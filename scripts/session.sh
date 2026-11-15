#!/usr/bin/env bash
# Ctrl-Z session launcher (the `ctrlz` command on the key).
#
#   ctrlz                         start a session
#   ctrlz lang fr|en              change the key's language
#   ctrlz events <logs folder>    errors of a Windows installation's event logs
#
# A session:
#   1. reads the installer's settings, asks for the language and the keyboard once
#   2. gets the network up (cable, or Wi-Fi through a menu)
#   3. first boot only: creates the persistence partition
#   4. updates the key (git pull)
#   5. asks what the session is for: recover files, or diagnose a Windows installation
#   6. has the disk and the destination drive picked from a list; the disk is locked
#      read-only in the kernel before anything else touches it
#   7. Windows diagnosis: unlocks BitLocker read-only if the person has the key, and
#      takes a read-only inventory of the installation
#   8. prepares the job folder on the destination and starts Claude Code in it
#   9. on exit, business edition: sends the logs and the report to the server
set -u

# shellcheck source=scripts/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
# shellcheck disable=SC1091
[ -r /etc/ctrl-z/config.env ] && . /etc/ctrl-z/config.env

reload_config() {
  # shellcheck disable=SC1091
  [ -r /etc/ctrl-z/config.env ] && . /etc/ctrl-z/config.env
  CR_LANG="$(cr_lang)"
  export RECOVERY_LANG CR_LANG
  cr_use_locale
}

# --- Language switch ------------------------------------------------------------
if [ "${1:-}" = "lang" ]; then
  if ! cr_set_lang "${2:-}"; then
    echo "Usage: ctrlz lang fr|en"
    exit 1
  fi
  RECOVERY_LANG="$2"
  "$CR_REPO/scripts/update.sh" --install-only
  CR_LANG="$2"
  t "Langue de la clé : français." "Key language: English."
  exit 0
fi

# --- Event log extract (Windows diagnosis) ------------------------------------------
if [ "${1:-}" = "events" ]; then
  shift
  CR_LANG="$(cr_lang)"
  [ $# -gt 0 ] || { t "Usage : ctrlz events <dossier winevt/Logs ou fichier .evtx> [--days N]" \
                      "Usage: ctrlz events <winevt/Logs folder or .evtx file> [--days N]"; exit 1; }
  t "Lecture des journaux (une à trois minutes)…" "Reading the logs (one to three minutes)…" >&2
  # python3-evtx 0.7.4 prints a SyntaxWarning of its own on Python 3.12+: harmless, hidden.
  CR_LANG="$CR_LANG" exec python3 -W ignore::SyntaxWarning "$CR_REPO/scripts/windows-inspect.py" events "$@"
fi

# --- Installer settings: read before any question (they set the language) --------
if [ -z "${RECOVERY_LANG:-}" ] && ! mountpoint -q /etc/ctrl-z; then
  sudo "$CR_REPO/scripts/firstboot.sh" --settings-only
  # shellcheck disable=SC1091
  [ -r /etc/ctrl-z/config.env ] && . /etc/ctrl-z/config.env
fi

# --- Language: asked once, unless the installer set it ---------------------------
if [ -z "${RECOVERY_LANG:-}" ]; then
  CR_LANG="$(cr_lang)"
  ui_menu RECOVERY_LANG "$CR_LANG" "Langue / Language" fr "Français" en "English" || RECOVERY_LANG="$CR_LANG"
  cr_set_lang "$RECOVERY_LANG"
fi
CR_LANG="$(cr_lang)"
export RECOVERY_LANG CR_LANG
cr_use_locale

# --- Keyboard: asked once, then applied at every session --------------------------
if [ -z "${RECOVERY_KEYMAP:-}" ]; then
  default_map=us; [ "$CR_LANG" = "fr" ] && default_map=fr
  ui_menu RECOVERY_KEYMAP "$default_map" "$(t "Disposition du clavier" "Keyboard layout")" \
    fr "Français (AZERTY)" \
    us "English, US (QWERTY)" \
    gb "English, UK" \
    be "Belgique / België" \
    ch-fr "Suisse romande" \
    ca "Canada (multilingue)" \
    de "Deutsch (QWERTZ)" \
    es "Español" \
    it "Italiano" || RECOVERY_KEYMAP="$default_map"
  cr_set_conf RECOVERY_KEYMAP "$RECOVERY_KEYMAP"
