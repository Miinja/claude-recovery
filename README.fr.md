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

## Prérequis et recommandations

### La clé USB

| | Minimum | Recommandé |
|---|---|---|
| Capacité | 4 Go | 32 Go |
| Interface | USB 2.0 | USB 3.0 ou plus récent |

- L'image occupe 1,4 Go et l'installeur refuse une clé qui n'a pas 2 Go libres après
  elle, d'où le minimum de 4 Go.
- L'espace qui reste après l'image est partagé en deux au premier démarrage : la
  persistance (connexion Claude, réglages, journaux ; la moitié de l'espace libre, 16 Go
  au plus) et la partition `CR-WINDOWS` du mode Windows. Une clé de 32 Go donne environ
  14 Go de persistance ; à partir de 64 Go elle reste à 16 Go et seule `CR-WINDOWS`
  grandit.
- Tout le système est lu depuis la clé : en USB 2.0 elle démarre et fonctionne, mais
  lentement. Préférez une clé USB 3 de marque connue, branchée sur un port USB 3.
- Réservez une clé à cet usage : elle est entièrement effacée et ne doit rien contenir
  d'autre. L'installeur signale les disques de plus de 130 Go, qui sont en général des
  disques externes.
- Chiffrez la persistance (proposé au premier démarrage) si la clé sort de chez vous ou de
  l'atelier : elle contient la session du compte Claude et, en édition entreprise, le
  jeton du serveur.

### Le PC que l'on démarre

- Processeur Intel ou AMD 64 bits. Le démarrage fonctionne en BIOS comme en UEFI ; l'image
  prend en charge Secure Boot.
- Pas les tout premiers PC 64 bits : Claude Code lui-même demande un processeur assez
  récent. En test, il a planté (« instruction non permise ») sur le modèle de processeur
  64 bits de base et fonctionné sur un modèle récent ; la limite exacte n'a pas été
  mesurée. La clé démarre quand même sur un tel PC, mais Claude ne se lance pas.
- 4 Go de mémoire : c'est la configuration avec laquelle la clé a été testée (en machine
  virtuelle) ; 8 Go sont plus confortables.
- Une connexion Internet, filaire si possible : Claude Code en a besoin pendant toute la
  session.
- Un compte Claude.

### Le disque de destination

Les fichiers récupérés ne vont jamais sur la clé ni sur le disque à récupérer : il faut un
troisième disque.

- Capacité : au moins la taille du disque à récupérer, puisque la première étape en fait
  un clone complet. Le double est confortable, car les fichiers récupérés sont recopiés à
  côté du clone.
- Un disque en bon état, formaté en exFAT ou en NTFS pour que le résultat soit lisible
  sous Windows.
- Branchez-le sur un autre port USB que la clé, avec un hub alimenté si le PC a peu de
  ports.

### Avant de commencer

- Cessez tout de suite d'utiliser le disque en panne : chaque écriture peut détruire ce
  qui est encore récupérable.
- Un disque qui claque, qui n'est plus détecté du tout ou qui est tombé relève d'un
  laboratoire, pas d'un logiciel. Claude le dit quand les symptômes vont dans ce sens.
- Créez et essayez la clé avant d'en avoir besoin, sur un PC qui fonctionne.

## Créer une clé

### Sous Windows : l'installeur

Télécharger `ClaudeRecoveryInstaller.exe` depuis la dernière release, le lancer, puis :

1. choisir la langue et l'édition ;
2. choisir la clé USB (elle est entièrement effacée) ;
3. édition entreprise : remplir les réglages ;
4. **Écrire la clé**. L'installeur télécharge l'image, vérifie son empreinte, l'écrit,
   puis relit la clé pour contrôle.

### Les options de l'installeur

| Option | Ce qu'elle fait | Où trouver la valeur |
|---|---|---|
| **FR / EN** | Langue de l'installeur, des messages de la clé et de la procédure de Claude | Au choix. Se change ensuite sur la clé avec `claude-recovery lang fr` |
| **Particulier / Entreprise** | L'image qui sera écrite | Particulier : vous récupérez vos propres fichiers. Entreprise : un technicien intervient pour des clients et chaque commande est journalisée |
| **Choisir la clé USB** | Le disque qui sera effacé | Seuls les disques USB sont proposés. Un disque de plus de 130 Go est signalé en rouge : vérifiez que ce n'est pas un disque de sauvegarde |
| **Utiliser un fichier local…** | Écrit un `.iso` que vous avez déjà, au lieu de télécharger la dernière release | Une image téléchargée depuis les [releases](https://github.com/Miinja/claude-recovery/releases), ou construite avec `build/build-iso.sh` |
| **Aide en ligne** | Ouvre cette page | |

Réglages de l'édition entreprise (lien « Remplir les réglages… » sous l'édition) :

