# Claude Recovery

Clé USB bootable de récupération de données pilotée par **Claude Code**, pour ORDIServices.

## Principe

- **Mode boot (Linux live)** : on démarre n'importe quel PC sur la clé ; Claude Code
  diagnostique et récupère les données (ddrescue, testdisk, photorec, smartctl…).
- **Mode Windows** : un script lancé depuis le Windows du client installe Claude Code
  temporairement pour diagnostiquer un bug logiciel/navigateur, puis nettoie tout.
- **Serveur ORDIServices** (support, pas de calcul) : dépôt de config (Forgejo),
  réception des logs d'intervention, stockage des images et fichiers récupérés.

## Arborescence

```
config/
  CLAUDE.md          Procédure que Claude suit sur la clé (→ ~/.claude/CLAUDE.md)
  settings.json      Permissions + hooks Claude Code (→ ~/.claude/settings.json)
hooks/
  log-command.sh     Journalise chaque commande lancée par Claude (traçabilité)
build/
  packages.txt       Paquets installés dans l'image live
  build-iso.sh       Construction de l'image de la clé (à compléter)
scripts/
  update-keys.sh     Met à jour toutes les clés branchées sur le poste
  ordi-update.service  Service systemd : git pull de la config au démarrage
windows/
  start-claude.ps1   Mode Windows (à compléter)
```

## Règles de sécurité (non négociables)

1. Le disque source n'est **jamais** écrit : clonage ddrescue d'abord, travail sur l'image.
2. Claude travaille sur les **métadonnées** et n'ouvre pas le contenu des fichiers clients sans raison.
3. Commandes destructrices bloquées dans `settings.json` (et via les paramètres gérés entreprise).
4. Aucune donnée client dans ce dépôt (voir `.gitignore`).

## Statut

- [x] Squelette du projet
- [ ] Procédure `CLAUDE.md` finalisée
- [ ] Build de la clé (base Debian live)
- [ ] Hooks de traçabilité → serveur
- [ ] Mode Windows
- [ ] Forgejo sur le serveur ORDIServices