fi
cr_apply_keymap "$RECOVERY_KEYMAP"

EDITION="$(cr_edition)"
STATE="${HOME}/.config/ctrl-z"
mkdir -p "$STATE"

# --- Network -----------------------------------------------------------------------
# Claude Code needs the Internet for the whole session. A cable just works; otherwise
# the Wi-Fi is picked in NetworkManager's own menu.
if ! cr_online 12; then
  while :; do
    ui_menu net wifi "$(t "Pas de connexion Internet. Claude Code en a besoin pendant toute la session." \
                          "No Internet connection. Claude Code needs one for the whole session.")" \
      wifi    "$(t "Se connecter à un réseau Wi-Fi" "Connect to a Wi-Fi network")" \
      retry   "$(t "J'ai branché un câble réseau : réessayer" "I plugged in a network cable: try again")" \
      offline "$(t "Continuer sans connexion" "Continue without a connection")" || net=offline
    case "$net" in
      wifi)  sudo nmtui-connect || true ;;
      retry) ;;
      *)     break ;;
    esac
    cr_online 12 && break
  done
fi

# --- First boot: persistence ---------------------------------------------------------
mountpoint -q /etc/ctrl-z || sudo RECOVERY_LANG="$RECOVERY_LANG" "$CR_REPO/scripts/firstboot.sh"
"$CR_REPO/scripts/update.sh"
reload_config

echo
if [ "$EDITION" = "business" ]; then
  t "=== Ctrl-Z — édition entreprise ===" "=== Ctrl-Z — business edition ==="
else
  t "=== Ctrl-Z — édition particulier ===" "=== Ctrl-Z — personal edition ==="
fi

# --- What is this session for? -------------------------------------------------------
ui_menu GOAL recover "$(t "Que voulez-vous faire ?" "What do you want to do?")" \
  recover "$(t "Récupérer des fichiers (disque abîmé, fichiers effacés)" "Recover files (damaged disk, deleted files)")" \
  windows "$(t "Diagnostiquer un Windows qui ne démarre plus ou plante" "Diagnose a Windows that no longer starts or crashes")" || exit 1

# --- Who and what --------------------------------------------------------------------
if [ "$EDITION" = "business" ]; then
  last_tech="$(cat "$STATE/technician" 2>/dev/null || true)"
  ui_input tech "$(t "Technicien :" "Technician:")" "$last_tech" || exit 1
  [ -n "$tech" ] || { t "Nom du technicien obligatoire." "The technician's name is required."; exit 1; }
  echo "$tech" > "$STATE/technician"
  ui_input ref "$(t "Référence du job (ex. dupont-hdd) :" "Job reference (e.g. smith-hdd):")" || exit 1
else
  tech="personal"
  default_ref=recovery; [ "$GOAL" = windows ] && default_ref=windows
  ui_input ref "$(t "Donnez un nom à cette intervention :" "Give this job a name:")" "$default_ref" || exit 1
  ref="${ref:-$default_ref}"
fi
# Letters, digits, dot, dash, underscore: the name is used as a folder and as an identifier.
ref="$(printf '%s' "$ref" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48)"
[ -n "$ref" ] || { t "Référence obligatoire." "A reference is required."; exit 1; }