| Champ | Obligatoire | Où trouver la valeur |
|---|---|---|
| **Nom de l'entreprise** | Non | Le nom de votre atelier ou de votre société. Il sert seulement à identifier à qui appartient la clé |
| **Nom de cette clé** | Oui | Un nom que vous choisissez, par exemple `cle01`. Prenez celui écrit sur la ligne de cette clé dans `tokens.txt`, sur votre serveur |
| **Serveur de journaux** | Non | `https://` suivi de la valeur `LOGS_DOMAIN` du fichier `server/.env` de votre serveur (voir [server/README.fr.md](server/README.fr.md)). Vide : le journal reste sur la clé |
| **Jeton de la clé** | Avec un serveur de journaux | Le jeton de la ligne de cette clé dans `server/tokens.txt` (`nom jeton`). Pour en créer un sur le serveur : `openssl rand -hex 32`, ajoutez la ligne, aucun redémarrage n'est nécessaire |
| **Dépôt de mise à jour** | Non | Laissez vide pour suivre ce dépôt GitHub. Indiquez l'adresse `https` de votre propre copie seulement si l'entreprise en héberge une |

**Tester le serveur** vérifie, depuis votre PC, que le serveur de journaux répond et
accepte le jeton. Il n'écrit rien sur le serveur. Avec le certificat interne de Caddy, le
test signale un certificat non reconnu : c'est attendu sur un PC qui ne possède pas ce
certificat ; la clé, elle, l'accepte si l'image a été construite avec (voir
[server/README.fr.md](server/README.fr.md)).

### Sous Linux

```
sudo scripts/make-key.sh particulier /dev/sdX fr
sudo scripts/make-key.sh entreprise  /dev/sdX fr
```

### Premier démarrage

Démarrer un PC sur la clé : l'assistant se lance tout seul. La première fois, il propose
de créer l'espace de persistance de la clé (chiffré par une phrase de passe, si on le
souhaite) : c'est lui qui garde la connexion au compte Claude, les réglages et les
journaux d'un démarrage à l'autre. Un redémarrage plus tard, la clé est opérationnelle.

## Utilisation

L'assistant démarre de lui-même avec la clé ; tout se choisit avec les flèches et Entrée.
Pour le relancer après l'avoir quitté, taper `claude-recovery`.

