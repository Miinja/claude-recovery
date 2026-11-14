#!/usr/bin/env bash
# Fonctions communes aux scripts de la clé. À inclure avec `.`, pas à exécuter.

ORDI_REPO="${ORDI_REPO:-/opt/ordi/claude-recovery}"
ORDI_DEFAULT_GIT_URL="https://github.com/Miinja/claude-recovery.git"

# Édition de la clé : fixée dans l'image à la construction.
ordi_edition() {
  local e
  e="$(cat /usr/share/ordi/edition 2>/dev/null || true)"
  case "$e" in
    entreprise|particulier) echo "$e" ;;
    *) echo "entreprise" ;;
  esac
}

# --- Bloc de réglages ---------------------------------------------------------
# L'installeur ne sait pas créer de partition Linux depuis Windows. Il dépose donc
# les réglages saisis (le futur /etc/ordi/ordi.env) dans un petit bloc brut, juste
# après l'image, à une frontière de 1 Mio. Au premier démarrage, la clé le lit,
# crée sa partition de persistance, y range les réglages et efface le bloc.
#
#   ORDICFG1\n<taille en octets>\n<sha256 du contenu>\n<contenu>
ORDI_BLOB_MAGIC="ORDICFG1"
ORDI_BLOB_AREA=$((1024 * 1024))     # zone réservée au bloc
ORDI_BLOB_MAX=$((60 * 1024))        # taille maximale du contenu

# ordi_blob_offset <taille de l'image en octets> : frontière de 1 Mio suivante
ordi_blob_offset() {
  echo $(( ( ($1 + ORDI_BLOB_AREA - 1) / ORDI_BLOB_AREA ) * ORDI_BLOB_AREA ))
}

# ordi_blob_write <périphérique ou fichier> <décalage en octets> <fichier de réglages>
ordi_blob_write() {
  local target="$1" offset="$2" file="$3" size sum tmp
  size="$(stat -c %s "$file")"
  [ "$size" -le "$ORDI_BLOB_MAX" ] || { echo "Réglages trop volumineux." >&2; return 1; }
  sum="$(sha256sum "$file" | cut -d' ' -f1)"
  tmp="$(mktemp)"
  { printf '%s\n%s\n%s\n' "$ORDI_BLOB_MAGIC" "$size" "$sum"; cat "$file"; } > "$tmp"
  truncate -s "$ORDI_BLOB_AREA" "$tmp"
  dd if="$tmp" of="$target" bs=1M seek=$((offset / ORDI_BLOB_AREA)) conv=notrunc,fsync status=none
  rm -f "$tmp"
}

# ordi_blob_find <périphérique ou fichier> <octet de départ> : cherche le bloc sur les
# 64 Mio suivants ; affiche son décalage et renvoie 0 s'il est trouvé.
ordi_blob_find() {
  local target="$1" n first
  first=$(( $2 / ORDI_BLOB_AREA ))
  for n in $(seq "$first" $((first + 64))); do
    if [ "$(dd if="$target" bs=1M skip="$n" count=1 status=none 2>/dev/null | head -c 8 | tr -d '\0')" = "$ORDI_BLOB_MAGIC" ]; then
      echo $((n * ORDI_BLOB_AREA))
      return 0
    fi
  done
  return 1
}

# ordi_blob_read <périphérique ou fichier> <décalage> : affiche le contenu s'il est intact
ordi_blob_read() {
  local target="$1" offset="$2" tmp size sum header
  tmp="$(mktemp)"
  dd if="$target" of="$tmp" bs=1M skip=$((offset / ORDI_BLOB_AREA)) count=1 status=none
  size="$(sed -n 2p "$tmp" | tr -cd '0-9')"
  sum="$(sed -n 3p "$tmp" | tr -cd 'a-f0-9')"
  if [ -z "$size" ] || [ "$size" -gt "$ORDI_BLOB_MAX" ]; then rm -f "$tmp"; return 1; fi
  header=$(( ${#ORDI_BLOB_MAGIC} + 1 + ${#size} + 1 + 64 + 1 ))
  if [ "$(tail -c +$((header + 1)) "$tmp" | head -c "$size" | sha256sum | cut -d' ' -f1)" != "$sum" ]; then
    rm -f "$tmp"; return 1
  fi
  tail -c +$((header + 1)) "$tmp" | head -c "$size"
  rm -f "$tmp"
}

# ordi_blob_erase <périphérique ou fichier> <décalage>
ordi_blob_erase() {
  dd if=/dev/zero of="$1" bs=1M seek=$(( $2 / ORDI_BLOB_AREA )) count=1 conv=notrunc,fsync status=none
}

# ordi_env_line NOM valeur : ligne `NOM='valeur'` sûre à inclure par un shell
ordi_env_line() {
  printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
}
