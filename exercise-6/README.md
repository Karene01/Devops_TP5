# Apprentissages

## Pod Security et RBAC
Appliquer le moindre privilège aux identités et aux pods, pour neutraliser la kill chain complète observée à l'exo 2: RBAC trop large, token monté inutilement, pods sans contrainte de sécurité, aucune limite de ressources.

### Problème rencontré et pourquoi il est survenu
- RBAC excessif: 'deploy/redis/debug-rbac.yaml' liait le ServiceAccount 'default' du namespace 'data' au 'ClusterRole' 'cluster-admin' via un 'ClusterRoleBinding' nommé 'data-default-debug', laissé en place avec le commentaire "Temporary: lets the Redis pod 'see everything' while debugging". Résultat: tous les droits sur toutes les ressources de tous les namespaces.

- Token inutilement monté: aucun pod n'a besoin d'appeler l'API Kubernetes, pourtant le token du ServiceAccount était monté par défaut dans chaque pod. Une identité exploitable en cas de compromission, même sans RBAC permissif.

- Absence de contraintes sur les pods: ni 'runAsNonRoot', ni capacités supprimées, ni système de fichiers en lecture seule, ni profil seccomp. Combiné à l'absence de 'resources.limits' sur Redis, cela permettait l'exécution du faux mineur et une consommation CPU illimitée

- Effet de bord en réappliquant les manifestes: après avoir supprimé le 'ClusterRoleBinding' à la main, 'kubectl apply -n data -f deploy/redis/' l'a recréé automatiquement, car le fichier 'debug-rbac.yaml' existait toujours dans le dossier appliqué. La correction en ligne de commande seule ne suffit pas, il faut aussi supprimer le fichier source.

### Solution appliquée et pourquoi cette solution fonctionne
- Suppression définitive du RBAC excessif: 'kubectl delete clusterrolebinding data-default-debug' puis suppression du fichier 'deploy/redis/debug-rbac.yaml' lui-même, pour qu'un futur 'kubectl apply' ne le recrée plus.
- 'automountServiceAccountToken: false' ajouté au niveau pod: aucun des deux n'appelant l'API Kubernetes, le token ne leur sert à rien et ne doit pas être exposé.
- 'securityContext' niveau pod: 'runAsNonRoot: true', 'runAsUser'/'runAsGroup' explicites (999 pour Redis, 65532 pour le guestbook), 'fsGroup: 999' pour Redis, et 'seccompProfile: RuntimeDefault' pour filtrer les appels système dangereux.
- 'securityContext' niveau conteneur: 'allowPrivilegeEscalation: false', 'readOnlyRootFilesystem: true', 'capabilities.drop: ["ALL"]' empêche toute écriture hors des volumes explicitement montés et supprime toutes les capacités Linux superflues.
- 'resources.limits' ajoutées à Redis (cpu: 200m, memory: 128Mi) pour plafonner toute consommation excessive.
- Pod Security Standard 'restricted' appliqué aux namespaces guestbook et data, après avoir migré les pods existants pour éviter de bloquer sans prévenir.

### Ce que j'ai appris
- Une correction appliquée uniquement en ligne de commande ('kubectl delete') ne survit pas à un redéploiement si le manifeste source n'est pas corrigé en conséquence. La source de vérité reste le fichier, pas l'état du cluster à un instant donné. 
- 'readOnlyRootFilesystem: true' est une défense efficace contre les attaques de type "écrire puis exécuter un binaire malveillant", bien plus directe que de simplement limiter le CPU après coup. 
- Le sod security standard 'enforce' ne s'applique qu'à la création : il faut d'abord migrer les pods existants pour que la protection soit réellement effective, sinon le cluster continue de faire tourner silencieusement des pods non conformes.