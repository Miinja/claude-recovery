# Claude Recovery

[English](README.md) · **Français**

Clé USB bootable de récupération de données pilotée par **Claude Code**.

On démarre n'importe quel PC sur la clé ; Claude Code diagnostique le disque, le clone,
puis récupère les fichiers (ddrescue, testdisk, photorec, smartctl…), sans jamais écrire
sur le disque d'origine.

> Projet indépendant, ni affilié à Anthropic ni approuvé par elle. « Claude » et
> « Claude Code » sont des marques d'Anthropic. Un compte Claude est nécessaire pour
> utiliser la clé.

## Deux éditions

| | **Particulier** | **Entreprise** |
|---|---|---|
| Pour qui | Une personne qui récupère ses propres fichiers | Un technicien qui intervient pour un client |
| Ton de Claude | Explique chaque étape, sans jargon ; dit quand il vaut mieux s'arrêter et voir un professionnel | Court et factuel |
| Journal des commandes | Sur la clé uniquement | Sur la clé **et** envoyé au serveur de l'entreprise |
| Rapport de fin de job | Dans le dossier de récupération | Idem, et envoyé au serveur |
| Réglages à la création | Langue | Langue, nom de la clé, serveur de journaux et jeton, dépôt de mise à jour (facultatif) |
| Mode Windows (diagnostic d'un bug logiciel) | Oui, procédure pour un non-spécialiste | Oui, procédure technicien |
| Mises à jour | Dépôt GitHub du projet | Dépôt GitHub, ou le dépôt de l'entreprise |

L'édition est fixée dans l'image. Les deux images sont publiées dans les
[releases](https://github.com/Miinja/claude-recovery/releases).

## Langues

Tout existe en **français et en anglais** : l'installeur, les messages de la clé et les
procédures que suit Claude.

- La langue se choisit dans l'installeur, qui l'inscrit sur la clé.
- Elle se change à tout moment sur la clé :

```
claude-recovery lang fr
claude-recovery lang en
```

## Créer une clé

### Sous Windows : l'installeur

Télécharger `ClaudeRecoveryInstaller.exe` depuis la dernière release, le lancer, puis :

1. choisir la langue et l'édition ;
2. choisir la clé USB (elle est entièrement effacée) ;
3. édition entreprise : remplir les réglages ;
4. **Écrire la clé**. L'installeur télécharge l'image, vérifie son empreinte, l'écrit,
   puis relit la clé pour contrôle.

### Sous Linux

```
sudo scripts/make-key.sh particulier /dev/sdX fr
sudo scripts/make-key.sh entreprise  /dev/sdX fr
```

### Premier démarrage

Démarrer un PC sur la clé et taper `claude-recovery`. La première fois, la clé propose de
créer son espace de persistance (chiffré par une phrase de passe, si on le souhaite) :
c'est lui qui garde la connexion au compte Claude, les réglages et les journaux d'un
démarrage à l'autre. Un redémarrage plus tard, la clé est opérationnelle.

## Utilisation

```
claude-recovery
```

La commande met la clé à jour (`git pull`), prépare le dossier de travail sur le disque de
destination, puis lance Claude Code dedans. En édition entreprise, elle demande le
technicien et la référence du job ; à la fermeture, les journaux en attente et
`report.md` partent au serveur. Hors ligne, tout reste sur la clé et part à la prochaine
session connectée.

### Mode Windows

Depuis la partition `CR-WINDOWS` de la clé, dans PowerShell :

```
powershell -ExecutionPolicy Bypass -File .\windows\start-claude.ps1
```

Le script suit la procédure de l'édition et de la langue de la clé (`-Lang fr|en` pour en
changer). On se connecte au compte Claude à chaque session. À la fermeture : déconnexion,
rapport recopié sur la clé, suppression de tout ce que la session a ajouté au PC.

## Publier une release

```
git tag v0.1.0
git push origin v0.1.0
```

Le workflow `.github/workflows/release.yml` construit les deux images et l'installeur,
puis crée la release. Les noms de fichiers sont fixes (`claude-recovery-particulier.iso`,
`claude-recovery-entreprise.iso`, `ClaudeRecoveryInstaller.exe`) : l'installeur et
`make-key.sh` vont toujours chercher la dernière release.

## Arborescence

```
config/
  entreprise/            Édition entreprise : procédure (CLAUDE.<langue>.md), permissions, modèle de réglages
  particulier/           Édition particulier : procédure et permissions
  windows/               Mode Windows : une procédure par édition et par langue, permissions
hooks/
  log-command.sh         Journalise chaque commande de Claude, file d'attente hors ligne
scripts/
  session.sh             Lanceur de session (commande `claude-recovery`)
  firstboot.sh           Premier démarrage : réglages de l'installeur, persistance
  update.sh              git pull + installation de la config (commande `claude-recovery-update`)
  lib.sh                 Fonctions communes (édition, langue, bloc de réglages)
  make-key.sh            Création d'une clé depuis Linux
  update-keys.sh         Met à jour les clés branchées sur un poste, sans les démarrer
build/
  build-iso.sh           Construction d'une édition (Debian live-build)
  packages.txt           Paquets de l'image
  hooks/                 Hook live-build : installation de Claude Code dans l'image
installer/
  src/                   Installeur Windows (C#, .NET Framework livré avec Windows)
  build.ps1              Compilation, sans SDK à installer
windows/
  start-claude.ps1       Mode Windows : installation temporaire, session, nettoyage
  log-command.ps1        Journalisation des commandes en mode Windows
server/
  docker-compose.yml     Récepteur de journaux + Forgejo, derrière Caddy
  log-receiver/          Service HTTP de réception des journaux et rapports
.github/workflows/
  release.yml            Build des images et de l'installeur, publication
```

### Comment les réglages arrivent sur la clé

Windows ne sait pas créer de partition Linux. L'installeur écrit donc l'image, puis dépose
les réglages dans un petit bloc brut juste après elle (format décrit dans
`scripts/lib.sh`). Au premier démarrage, la clé lit ce bloc, crée sa partition de
persistance, y range les réglages, puis efface le bloc.

## Règles de sécurité

1. Le disque source n'est **jamais** écrit : clonage ddrescue d'abord, travail sur l'image.
2. Claude travaille sur les **métadonnées** et n'ouvre pas le contenu des fichiers sans raison.
3. Commandes destructrices bloquées dans `settings.json`, et reprises en paramètres gérés
   (`/etc/claude-code/managed-settings.json`) pour qu'aucun réglage local ne les lève.
   Ces règles sont un garde-fou, pas une barrière étanche.
4. Aucune donnée client ni aucun jeton dans ce dépôt (voir `.gitignore`).
5. Une clé se met à jour depuis ce dépôt à chaque session : qui peut pousser sur `main`
   peut modifier la procédure de toutes les clés. Protéger la branche.
6. Une clé entreprise perdue se révoque en trois endroits : le jeton du serveur de
   journaux, le jeton du dépôt de mise à jour, la session du compte Claude. D'où
   l'intérêt de chiffrer la persistance.

## Statut

- [x] Procédures des deux éditions et du mode Windows, en français et en anglais
- [x] Journalisation et envoi au serveur — testés de bout en bout en local
- [x] Bloc de réglages installeur → clé — testé (écriture Windows, relecture Linux)
- [x] Installeur Windows — compile ; copie, bloc et relecture testés sur fichier
- [ ] Installeur Windows — écriture sur une vraie clé USB **jamais essayée**
- [x] Build des images — les deux éditions se construisent dans un conteneur `debian:trixie`, et le workflow de release a tourné sur GitHub
- [x] Premier démarrage — testé en machine virtuelle (QEMU) : démarrage BIOS et UEFI, persistance en clair et chiffrée, réglages de l'installeur appliqués (édition entreprise), second démarrage avec persistance active
- [ ] Premier démarrage sur une vraie clé USB — **jamais essayé**
- [ ] Mode Windows — à valider sur un PC de test
- [ ] Serveur de journaux et Forgejo — fichiers prêts dans `server/`, à déployer

## Licence

Copyright (C) 2026 Miinja

Ce programme est un logiciel libre : vous pouvez le redistribuer et le modifier selon les
termes de la licence publique générale GNU (GPL), version 3, publiée par la Free Software
Foundation. Il est distribué dans l'espoir qu'il sera utile, mais SANS AUCUNE GARANTIE.
Le texte complet est dans [LICENSE](LICENSE).

La récupération de données comporte des risques. Ce logiciel est fourni tel quel ; vous
restez responsable des disques sur lesquels vous intervenez.