# --- Disk to recover -------------------------------------------------------------------
# Picked from a list, then locked read-only in the kernel: from here on nothing on this
# system can write to it, whatever command is run.
KEY_DISK="$(cr_boot_disk)"
SOURCE=""
while :; do
  items=()
  while IFS='|' read -r name size model serial tran; do
    [ -n "$name" ] || continue
    items+=("$name" "$(printf '%7s  %s  %s%s' "$size" "${model:-?}" "${tran:+($tran)  }" "${serial:+S/N $serial}")")
  done < <(cr_list_disks "$KEY_DISK")
  items+=(rescan "$(t "Je viens de le brancher : actualiser la liste" "I just plugged it in: refresh the list")")
  items+=(none   "$(t "Aucun pour l'instant (fichier image, disque branché plus tard)" "None for now (image file, disk plugged in later)")")
  if [ "$GOAL" = windows ]; then
    question="$(t "Sur quel disque Windows est-il installé ? Il sera verrouillé en lecture seule : le diagnostic ne modifie rien." \
                  "Which disk is Windows installed on? It will be locked read-only: the diagnosis changes nothing.")"
  else
    question="$(t "Quel est le disque À RÉCUPÉRER ? Il sera verrouillé en lecture seule." \
                  "Which disk is the one TO RECOVER? It will be locked read-only.")"
  fi
  ui_menu SOURCE "${items[0]}" "$question" "${items[@]}" || exit 1
  [ "$SOURCE" = "rescan" ] || break
done
if [ "$SOURCE" = "none" ]; then
  SOURCE=""
else
  if cr_lock_ro "$SOURCE"; then
    t "Disque à récupérer : /dev/$SOURCE, verrouillé en lecture seule." \
      "Disk to recover: /dev/$SOURCE, locked read-only."
  else
    ui_msg "$(t "Le verrouillage en lecture seule de /dev/$SOURCE a échoué. Arrêt, par sécurité." \
               "Could not lock /dev/$SOURCE read-only. Stopping, to be safe.")"
    exit 1
  fi
fi

# --- BitLocker (Windows diagnosis) ---------------------------------------------------------
# An encrypted Windows partition can only be read with its key. The key is typed here,
# in the launcher, and handed to the opening script on its standard input: it never
# goes through Claude, the command line or the logs. The volume is opened read-only.
if [ "$GOAL" = windows ] && [ -n "$SOURCE" ]; then
  for part in $(lsblk -lnpo NAME "/dev/$SOURCE" | sed 1d); do
    [ "$(sudo blkid -p -o value -s TYPE "$part" 2>/dev/null)" = BitLocker ] || continue
    p="${part#/dev/}"
    [ -b "/dev/mapper/ctrlz-bl-$p" ] && continue
    while :; do
      ui_yesno "$(t "La partition $p ($(lsblk -dno SIZE "$part" | tr -d ' ')) est chiffrée par BitLocker.

Pour l'examiner, il faut sa clé de récupération (48 chiffres) : compte Microsoft (aka.ms/myrecoverykey), impression, clé USB ou administrateur informatique.

Saisir la clé maintenant ? Elle sert uniquement à ouvrir la partition en lecture seule ; elle n'est ni enregistrée ni transmise à Claude." \
"Partition $p ($(lsblk -dno SIZE "$part" | tr -d ' ')) is encrypted with BitLocker.

Reading it needs its recovery key (48 digits): Microsoft account (aka.ms/myrecoverykey), printout, USB stick or IT administrator.

Enter the key now? It is only used to open the partition read-only; it is neither stored nor given to Claude.")" || break
      ui_password bl_key "$(t "Clé de récupération de $p :" "Recovery key of $p:")" || break
      if printf '%s\n' "$bl_key" | sudo "$CR_REPO/scripts/bitlocker-open.sh" "$p"; then
        bl_key=""
        t "$p : ouverte en lecture seule." "$p: opened read-only."
        break
      fi
      bl_key=""
      ui_msg "$(t "Cette clé n'ouvre pas $p. Vérifiez-la (l'identifiant de clé affiché par Windows doit correspondre)." \
                 "This key does not open $p. Check it (the key ID shown by Windows must match).")"
    done
  done
fi

