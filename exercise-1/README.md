# Apprentissages

## Titre d'exo

Court résumé de l’objectif visé

### Problème rencontré et pourquoi il est survenu

### Solution appliquée et pourquoi cette solution fonctionne

### Ce que j'ai appris

### Commandes et résultats : 
#### Question 1
Devops_TP5 git:(main) IP=$(minikube -p security ip)  
➜  Devops_TP5 git:(main) ✗ REDIS_IP=$(kubectl get svc -n data redis -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
➜  Devops_TP5 git:(main) ✗ echo $IP $REDIS_IP
192.168.67.2 127.0.0.1

#### Question 2
nmap -sV -p 80,443 $IP
Starting Nmap 7.993 ( https://nmap.org ) at 2026-11-18 16:15 +0100
Nmap scan report for localhost (127.0.0.1)

PORT    STATE SERVICE  VERSION
80/tcp  open  http     nginx (reverse proxy)
443/tcp open  ssl/http nginx (reverse proxy)
Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 18.34 seconds

nmap -sV -p 6379 $REDIS_IP
Starting Nmap 7.993 ( https://nmap.org ) at 2026-11-18 16:16 +0100
Nmap scan report for localhost (127.0.0.1)
Host is up (0.00018s latency).
PORT     STATE SERVICE VERSION
6379/tcp open  redis   Redis key-value store 7.4.12
Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 6.24 seconds

Ports appartenant à minikube/ Kubernetes lui-même :
8443 ou 6443 : l’API server Kubernetes
10250 : kubelet
10256, 10257, 10259 : kube-proxy, controller-manager, scheduler
Ports appartenant à l'application :
80/443 : l’Ingress qui route vers le guestbook
6379 : Redis, exposé via son service LoadBalancer

Service tournant sur 6379 : Redis 
Il est exposé via un service LoadBalancer dans deploy/redis/redis-service.yaml, jamais repassé en ClusterIP. Accessible sans mot de passe depuis n’importe quelle machine qui atteint le LoadBalancer.

#### Question 3 et 4
while read p; do
  curl -s -o /dev/null -w "%{http_code} $p\n" -H "Host: guestbook.local" "http://$IP$p"
done < attack/paths.txt
200 /
404 /.env
404 /.git/config
404 /wp-login.php
404 /admin
404 /actuator/env
404 /actuator/health
404 /server-status
404 /phpinfo.php
404 /debug
200 /env
200 /info
200 /metrics
200 /healthz
200 /lrange/guestbook
404 /backup.zip
404 /config.json

Les chemins répondant 200 mais ne devant pas exister en production sont /env, /info, /metrics, /healthz et /lrange/guestbook

/env:
Clés AWS en clair : AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY
REDIS_HOST : confirme le nom DNS interne (redis.data.svc.cluster.local), utile si l’attaquant a atterri dans le cluster
REDIS_PASSWORD vide : confirme qu’il n’y a aucune authentification sur Redis
Des infos d’infra interne (IP de Service Kubernetes, nom du pod guestbook-59885757fd-q5hwc) qui aident à cartographier le cluster depuis l’extérieur
Endpoint de debug laissé accessible en public, sans authentification, alors qu’il ne devrait exister ni en prod ni être routable depuis l’extérieur

/info: cet endpoint, censé donner des infos sur l’app guestbook, renvoie en fait la sortie de la commande Redis INFO (version 7.4.12, OS du conteneur, uptime, stats mémoire, rôle master, etc.). L’app agit comme un proxy transparent vers Redis, exposant du fingerprinting précis utile pour chercher des CVE ciblées sur cette version de Redis.
Même défaut qu’au-dessus : un endpoint de diagnostic exposé publiquement permet à un attaquant de cibler des CVE précises sans avoir à deviner la version

/metrics : Révèle la version du runtime Go (go1.27.4). Il confirme la liste des routes internes existantes via http_requests_total{handler="/env"...}, {handler="/healthz"}, etc. Un attaquant qui n’aurait pas eu paths.txt pourrait déduire les endpoints de debug juste en lisant ce fichier. Une métrique custom guestbook_redis_up confirme la dépendance à Redis
Les métriques Prometheus sont faites pour être scrapées depuis l’intérieur du cluster par un outil de monitoring, pas exposées publiquement sans contrôle d’accès

/healthz : Comme on a un corps vide, c’est un simple check de vivacité. Pas de fuite de données ici, mais il ne devrait toujours pas être exposé publiquement sans raison car il pourrait confirmer à un attaquant que le service tourne, et peut servir pour du fingerprinting ou juste pour vérifier qu’une attaque DoS a un effet.
Risque faible seul, mais fait partie du même défaut structurel : aucune séparation entre les routes publiques (/, poster un message) et les routes internes (debug, santé, métriques)



