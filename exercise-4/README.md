# Apprentissages

## Les secrets et l'image
L'objectif de cet exercice était de corriger à la source les failles exploitées à l'exo 2: supprimer la fuite de secrets (clés AWS, endpoints de debug), faire tourner l'image en non-root, et scanner/corriger les vulnérabilités des images.

### Problème rencontré et pourquoi il est survenu
- Fuite de secrets: les clés AWS étaient injectées dans le pod via un  Secret Kubernetes ('deploy/guestbook/templates/secret.yaml'), lui-même alimenté par 'deploy/guestbook/values.yaml' et monté dans le conteneur via 'envFrom.secretRef' dans 'deployment.yaml'. Elles devenaient ainsi accessibles via l'endpoint '/env' du guestbook ('guestbook/main.go', fonction 'EnvHandler'), sans aucune authentification.

- Image en root: le Dockerfile du guestbook ne définissait aucun utilisateur. Sans instruction 'USER', le conteneur tournait par défaut en 'root', ce qui aggrave l'impact de toute compromission du processus applicatif.

- Vulnérabilités du code: trivy image a détecté 2 CVEs HIGH sur golang.org/x/net v0.59.0 (déni de service via HTML malveillant, et via trop de frames HTTP/2 SETTINGS), une dépendance indirecte du projet.

- Vulnérabilités de l'image Redis: trivy image redis:7 a remonté 41 CVEs (40 HIGH, 1 CRITICAL), la majorité provenant de paquets système Debian ('util-linux', 'apt', 'perl-base') non utilisés par Redis en fonctionnement normal, mais constituant une surface d'attaque inutile si un attaquant obtient un shell dans le conteneur.

### Solution appliquée et pourquoi cette solution fonctionne
- Suppression de la fuite: retrait du bloc aws dans 'values.yaml', suppression de 'secret.yaml', retrait du 'secretRef' dans 'deployment.yaml'. Les handlers '/env' et '/info' étaient déjà absents du code source. La persistance de la fuite observée en exercice 2 venait d'une image Docker figée sur un ancien build, antérieur à cette suppression côté code.
- Non-root : ajout de USER 65532:65532' dans le Dockerfile, fonctionnel sans créer d'utilisateur explicite car scratch n'a pas de '/etc/passwd' à consulter et Kubernetes applique directement l'UID/GID numérique.
- Correction CVE guestbook : 'go get golang.org/x/net@latest' puis 'go mod tidy', passant la dépendance de v0.59.0 à v0.63.0. Rescan Trivy après rebuild : 0 vulnérabilité HIGH/CRITICAL.
- Choix du tag Redis: redis:7 remplacé par un tag plus restreint pour réduire drastiquement la surface de paquets système exposés.

### Ce que j'ai appris

- Un fichier source corrigé ne protège rien tant que l'image qui tourne n'a pas été reconstruite et redéployée. Le code et l'artefact déployé peuvent diverger silencieusement.

- Une CVE 'HIGH' n'est pas automatiquement exploitable. Il faut vérifier si le code vulnérable est réellement atteint avant de la traiter en urgence absolue, même si la corriger reste une bonne pratique. 

- 'scratch' simplifie le passage en non-root 

- 'gitleaks' et le push protection de GitHub portent sur des cibles différentes mais complémentaires. L'historique Git entier, y compris les fichiers de documentation qu'on pense anodins comme un secret, même factice, doit toujours être masqué avant d'être écrit où que ce soit dans le dépôt