# --- Destination -------------------------------------------------------------------------
jobs_dir="${RECOVERY_JOBS_DIR:-/mnt/jobs}"
DEST=""
if mountpoint -q "$jobs_dir"; then
  DEST="$(findmnt -no SOURCE "$jobs_dir")"
  if [ -n "$SOURCE" ] && [ "$(lsblk -no PKNAME "$DEST" 2>/dev/null | head -n 1)" = "$SOURCE" ]; then
    ui_msg "$(t "$jobs_dir est monté depuis le disque à récupérer. Démontez-le et relancez." \
               "$jobs_dir is mounted from the disk to recover. Unmount it and start again.")"
    exit 1
  fi
else
  while :; do
    items=()
    while IFS='|' read -r name size fstype label model; do
      [ -n "$name" ] || continue
      items+=("$name" "$(printf '%7s  %-6s %s%s' "$size" "$fstype" "${label:+[$label]  }" "$model")")
    done < <(cr_list_destinations "$KEY_DISK" "$SOURCE")
    items+=(rescan "$(t "Je viens de le brancher : actualiser la liste" "I just plugged it in: refresh the list")")
    items+=(folder "$(t "Autre : indiquer un dossier déjà monté" "Other: give a folder that is already mounted")")
    if [ "$GOAL" = windows ]; then
      # A diagnosis only produces reports: the key's persistence is enough.
      items=(key "$(t "Sur la clé elle-même (diagnostic seul, pas de copie du disque)" "On the key itself (diagnosis only, no copy of the disk)")" "${items[@]}")
      question="$(t "Où ranger le diagnostic ? Sur la clé suffit ; un disque de DESTINATION sera nécessaire pour sauvegarder le disque avant toute réparation." \
                    "Where should the diagnosis be kept? The key is enough; a DESTINATION drive will be needed to back up the disk before any repair.")"
    else
      question="$(t "Où ranger ce qui sera récupéré ? Choisissez la partition du disque de DESTINATION. Elle ne sera pas effacée : un dossier y est ajouté." \
                    "Where should the recovered data go? Pick the partition of the DESTINATION drive. It is not erased: a folder is added to it.")"
    fi
    ui_menu dest "${items[0]}" "$question" "${items[@]}" || exit 1
    case "$dest" in
      rescan) continue ;;
      folder)
        ui_input jobs_dir "$(t "Dossier de destination :" "Destination folder:")" "$jobs_dir" || exit 1
        break ;;
      key)
        jobs_dir="$HOME/ctrl-z-jobs"
        mkdir -p "$jobs_dir"
        ON_KEY=1
        break ;;
    esac
    ui_yesno "$(t "/dev/$dest va être ouverte en écriture. Est-ce bien le disque de DESTINATION, et pas celui que vous voulez récupérer ?" \
                 "/dev/$dest is about to be opened for writing. Is it really the DESTINATION drive, and not the one you want to recover?")" no || continue
    sudo mkdir -p "$jobs_dir"
    if ! sudo mount -o "uid=$(id -u),gid=$(id -g)" "/dev/$dest" "$jobs_dir" 2>/dev/null && ! sudo mount "/dev/$dest" "$jobs_dir"; then
      ui_msg "$(t "Montage de /dev/$dest impossible." "Could not mount /dev/$dest.")"
      continue
    fi
    # The first step of a recovery is a full clone of the disk: it has to fit.
    if [ -n "$SOURCE" ] && [ "$GOAL" = recover ]; then
      need="$(lsblk -bdno SIZE "/dev/$SOURCE")"
      free="$(df -B1 --output=avail "$jobs_dir" | tail -n 1 | tr -d ' ')"
      if [ "${free:-0}" -lt "${need:-0}" ]; then
        if ! ui_yesno "$(t "Espace libre sur la destination : $(numfmt --to=iec "$free"). Le disque à récupérer fait $(numfmt --to=iec "$need") : son clone complet ne tiendra pas. Continuer quand même ?" \
                          "Free space on the destination: $(numfmt --to=iec "$free"). The disk to recover is $(numfmt --to=iec "$need"): its full clone will not fit. Continue anyway?")" no; then
          sudo umount "$jobs_dir"
          continue
        fi
      fi
    fi
    DEST="/dev/$dest"
    jobs_dir="$jobs_dir/ctrl-z"
    sudo mkdir -p "$jobs_dir" && sudo chown "$(id -u):$(id -g)" "$jobs_dir" 2>/dev/null
    break
  done
