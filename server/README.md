# Serveur de l’édition entreprise — Forgejo et récepteur de journaux

À déployer sur un serveur Linux avec Docker et Caddy .

## Installation

```bash
# Sur la VM, dans le dossier où vivent vos autres services
git clone https://github.com/Miinja/claude-recovery.git
cd claude-recovery/server

cp .env.example .env            # noms de domaine, réseau Docker de Caddy
cp tokens.example tokens.txt    # un jeton par clé : openssl rand -hex 32
chmod 600 .env tokens.txt

mkdir -p data/forgejo data/logs
sudo chown 1000:1000 data/forgejo
sudo chown 10001 data/logs      # utilisateur du conteneur log-receiver

docker compose up -d --build
```

Ajouter ensuite le contenu de `Caddyfile.snippet` au Caddyfile et recharger Caddy.

## Forgejo : premier réglage

L'inscription publique est fermée. Créer le compte administrateur en ligne de commande :

```bash
docker compose exec -u git forgejo forgejo admin user create \
  --admin --username admin --email admin@exemple.lan --random-password
```

Puis, dans l'interface (`https://<GIT_DOMAIN>`) :

1. Créer l'organisation `claude-recovery` et le dépôt privé `claude-recovery`.
2. Créer un compte par clé (`cle01`, …) en **lecture seule** sur ce dépôt, et un jeton
   d'accès (droit `read:repository`) pour chacun. Ce jeton va dans `RECOVERY_GIT_URL`
   sur la clé (`/etc/claude-recovery/config.env`).
3. Depuis le poste de développement, pousser le dépôt :

```bash
git remote add forgejo https://<GIT_DOMAIN>/atelier/claude-recovery.git
git push forgejo main
```

## Journaux

- Les commandes arrivent dans `data/logs/<job>/commands.jsonl`, les rapports dans
  `data/logs/<job>/rapport.md` (les versions précédentes sont conservées).
- Test depuis n'importe quel poste du réseau :

```bash
curl https://<LOGS_DOMAIN>/healthz
curl -H "Authorization: Bearer <jeton>" -H 'Content-Type: application/x-ndjson' \
  -d '{"job":"test","command":"echo ok"}' https://<LOGS_DOMAIN>/api/logs
```

- Clé perdue : supprimer sa ligne dans `tokens.txt` (effet immédiat), révoquer son jeton
  Forgejo, et déconnecter sa session dans les réglages du compte Claude.

## Certificat interne

Avec `tls internal`, Caddy signe les certificats avec sa propre autorité. Pour que les
clés l'acceptent, copier le certificat racine de Caddy
(`/data/caddy/pki/authorities/local/root.crt` dans le conteneur Caddy) dans
`build/ca/` (extension `.crt`) avant de construire l'image : le build l'ajoute aux
autorités de confiance de la clé.

## Sauvegarde

Tout l'état est dans `server/data/` (dépôts Forgejo, journaux) : l'ajouter à la
sauvegarde existante de la VM.
