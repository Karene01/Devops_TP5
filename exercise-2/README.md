# Apprentissages

## Exploitation

Court résumé de l’objectif visé

### Problème rencontré et pourquoi il est survenu

### Solution appliquée et pourquoi cette solution fonctionne

### Ce que j'ai appris

#### Commandes et réponses : 
curl -s -H "Host: guestbook.local" http://$IP/env
{
  "APP_VERSION": "v1.0.0",
  "AWS_ACCESS_KEY_ID": "keyID",
  "AWS_REGION": "eu-west-3",
  "AWS_SECRET_ACCESS_KEY": "key",
  "GUESTBOOK_PORT": "tcp://10.97.193.0:3000",
  "GUESTBOOK_PORT_3000_TCP": "tcp://10.97.193.0:3000",
  "GUESTBOOK_PORT_3000_TCP_ADDR": "10.97.193.0",
  "GUESTBOOK_PORT_3000_TCP_PORT": "3000",
  "GUESTBOOK_PORT_3000_TCP_PROTO": "tcp",
  "GUESTBOOK_SERVICE_HOST": "10.97.193.0",
  "GUESTBOOK_SERVICE_PORT": "3000",
  "GUESTBOOK_SERVICE_PORT_HTTP": "3000",
  "HOME": "/",
  "HOSTNAME": "guestbook-59885757fd-q5hwc",
  "KUBERNETES_PORT": "tcp://10.96.0.1:443",
  "KUBERNETES_PORT_443_TCP": "tcp://10.96.0.1:443",
  "KUBERNETES_PORT_443_TCP_ADDR": "10.96.0.1",
  "KUBERNETES_PORT_443_TCP_PORT": "443",
  "KUBERNETES_PORT_443_TCP_PROTO": "tcp",
  "KUBERNETES_SERVICE_HOST": "10.96.0.1",
  "KUBERNETES_SERVICE_PORT": "443",
  "KUBERNETES_SERVICE_PORT_HTTPS": "443",
  "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
  "REDIS_HOST": "redis.data.svc.cluster.local",
  "REDIS_PASSWORD": ""
}%         
Les variables sensibles : 
- AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY : identifiants cloud complets. Avec ça, un attaquant peut s’authentifier directement sur AWS avec l’API/CLI et agir avec les permissions associées à cette clé
- REDIS_PASSWORD : vide ici, mais le simple fait qu’elle soit exposée et vide confirme à l’attaquant qu’aucune authentification ne protège Redis. Une information stratégique pour la suite de l’attaque
- REDIS_HOST : moins critique seule, mais donne le nom DNS interne exact du service Redis, utile pour un attaquant qui chercherait à pivoter depuis un autre pod du cluster

#### Q2
J'ai "no database connection". En interrogeant directement le backend, on constate que le message injecté manuellement ("Redis est ouvert a tous") est bien présent et retourné par l'API. Preuve que l'app affiche sans distinction tout le contenu de la clé Redis guestbook, qu'il provienne du formulaire officiel ou d'un accès direct non authentifié à Redis.

FLUSHALL supprime immédiatement toutes les clés de toutes les bases Redis, sans confirmation. Un attaquant aurait pu effacer intégralement le contenu du guestbook, et plus largement, dans un contexte où Redis servirait à d'autres usages (cache, sessions), causer une panne applicative en cascade sans laisser de trace de son origine puisque aucune authentification n'est requise pour s'y connecter.

Problèmes de configurations : 
- Absence d'authentification sur Redis (REDIS_PASSWORD vide, confirmé dans /env et dans deploy/redis/values.yaml). N'importe qui peut exécuter n'importe quelle commande, y compris destructrice.
- Exposition réseau non maîtrisée : le service Redis est en type: LoadBalancer au lieu de ClusterIP, le rendant joignable depuis l'extérieur du cluster, jusqu'à la machine

#### Q3
Il s'installe dans /tmp/.x/ sous le nom de kworker, copié depuis /bin/sh. kworker est le nom des vrais threads noyau Linux, normalement présents et légitimes sur n'importe quel système Linux. En se faisant passer pour kworker, le processus malveillant se fond dans le bruit de fond du système et un administrateur qui scrute rapidement ps aux ne le remarquerait probablement pas, le confondant avec un processus noyau normal.

#### Q4
Redis consomme parce qu'aucune limite de ressources n'est définie dans redis-deployment.yaml. Sans limits.cpu, Kubernetes ne borne pas la consommation CPU du conteneur. Il peut utiliser autant de CPU disponible sur le nœud qu'il veut.

#### Q5
Le pod Redis utilise default dans le namespace data, c'est-à-dire le ServiceAccount créé automatiquement par Kubernetes, qui ne devrait normalement avoir aucun droit particulier.
Le fichier qui donne ces droit est /deploy/debug-rbac.yaml
Le fichier n'est pas chiffré. Le base64 n'est pas du chiffrement, c'est un simple encodage réversible sans clé.

#### Q6
- "securityContext.privileged: true" désactive l'isolation standard du conteneur : capacités Linux complètes, accès aux périphériques du node, contournement de seccomp/AppArmor par défaut
- volumes.hostPath.path: / monté sur /host monte la racine entière du système de fichiers du node à l'intérieur du conteneur, rendant lisible/modifiable absolument tout ce qui s'y trouve
- "hostPID: true" partage l'espace de noms des processus du node : le conteneur peut voir tous les processus tournant sur le node, pas seulement les siens

Kubernetes accepte ce pod parce qu'aucune restriction de sécurité n'empêche la création de pods privilégiés dans ce cluster. Kubernetes, par défaut, n'impose aucune limite sur les privilèges qu'un pod peut demander donc c'est à l'administrateur de les définir.