fi

if [ ! -d "$jobs_dir" ]; then
  t "Le dossier $jobs_dir n'existe pas. Montez le support de destination, puis relancez." \
    "The folder $jobs_dir does not exist. Mount the destination drive, then start again."
  exit 1
fi
if [ -n "${ON_KEY:-}" ]; then
  mountpoint -q /etc/ctrl-z || ui_msg "$(t "Pas de persistance active : le diagnostic restera en mémoire et sera perdu à l'arrêt du PC." \
                                         "No active persistence: the diagnosis stays in memory and is lost when the PC shuts down.")"
elif [ "$(stat -f -c %T "$jobs_dir")" = "overlayfs" ]; then
  ui_yesno "$(t "ATTENTION : $jobs_dir est sur la clé (mémoire vive), pas sur un disque de destination. Continuer quand même ?" \
               "WARNING: $jobs_dir is on the key (in memory), not on a destination drive. Continue anyway?")" no || exit 1
fi

# Resume an existing job with this reference, otherwise create one dated today.
job_dir="$(find "$jobs_dir" -maxdepth 1 -type d -name "*_$ref" 2>/dev/null | sort | tail -n 1)"
if [ -n "$job_dir" ]; then
  t "Reprise : $job_dir" "Resuming: $job_dir"
else
  job_dir="$jobs_dir/$(date +%F)_$ref"
  if [ "$GOAL" = windows ]; then subdirs=(windows); else subdirs=(image work recovered); fi
  mkdir -p "${subdirs[@]/#/$job_dir/}" \
    || { t "Création impossible dans $jobs_dir." "Could not create a folder in $jobs_dir."; exit 1; }
  t "Nouveau dossier : $job_dir" "New folder: $job_dir"
fi

# --- Windows inventory ------------------------------------------------------------------------
# Read-only: the disk is locked. Partitions are mounted read-only under /mnt/windows.
WIN_SUMMARY=""
if [ "$GOAL" = windows ] && [ -n "$SOURCE" ]; then
  t "Inventaire de Windows sur /dev/$SOURCE (lecture seule)…" "Inventory of Windows on /dev/$SOURCE (read-only)…"
  if WIN_SUMMARY="$(sudo RECOVERY_LANG="$RECOVERY_LANG" "$CR_REPO/scripts/windows-detect.sh" "$SOURCE" "$job_dir/windows")"; then
    printf '%s\n' "$WIN_SUMMARY" | sed 's/^/  /'
  else
    WIN_SUMMARY="- $(t "L'inventaire a échoué : à refaire avec Claude." "The inventory failed: to be redone with Claude.")"
  fi
fi

