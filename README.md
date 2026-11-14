# Claude Recovery

Clé USB bootable de récupération de données pilotée par **Claude Code**, pour ORDIServices.

## Principe

- **Mode boot (Linux live)** : on démarre n'importe quel PC sur la clé ; Claude Code
  diagnostique et récupère les données (ddrescue, testdisk, photorec, smartctl…).
- **Mode Windows** : un script lancé depuis le Windows du client installe Claude Code
  temporairement pour diagnostiquer un bug logiciel/navigateur, puis nettoie tout.
- **Serveur ORDIServices** (support, pas de calcul) : dépôt de config (Forgejo),
  réception des logs d'intervention, stockage des images et fichiers récupérés.

## Utilisation

### Sur la clé (mode boot)

```
ordi
```

La commande met la clé à jour (`git pull`), demande le technicien, la référence du job
et le dossier de destination, puis lance Claude Code dans le dossier du job. À la
fermeture, les journaux en attente et `rapport.md` partent au serveur. Hors ligne, tout
reste sur la clé et part à la prochaine session connectée.

La connexion au compte Claude est mémorisée sur la partition de persistance.

### Chez le client (mode Windows)

Depuis la partition `ORDI-WIN` de la clé, dans PowerShell :

```
powershell -ExecutionPolicy Bypass -File .\windows\start-claude.ps1
```

Le technicien se connecte au compte Claude à chaque session. À la fermeture : déconnexion,
rapport recopié sur la clé, suppression de tout ce que la session a ajouté au PC.

### Fabriquer une clé

```
sudo build/build-iso.sh                                             # sur une machine Debian
sudo scripts/make-key.sh build/out/claude-recovery-AAAAMMJJ.iso /dev/sdX --luks
```

Puis, au premier démarrage de la clé : renseigner `/etc/ordi/ordi.env`
(modèle : `config/ordi.env.example`) et lancer `ordi`.

## Arborescence

```
config/
  CLAUDE.md              Procédure suivie par Claude sur la clé (→ ~/.claude/CLAUDE.md)
  settings.json          Permissions + hooks de la clé (→ ~/.claude/settings.json)
  CLAUDE.windows.md      Procédure du mode Windows
  settings.windows.json  Permissions + hooks du mode Windows
  ordi.env.example       Réglages propres à une clé (URL du dépôt, jetons)
hooks/
  log-command.sh         Journalise chaque commande de Claude, file d'attente hors ligne
build/
  packages.txt           Paquets installés dans l'image live
  build-iso.sh           Construction de l'image (Debian live-build)
  hooks/                 Hook live-build : installation de Claude Code dans l'image
  ca/                    (facultatif) certificat racine interne à embarquer
scripts/
  ordi-session.sh        Lanceur de session (commande `ordi`)
  ordi-update.sh         git pull + installation de la config (commande `ordi-update`)
  ordi-update.service    Même mise à jour, au démarrage de la clé
  make-key.sh            Écrit l'image sur une clé et crée persistance + partition Windows
  update-keys.sh         Met à jour les clés branchées sur un poste, sans les démarrer
windows/
  start-claude.ps1       Mode Windows : installation temporaire, session, nettoyage
  log-command.ps1        Journalisation des commandes en mode Windows
server/
  docker-compose.yml     Forgejo + récepteur de journaux (derrière le Caddy existant)
  log-receiver/          Service HTTP de réception des journaux et rapports
  README.md              Déploiement sur la VM Debian
```

## Règles de sécurité (non négociables)

1. Le disque source n'est **jamais** écrit : clonage ddrescue d'abord, travail sur l'image.
2. Claude travaille sur les **métadonnées** et n'ouvre pas le contenu des fichiers clients sans raison.
3. Commandes destructrices bloquées dans `settings.json`, et reprises en paramètres gérés
   (`/etc/claude-code/managed-settings.json`) pour qu'aucun réglage local ne les lève.
   Ces règles sont un garde-fou, pas une barrière étanche : la présence du technicien reste la règle.
4. Aucune donnée client ni aucun jeton dans ce dépôt (voir `.gitignore`).
5. Une clé perdue se révoque en trois endroits : `server/tokens.txt`, le jeton Forgejo de la
   clé, la session du compte Claude. D'où l'intérêt de chiffrer la persistance (`--luks`).

## Statut

- [x] Squelette du projet
- [x] Procédure `CLAUDE.md` finalisée
- [x] Hooks de traçabilité → serveur (écrits et testés en local)
- [ ] Build de la clé (base Debian live) — scripts écrits, **jamais exécutés** : à valider sur une machine Debian
- [ ] Mode Windows — script écrit, à valider sur un PC de test
- [ ] Forgejo sur le serveur ORDIServices — fichiers prêts dans `server/`, à déployer sur la VM
