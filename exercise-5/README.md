# Apprentissages

## Signer l'image avec Cosign

Prouver que le cluster peut vérifier qu'une image provient bien de moi et n'a pas été modifiée dans le registry : signer l'image avec Cosign, y attacher une SBOM, puis simuler une substitution d'image pour vérifier que la signature la détecte.

### Problème rencontré et pourquoi il est survenu
- Confusion localhost vs host.docker.internal : sur Mac, le daemon Docker ne tourne pas directement sur la machine mais dans une VM Linux. docker tag/docker push, exécutés par ce daemon, résolvent localhost depuis l'intérieur de la VM, pas depuis le Mac où tournait mon 'kubectl port-forward -n kube-system svc/registry 5000:80'. Résultat : 'docker push localhost:5000/...' timeout systématiquement, alors qu'un simple 'curl http://localhost:5000/v2/' depuis le Mac répondait parfaitement. À l'inverse, cosign, curl et trivy s'exécutent nativement sur macOS et utilisent bien localhost:5000 sans problème.

- Registry en HTTP non sécurisé: 'docker push host.docker.internal:5000/...' échouait avec "server gave HTTP response to HTTPS client", car Docker tente du HTTPS par défaut alors que le registry minikube répond en HTTP simple.

- Instabilité récurrente de Docker Desktop: plusieurs redémarrages forcés de Docker Desktop pendant la session ont coupé le conteneur minikube, le tunnel et le port-forward, nécessitant de tout relancer à chaque fois.

### Solution appliquée et pourquoi cette solution fonctionne
- Registry HTTP autorisé: ajout de insecure-registries: ["host.docker.internal:5000"] dans Docker Desktop (Settings -> Docker Engine), ce qui autorise explicitement ce registry en HTTP.
- Séparation des usages localhost / host.docker.internal : docker tag/docker push utilisent systématiquement host.docker.internal:5000, tandis que cosign/curl/trivy utilisent localhost:5000 (vu depuis macOS). Les deux pointent vers le même registry via le même port-forward, seul le chemin réseau diffère selon qui émet la requête.
- Signature du digest, pas du tag : récupération du digest exact depuis la sortie du docker push, puis cosign generate-key-pair, cosign attest --predicate sbom.json --type cyclonedx pour la SBOM, et cosign sign pour la signature, tous les deux ciblant 'guestbook@sha256:...' et non 'guestbook:v1.1.0'.
- Preuve de détection: poussé redis:7 sous le tag 'v1.1.0', puis 'cosign verify --key cosign.pub localhost:5000/guestbook:v1.1.0' -> 'Error: no signatures found', confirmant qu'aucune signature n'existe pour ce nouveau digest.

### Ce que j'ai appris
- Signer le digest plutôt que le tag est la seule garantie réelle d'intégrité : un tag est un simple pointeur mutable que n'importe qui avec accès au registry peut réassigner, alors qu'un digest identifie un contenu unique et immuable.
- Sur Docker Desktop Mac, il faut distinguer qui émet la requête réseau : le daemon Docker (dans sa VM Linux, donc 'host.docker.internal') contre un outil natif macOS ('localhost'). Une même adresse ne désigne pas la même machine selon l'outil utilisé.
- 'cosign.key' protégé par passphrase et jamais commité (via .gitignore) est l'unique moyen de produire une signature valide. Sans elle, même un attaquant ayant un accès complet au registry ne peut pas forger une signature acceptée par 'cosign verify'.