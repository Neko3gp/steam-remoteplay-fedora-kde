#!/usr/bin/env bash
# uninstall.sh — revierte lo que instaló install.sh en tu usuario (no desinstala paquetes ni toca drivers).
set -euo pipefail

DRY=0; CLOSE_PORTS=0; REMOVE_AUTOLOGIN=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    --close-ports) CLOSE_PORTS=1 ;;
    --remove-autologin) REMOVE_AUTOLOGIN=1 ;;
    -h|--help)
      echo "Uso: ./uninstall.sh [--dry-run] [--close-ports] [--remove-autologin]"; exit 0 ;;
    *) echo "Opción desconocida: $a" >&2; exit 2 ;;
  esac
done

run() { if [ "$DRY" = 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }

run rm -f "$HOME/.local/bin/remoteplay-launch" "$HOME/.local/bin/remoteplay-doctor"
run rm -rf "$HOME/.local/lib/fedora-mac-remoteplay"
run rm -f "$HOME/.config/autostart/fedora-mac-remoteplay.desktop"

if [ -f "$HOME/.config/autostart/steam.desktop.bak" ]; then
  run mv "$HOME/.config/autostart/steam.desktop.bak" "$HOME/.config/autostart/steam.desktop"
  echo "Restauré el autostart original de Steam."
fi

if [ "$CLOSE_PORTS" = 1 ]; then
  run sudo firewall-cmd --permanent --remove-port=27031-27036/udp
  run sudo firewall-cmd --permanent --remove-port=27036-27037/tcp
  run sudo firewall-cmd --reload
fi

if [ "$REMOVE_AUTOLOGIN" = 1 ]; then
  run sudo rm -f /etc/sddm.conf.d/zz-remoteplay-autologin.conf
fi

echo "Listo. No se revirtieron: bloqueo de pantalla desactivado, sshd, drivers freeworld."
