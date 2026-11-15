# Business edition server — log receiver and Forgejo

**English** · [Français](README.fr.md)

To be deployed on a Linux server with Docker and Caddy.

## Installation

```bash
# On the server, in the folder where your other services live
git clone https://github.com/Miinja/ctrl-z.git
cd ctrl-z/server

cp .env.example .env            # domain names, Caddy's Docker network
cp tokens.example tokens.txt    # one token per key: openssl rand -hex 32
chmod 600 .env tokens.txt

mkdir -p data/forgejo data/logs
sudo chown 1000:1000 data/forgejo
sudo chown 10001 data/logs      # user of the log-receiver container

docker compose up -d --build
```

Then add the content of `Caddyfile.snippet` to your Caddyfile and reload Caddy.

## Logs

- Commands arrive in `data/logs/<job>/commands.jsonl`, reports in
  `data/logs/<job>/report.md` (earlier versions are kept).
- Test from any machine on the network:

```bash
curl https://<LOGS_DOMAIN>/healthz
curl -H "Authorization: Bearer <token>" -H 'Content-Type: application/x-ndjson' \
  -d '{"job":"test","command":"echo ok"}' https://<LOGS_DOMAIN>/api/logs
```

- Lost key: delete its line in `tokens.txt` (immediate effect), revoke its Forgejo token,
  and sign its session out in the Claude account settings.

## Forgejo (optional): your own update repository

By default, keys update from the project's GitHub repository. Forgejo is only needed if
the company wants keys to follow its own copy of the repository.

Public sign-up is closed. Create the administrator account from the command line:

```bash
docker compose exec -u git forgejo forgejo admin user create \
  --admin --username admin --email admin@example.lan --random-password
```

Then, in the web interface (`https://<GIT_DOMAIN>`):

1. Create an organisation (e.g. `workshop`) and the private repository `ctrl-z`.
2. Create one account per key (`key01`, …) with **read-only** access to that repository,
   and an access token (`read:repository` scope) for each. That token goes into the
   "Update repository" field of the installer (`RECOVERY_GIT_URL` on the key).
3. From your development machine, push the repository:

```bash
git remote add forgejo https://<GIT_DOMAIN>/workshop/ctrl-z.git
git push forgejo main
```

## Internal certificate

With `tls internal`, Caddy signs certificates with its own authority. For the keys to
accept it, copy Caddy's root certificate
(`/data/caddy/pki/authorities/local/root.crt` inside the Caddy container) into
`build/ca/` (`.crt` extension) before building the image: the build adds it to the key's
trusted authorities.

## Backup

All state lives in `server/data/` (Forgejo repositories, logs): add it to the server's
backup.