# --- Facts of this session, for Claude ----------------------------------------------------
# Claude Code reads CLAUDE.md in its working folder: the choices made above reach it as
# established facts instead of something it has to work out.
{
  t "# Faits de cette session (écrits par le lanceur, ne pas modifier)" \
    "# Facts of this session (written by the launcher, do not edit)"
  echo
  if [ -n "$SOURCE" ]; then
    t "- **Disque à récupérer** : \`/dev/$SOURCE\` — $(cr_describe_disk "$SOURCE"). Désigné par l'utilisateur et verrouillé en lecture seule dans le noyau (\`blockdev --setro\`). Ne jamais tenter de lever ce verrou." \
      "- **Disk to recover**: \`/dev/$SOURCE\` — $(cr_describe_disk "$SOURCE"). Designated by the user and locked read-only in the kernel (\`blockdev --setro\`). Never try to lift this lock."
  else
    t "- **Disque à récupérer** : aucun n'a été désigné. Avant de lire un disque, demande lequel et verrouille-le : \`sudo blockdev --setro /dev/sdX\`." \
      "- **Disk to recover**: none was designated. Before reading a disk, ask which one it is and lock it: \`sudo blockdev --setro /dev/sdX\`."
  fi
  t "- **Destination** : ${DEST:-$jobs_dir}, dossier de travail \`$job_dir\` ($(df -h --output=avail "$job_dir" | tail -n 1 | tr -d ' ') libres)." \
    "- **Destination**: ${DEST:-$jobs_dir}, working folder \`$job_dir\` ($(df -h --output=avail "$job_dir" | tail -n 1 | tr -d ' ') free)."
  [ -n "$KEY_DISK" ] && t "- **Clé de démarrage** : \`/dev/$KEY_DISK\`. Ni source ni destination." \
                          "- **Boot key**: \`/dev/$KEY_DISK\`. Neither a source nor a destination."
  if [ "$GOAL" = windows ]; then
    echo
    t "## Objectif : diagnostic Windows (lecture seule)" "## Goal: Windows diagnosis (read-only)"
    echo
    t "La personne a choisi « Diagnostiquer un Windows ». Suis la section « Diagnostic Windows » de ta procédure. Cette version de la clé ne répare pas : tu diagnostiques et tu proposes, rien n'est écrit sur ce disque." \
      "The person chose \"Diagnose a Windows\". Follow the \"Windows diagnosis\" section of your procedure. This version of the key does not repair: you diagnose and recommend, nothing is written to this disk."
    if [ -n "$WIN_SUMMARY" ]; then
      echo
      t "Inventaire fait par le lanceur (détail : \`windows/inventory.md\`) :" \
        "Inventory taken by the launcher (details: \`windows/inventory.md\`):"
      echo
      printf '%s\n' "$WIN_SUMMARY"
    fi
  fi
} > "$job_dir/CLAUDE.md"

# The dialogs are over: start Claude Code on a clean screen.
cr_ui_fancy && clear

export RECOVERY_EDITION="$EDITION"
export RECOVERY_COMPANY="${RECOVERY_COMPANY:-}"
export RECOVERY_TECH="$tech"
export RECOVERY_JOB="${job_dir##*/}"
export RECOVERY_JOB_DIR="$job_dir"
export RECOVERY_SOURCE_DISK="${SOURCE:+/dev/$SOURCE}"
export RECOVERY_GOAL="$GOAL"

echo
df -h "$job_dir" | sed 's/^/  /'
echo

cd "$job_dir" || exit 1
[ -n "${CR_NO_CLAUDE:-}" ] && exit 0          # tests stop here
claude "$@"
status=$?

# --- Closing ---------------------------------------------------------------------------------
[ "$EDITION" = "business" ] || exit "$status"

/opt/ctrl-z/hooks/log-command.sh --flush

if [ -n "${RECOVERY_LOG_URL:-}" ] && [ -s "$job_dir/report.md" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X PUT \
    -H "Authorization: Bearer ${RECOVERY_LOG_TOKEN:-}" \
    -H 'Content-Type: text/markdown; charset=utf-8' \
    --data-binary @"$job_dir/report.md" \
    "${RECOVERY_LOG_URL%/}/api/jobs/$RECOVERY_JOB/report" 2>/dev/null)" || code=000
  case "$code" in
    2*) t "Rapport envoyé au serveur." "Report sent to the server." ;;
    *)  t "Rapport NON envoyé (HTTP $code) : il reste dans $job_dir/report.md." \
          "Report NOT sent (HTTP $code): it remains in $job_dir/report.md." ;;
  esac
fi

log_dir="${RECOVERY_LOG_DIR:-/var/log/ctrl-z}"
if [ -s "$log_dir/queue.jsonl" ] || [ -s "$log_dir/queue.sending" ]; then
  t "Des journaux attendent encore sur la clé : ils partiront à la prochaine session connectée." \
    "Some logs are still waiting on the key: they will be sent at the next connected session."
fi
exit "$status"
