#!/usr/bin/env bash
# Fonctions communes aux scripts de la clé. À inclure avec `.`, pas à exécuter.

CR_REPO="${CR_REPO:-/opt/claude-recovery/repo}"
CR_DEFAULT_GIT_URL="https://github.com/Miinja/claude-recovery.git"

# Édition de la clé : fixée dans l'image à la construction.
cr_edition() {
  local e
  e="$(cat /usr/share/claude-recovery/edition 2>/dev/null || true)"
  case "$e" in
    entreprise|particulier) echo "$e" ;;
    *) echo "entreprise" ;;
  esac
}

# --- Bloc de réglages ---------------------------------------------------------
# L'installeur ne sait pas créer de partition Linux depuis Windows. Il dépose donc
# les réglages saisis (le futur /etc/claude-recovery/config.env) dans un petit bloc brut, juste
# après l'image, à une frontière de 1 Mio. Au premier démarrage, la clé le lit,
# crée sa partition de persistance, y range les réglages et efface le bloc.
#
#   CRCFGv01\n<taille en octets>\n<sha256 du contenu>\n<contenu>
CR_BLOB_MAGIC="CRCFGv01"
CR_BLOB_AREA=$((1024 * 1024))     # zone réservée au bloc
CR_BLOB_MAX=$((60 * 1024))        # taille maximale du contenu

# cr_blob_offset <taille de l'image en octets> : frontière de 1 Mio suivante
cr_blob_offset() {
  echo $(( ( ($1 + CR_BLOB_AREA - 1) / CR_BLOB_AREA ) * CR_BLOB_AREA ))
}

# cr_blob_write <périphérique ou fichier> <décalage en octets> <fichier de réglages>
cr_blob_write() {
  local target="$1" offset="$2" file="$3" size sum tmp
  size="$(stat -c %s "$file")"
  [ "$size" -le "$CR_BLOB_MAX" ] || { echo "Réglages trop volumineux." >&2; return 1; }
  sum="$(sha256sum "$file" | cut -d' ' -f1)"
  tmp="$(mktemp)"
  { printf '%s\n%s\n%s\n' "$CR_BLOB_MAGIC" "$size" "$sum"; cat "$file"; } > "$tmp"
  truncate -s "$CR_BLOB_AREA" "$tmp"
  dd if="$tmp" of="$target" bs=1M seek=$((offset / CR_BLOB_AREA)) conv=notrunc,fsync status=none
  rm -f "$tmp"
}

# cr_blob_find <périphérique ou fichier> <octet de départ> : cherche le bloc sur les
# 64 Mio suivants ; affiche son décalage et renvoie 0 s'il est trouvé.
cr_blob_find() {
  local target="$1" n first
  first=$(( $2 / CR_BLOB_AREA ))
  for n in $(seq "$first" $((first + 64))); do
    if [ "$(dd if="$target" bs=1M skip="$n" count=1 status=none 2>/dev/null | head -c 8 | tr -d '\0')" = "$CR_BLOB_MAGIC" ]; then
      echo $((n * CR_BLOB_AREA))
      return 0
    fi
  done
  return 1
}

# cr_blob_read <périphérique ou fichier> <décalage> : affiche le contenu s'il est intact
cr_blob_read() {
  local target="$1" offset="$2" tmp size sum header
  tmp="$(mktemp)"
  dd if="$target" of="$tmp" bs=1M skip=$((offset / CR_BLOB_AREA)) count=1 status=none
  size="$(sed -n 2p "$tmp" | tr -cd '0-9')"
  sum="$(sed -n 3p "$tmp" | tr -cd 'a-f0-9')"
  if [ -z "$size" ] || [ "$size" -gt "$CR_BLOB_MAX" ]; then rm -f "$tmp"; return 1; fi
  header=$(( ${#CR_BLOB_MAGIC} + 1 + ${#size} + 1 + 64 + 1 ))
  if [ "$(tail -c +$((header + 1)) "$tmp" | head -c "$size" | sha256sum | cut -d' ' -f1)" != "$sum" ]; then
    rm -f "$tmp"; return 1
  fi
  tail -c +$((header + 1)) "$tmp" | head -c "$size"
  rm -f "$tmp"
}

# cr_blob_erase <périphérique ou fichier> <décalage>
cr_blob_erase() {
  dd if=/dev/zero of="$1" bs=1M seek=$(( $2 / CR_BLOB_AREA )) count=1 conv=notrunc,fsync status=none
}

# cr_env_line NOM valeur : ligne `NOM='valeur'` sûre à inclure par un shell
cr_env_line() {
  printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
}

# --- Langue -------------------------------------------------------------------
# RECOVERY_LANG (fr ou en) vient de /etc/claude-recovery/config.env : écrit par
# l'installeur, changeable avec `claude-recovery lang fr|en`. À défaut, on suit la
# langue du système.
cr_lang() {
  case "${RECOVERY_LANG:-}" in
    fr|en) echo "$RECOVERY_LANG" ;;
    *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in fr*) echo fr ;; *) echo en ;; esac ;;
  esac
}

# t "texte français" "English text" : affiche le texte dans la langue courante (CR_LANG)
t() {
  if [ "${CR_LANG:-en}" = "fr" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}

# ask VARIABLE "question française" "English question" : pose la question, range la réponse
ask() {
  local __p
  __p="$(t "$2" "$3")"
  read -r -p "$__p " "$1"
}

# is_yes / is_no : accepte oui/yes et non/no dans les deux langues
is_yes() { case "$1" in o|O|oui|Oui|OUI|y|Y|yes|Yes|YES) return 0 ;; esac; return 1; }
is_no()  { case "$1" in n|N|non|Non|NON|no|No|NO) return 0 ;; esac; return 1; }

# cr_set_lang fr|en : enregistre la langue dans config.env (sudo si nécessaire)
cr_set_lang() {
  local f=/etc/claude-recovery/config.env sudo=""
  case "$1" in fr|en) ;; *) return 1 ;; esac
  [ "$(id -u)" -eq 0 ] || sudo="sudo"
  $sudo mkdir -p /etc/claude-recovery
  $sudo touch "$f"
  $sudo sed -i '/^RECOVERY_LANG=/d' "$f"
  echo "RECOVERY_LANG='$1'" | $sudo tee -a "$f" >/dev/null
  # Le lanceur tourne sans privilèges : il doit pouvoir relire ce fichier.
  $sudo chown 1000:1000 "$f"; $sudo chmod 600 "$f"
}
