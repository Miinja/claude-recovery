#!/usr/bin/env bash
# Construction de l'image live Claude Recovery (base Debian live-build).
# À compléter : ce script pose la structure, il n'est pas encore testé.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$HERE/work"

mkdir -p "$WORK" && cd "$WORK"

lb config \
  --distribution bookworm \
  --archive-areas "main contrib non-free non-free-firmware" \
  --bootappend-live "boot=live components persistence username=ordi"

# Paquets
grep -vE '^\s*(#|$)' "$HERE/packages.txt" > config/package-lists/recovery.list.chroot

# Config Claude + hooks copiés dans l'image
mkdir -p config/includes.chroot/opt/ordi/hooks config/includes.chroot/etc/skel/.claude
cp "$ROOT/config/CLAUDE.md"     config/includes.chroot/etc/skel/.claude/CLAUDE.md
cp "$ROOT/config/settings.json" config/includes.chroot/etc/skel/.claude/settings.json
cp "$ROOT/hooks/"*.sh           config/includes.chroot/opt/ordi/hooks/

# TODO : installer Claude Code dans le chroot (hook live-build)
# TODO : service ordi-update (git pull de la config au boot)

lb build
mkdir -p "$HERE/out" && mv ./*.iso "$HERE/out/"
echo "Image prête dans build/out/"
