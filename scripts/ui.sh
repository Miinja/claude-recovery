#!/usr/bin/env bash
# Dialogs used by the key's launcher. Source it with `.`, do not run it.
#
# On a real terminal the questions are drawn with whiptail (arrow keys, Enter), so
# nothing has to be typed until the keyboard layout is known. Without a terminal, or
# with CR_PLAIN=1, the same functions fall back to plain numbered prompts: that is what
# the automated tests drive.
#
# Texts are passed already translated: use "$(t "français" "English")".

CR_UI_TITLE="${CR_UI_TITLE:-Ctrl-Z}"

cr_ui_fancy() {
  [ -z "${CR_PLAIN:-}" ] && [ -t 0 ] && [ -t 1 ] && command -v whiptail >/dev/null 2>&1
}

# ui_msg "text"
ui_msg() {
  if cr_ui_fancy; then
    whiptail --title "$CR_UI_TITLE" --msgbox "$1" 0 0
  else
    printf '\n%s\n' "$1"
  fi
}

# ui_yesno "question" [no]   -> status 0 for yes. "no" makes No the default answer.
ui_yesno() {
  local answer
  if cr_ui_fancy; then
    if [ "${2:-}" = "no" ]; then
      whiptail --title "$CR_UI_TITLE" --defaultno --yes-button "$(t "Oui" "Yes")" --no-button "$(t "Non" "No")" --yesno "$1" 0 0
    else
      whiptail --title "$CR_UI_TITLE" --yes-button "$(t "Oui" "Yes")" --no-button "$(t "Non" "No")" --yesno "$1" 0 0
    fi
    return
  fi
  if [ "${2:-}" = "no" ]; then
    read -r -p "$1 $(t "[o/N]" "[y/N]") " answer
    is_yes "$answer"
  else
    read -r -p "$1 $(t "[O/n]" "[Y/n]") " answer
    ! is_no "$answer"
  fi
}

# ui_input VARIABLE "question" [default]   -> status 1 if cancelled
ui_input() {
  local __var="$1" __value
  if cr_ui_fancy; then
    __value="$(whiptail --title "$CR_UI_TITLE" --inputbox "$2" 0 70 "${3:-}" 3>&1 1>&2 2>&3)" || return 1
  else
    read -r -p "$2${3:+ [$3]} " __value
    __value="${__value:-${3:-}}"
  fi
  printf -v "$__var" '%s' "$__value"
}

# ui_password VARIABLE "question"   -> status 1 if cancelled. Nothing is shown while typing.
ui_password() {
  local __var="$1" __value
  if cr_ui_fancy; then
    __value="$(whiptail --title "$CR_UI_TITLE" --passwordbox "$2" 0 70 3>&1 1>&2 2>&3)" || return 1
  else
    read -r -s -p "$2 " __value || return 1
    echo
  fi
  printf -v "$__var" '%s' "$__value"
}

# ui_menu VARIABLE DEFAULT_TAG "text" tag "label" [tag "label"...]   -> status 1 if cancelled
ui_menu() {
  local __var="$1" __default="$2" __text="$3" __value __count __height __i __answer
  shift 3
  __count=$(( $# / 2 ))
  if cr_ui_fancy; then
    __height=$__count; [ "$__height" -gt 12 ] && __height=12
    __value="$(whiptail --title "$CR_UI_TITLE" --default-item "$__default" \
      --ok-button "$(t "Choisir" "Select")" --cancel-button "$(t "Annuler" "Cancel")" \
      --menu "$__text" $(( __height + 10 )) 78 "$__height" "$@" 3>&1 1>&2 2>&3)" || return 1
  else
    printf '\n%s\n' "$__text"
    __i=1
    while [ "$__i" -le "$__count" ]; do
      printf '  %d) %-8s %s\n' "$__i" "${@:$(( __i * 2 - 1 )):1}" "${@:$(( __i * 2 )):1}"
      __i=$(( __i + 1 ))
    done
    read -r -p "$(t "Votre choix" "Your choice")${__default:+ [$__default]}: " __answer
    __answer="${__answer:-$__default}"
    __value=""
    case "$__answer" in
      ''|*[!0-9]*) ;;
      *) [ "$__answer" -ge 1 ] && [ "$__answer" -le "$__count" ] && __value="${@:$(( __answer * 2 - 1 )):1}" ;;
    esac
    if [ -z "$__value" ]; then
      __i=1
      while [ "$__i" -le "$__count" ]; do
        [ "${@:$(( __i * 2 - 1 )):1}" = "$__answer" ] && __value="$__answer"
        __i=$(( __i + 1 ))
      done
    fi
    [ -n "$__value" ] || return 1
  fi
  printf -v "$__var" '%s' "$__value"
}