1. **Langue et clavier**, demandés une seule fois (la langue de l'installeur est reprise
   s'il y en a une).
2. **Réseau** : un câble est détecté tout seul ; sinon un menu liste les réseaux Wi-Fi et
   demande le mot de passe.
3. **Mise à jour** de la clé (`git pull`).
4. **Disque à récupérer**, choisi dans une liste qui affiche taille, modèle, connexion et
   numéro de série. Il est aussitôt **verrouillé en lecture seule dans le noyau** : plus
   aucune commande ne peut y écrire, et un montage se fait en lecture seule.
5. **Destination**, choisie parmi les partitions des autres disques. La clé et le disque à
   récupérer ne sont pas proposés, et une destination trop petite pour un clone complet
   est signalée.
6. Claude Code démarre dans le dossier du job. Les choix ci-dessus lui sont transmis comme
   des faits, dans un fichier `CLAUDE.md` écrit dans ce dossier.

En édition entreprise, l'assistant demande aussi le technicien et la référence du job ; à
la fermeture, les journaux en attente et `report.md` partent au serveur. Hors ligne, tout
reste sur la clé et part à la prochaine session connectée.

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
  lib.sh                 Fonctions communes (édition, langue, bloc de réglages, disques)
  ui.sh                  Menus de l'assistant (whiptail, questions simples en secours)
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
3. Le disque à récupérer est verrouillé en lecture seule dans le noyau
   (`blockdev --setro`) dès qu'il est désigné : cela tient quelle que soit la commande
   lancée. Le verrou tombe si le disque est débranché ; la procédure demande à Claude de
   le vérifier et de le remettre.
4. Les commandes destructrices sont aussi bloquées dans `settings.json`, et reprises en
   paramètres gérés (`/etc/claude-code/managed-settings.json`) pour qu'aucun réglage local
   ne les lève. Ces règles par motifs sont un garde-fou, pas une barrière étanche : la
   vraie barrière est le verrou du noyau ci-dessus.
5. Aucune donnée client ni aucun jeton dans ce dépôt (voir `.gitignore`).
6. Une clé se met à jour depuis ce dépôt à chaque session : qui peut pousser sur `main`
   peut modifier la procédure de toutes les clés. Protéger la branche.
7. Une clé entreprise perdue se révoque en trois endroits : le jeton du serveur de
   journaux, le jeton du dépôt de mise à jour, la session du compte Claude. D'où
   l'intérêt de chiffrer la persistance.

## Statut

- [x] Procédures des deux éditions et du mode Windows, en français et en anglais
- [x] Journalisation et envoi au serveur — testés de bout en bout en local
- [x] Bloc de réglages installeur → clé — testé (écriture Windows, relecture Linux)
- [x] Installeur Windows — compile ; copie, bloc, relecture et reprise de téléchargement testés (sur fichier, et contre un serveur qui coupe les connexions)
- [ ] Installeur Windows — écriture sur une vraie clé USB **jamais essayée**
- [x] Build des images — les deux éditions se construisent dans un conteneur `debian:trixie`, et le workflow de release a tourné sur GitHub
- [x] Assistant de démarrage — testé en machine virtuelle : menus, choix des disques, verrou en lecture seule (une écriture directe est refusée, un montage est forcé en lecture seule), avertissement d'espace insuffisant. Le menu Wi-Fi n'a **pas** été testé (pas de Wi-Fi en machine virtuelle)
- [x] Premier démarrage — testé en machine virtuelle (QEMU) : démarrage BIOS et UEFI, persistance en clair et chiffrée, réglages de l'installeur appliqués (édition entreprise), second démarrage avec persistance active
- [ ] Premier démarrage sur une vraie clé USB — **jamais essayé**
- [x] Mode Windows — lanceur testé sur un PC pour les deux éditions, avec un programme témoin à la place de Claude (configuration isolée, journal, rapport, nettoyage)
- [ ] Mode Windows — une vraie session Claude sur le PC d'un client n'a **jamais été essayée**
- [ ] Serveur de journaux et Forgejo — fichiers prêts dans `server/`, à déployer

### Scénarios de récupération testés

Chaque scénario se joue sur un faux disque (un fichier image) contenant 15 fichiers :
12 photos JPEG, un PNG, un PDF et un document Word. Le disque est attaché en lecture
seule, cloné avec `ddrescue`, et le travail se fait sur le clone. Un fichier ne compte
comme retrouvé que si son empreinte SHA-256 est celle de l'original.

| Scénario | Outil utilisé sur le clone | Retrouvés intacts | Noms et dossiers |
|---|---|---|---|
| Carte FAT32 formatée par erreur | `photorec` | 15 / 15 | Perdus (normal avec PhotoRec) |
| Fichiers supprimés sur NTFS, corbeille vidée | `ntfsundelete --truncate` | 15 / 15 | Noms conservés, dossiers perdus |
| Table de partitions effacée, disque vu « non initialisé » | `testdisk` pour localiser la partition, montage en lecture seule | 15 / 15 | Conservés |
| Disque avec secteurs défectueux (2 zones illisibles, 192 secteurs) | `ddrescue`, puis montage du clone en lecture seule | 14 / 15 | Conservés |

Dans tous les scénarios, l'empreinte du disque source est identique avant et après. Dans
le dernier, `ddrescue` a sauvé 99,96 % du disque ; la photo qui se trouvait sur une zone
illisible revient abîmée.

Ce sont des cas favorables : petits disques, fichiers non fragmentés, formatage rapide.
Ils montrent que les outils embarqués sur la clé fonctionnent sur les pannes classiques ;
de vrais disques feront moins bien. Les commandes ont été lancées à la main en suivant la
procédure, pas par une session Claude.

## Licence

Copyright (C) 2026 Miinja

Ce programme est un logiciel libre : vous pouvez le redistribuer et le modifier selon les
termes de la licence publique générale GNU (GPL), version 3, publiée par la Free Software
Foundation. Il est distribué dans l'espoir qu'il sera utile, mais SANS AUCUNE GARANTIE.
Le texte complet est dans [LICENSE](LICENSE).

La récupération de données comporte des risques. Ce logiciel est fourni tel quel ; vous
restez responsable des disques sur lesquels vous intervenez.
