#!/usr/bin/env bash
# install.sh — prepara un PC con Fedora KDE Plasma (Wayland) como host de Steam Remote Play.
# Ejecútalo como TU usuario (no como root); pedirá sudo solo cuando haga falta.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)

DRY=0; YES=0
OPT_SSH=1; OPT_FIREWALL=1; OPT_LOCK=1; OPT_AUTOSTART=1
OPT_CODECS=ask      # ask | yes | no
OPT_AUTOLOGIN=0

usage() {
  cat <<'EOF'
Uso: ./install.sh [opciones]

  --dry-run        Muestra lo que haría sin cambiar nada
  -y, --yes        No preguntar; aceptar los valores por defecto
  --codecs         Instalar drivers de video 'freeworld' (codificación por hardware) sin preguntar
  --no-codecs      No tocar los drivers de video
  --autologin      Activar inicio de sesión automático en SDDM (el PC arranca ya en el escritorio)
  --no-ssh         No instalar/activar sshd
  --no-firewall    No abrir puertos en firewalld
  --no-lock        No desactivar el bloqueo automático de pantalla
  --no-autostart   No arrancar Steam con -pipewire al iniciar sesión
  -h, --help       Esta ayuda
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    -y|--yes) YES=1 ;;
    --codecs) OPT_CODECS=yes ;;
    --no-codecs) OPT_CODECS=no ;;
    --autologin) OPT_AUTOLOGIN=1 ;;
    --no-ssh) OPT_SSH=0 ;;
    --no-firewall) OPT_FIREWALL=0 ;;
    --no-lock) OPT_LOCK=0 ;;
    --no-autostart) OPT_AUTOSTART=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    AVISO: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY" = 1 ]; then printf '    [dry-run] %s\n' "$*"; else "$@"; fi
}

# ask "pregunta" y|n  -> devuelve 0 si la respuesta es sí
ask() {
  local q=$1 def=${2:-y} ans
  if [ "$YES" = 1 ] || [ "$DRY" = 1 ] || [ ! -t 0 ]; then [ "$def" = y ]; return; fi
  read -r -p "    $q [$([ "$def" = y ] && echo 'S/n' || echo 's/N')] " ans || true
  ans=${ans:-$def}
  case $ans in [SsYy]*) return 0 ;; *) return 1 ;; esac
}

# --- 0. Comprobaciones -------------------------------------------------------
say "Comprobando el sistema"
if [ "$(id -u)" = 0 ]; then die "No lo ejecutes como root; usa tu usuario normal (se pedirá sudo)."; fi

if [ "${RP_SKIP_CHECKS:-0}" != 1 ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = fedora ] || die "Este instalador es para Fedora (detectado: ${PRETTY_NAME:-?})."
  case ${XDG_CURRENT_DESKTOP:-KDE} in *KDE*) ;; *) warn "Escritorio '${XDG_CURRENT_DESKTOP}': se esperaba KDE Plasma." ;; esac
  command -v sudo >/dev/null 2>&1 || die "Necesito sudo."
fi
info "Usuario: $(id -un) | Sesión: ${XDG_SESSION_TYPE:-desconocida}"
if [ "${XDG_SESSION_TYPE:-wayland}" != wayland ]; then
  warn "Tu sesión actual no es Wayland. Funciona, pero la opción -pipewire solo hace falta en Wayland."
fi

# shellcheck source=lib/env.sh
. "$REPO_DIR/lib/env.sh"
if ! rp_steam_cmd; then
  warn "No encuentro Steam. Instálalo (RPM Fusion nonfree: 'sudo dnf install steam', o Flatpak) y vuelve a ejecutar."
fi

# --- 1. Paquetes -------------------------------------------------------------
say "Instalando paquetes necesarios"
PKGS=(libva-utils xdg-desktop-portal-kde pipewire wireplumber)
if [ "$OPT_SSH" = 1 ]; then PKGS+=(openssh-server); fi
run sudo dnf install -y "${PKGS[@]}"

# --- 2. SSH ------------------------------------------------------------------
if [ "$OPT_SSH" = 1 ]; then
  say "Activando SSH (para controlar el PC desde el Mac)"
  run sudo systemctl enable --now sshd
fi

# --- 3. Firewall -------------------------------------------------------------
if [ "$OPT_FIREWALL" = 1 ]; then
  say "Abriendo puertos de Steam Remote Play en firewalld"
  if [ "$DRY" = 1 ] || systemctl is-active --quiet firewalld 2>/dev/null; then
    run sudo firewall-cmd --permanent --add-port=27031-27036/udp
    run sudo firewall-cmd --permanent --add-port=27036-27037/tcp
    if [ "$OPT_SSH" = 1 ]; then run sudo firewall-cmd --permanent --add-service=ssh; fi
    run sudo firewall-cmd --reload
  else
    info "firewalld no está activo; nada que abrir."
  fi
fi

# --- 4. Codecs / codificación por hardware ----------------------------------
do_codecs=0
case $OPT_CODECS in
  yes) do_codecs=1 ;;
  no)  do_codecs=0 ;;
  ask)
    if command -v vainfo >/dev/null 2>&1 && vainfo 2>/dev/null | grep -qE 'VAProfileH264.*EncSlice'; then
      info "La codificación H.264 por hardware ya funciona; omito los drivers."
    elif ask "¿Instalar drivers 'freeworld' de RPM Fusion para codificar video por hardware?" y; then
      do_codecs=1
    fi ;;
esac
if [ "$do_codecs" = 1 ]; then
  say "Drivers de video con codificación H.264/HEVC"
  gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
  if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    info "Habilitando RPM Fusion (free)…"
    run sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
  fi
  case $gpu in
    *AMD*|*ATI*|*Radeon*)
      info "GPU AMD detectada."
      run sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || warn "Falló el swap de mesa-va-drivers (¿ya estaba en freeworld?)."
      run sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || warn "Falló el swap de mesa-vdpau-drivers."
      ;;
    *Intel*)
      info "GPU Intel detectada."
      run sudo dnf install -y intel-media-driver ;;
    *NVIDIA*|*nvidia*)
      warn "GPU NVIDIA: usa el driver propietario de RPM Fusion (akmod-nvidia); Steam usará NVENC. No hago cambios." ;;
    *) warn "No pude identificar la GPU; omito los drivers." ;;
  esac
  info "Reinicia sesión (o el PC) para que los drivers nuevos se carguen."
fi

# --- 5. Bloqueo de pantalla --------------------------------------------------
if [ "$OPT_LOCK" = 1 ]; then
  say "Desactivando el bloqueo automático de pantalla (una pantalla bloqueada da stream negro)"
  kw=$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)
  if [ -n "$kw" ]; then
    run "$kw" --file kscreenlockerrc --group Daemon --key Autolock false
    run "$kw" --file kscreenlockerrc --group Daemon --key LockOnResume false
  else
    warn "No encuentro kwriteconfig; desactívalo a mano en Ajustes > Seguridad y privacidad > Bloqueo de pantalla."
  fi
fi

# --- 6. Scripts --------------------------------------------------------------
say "Instalando scripts en ~/.local"
BIN="$HOME/.local/bin"; LIB="$HOME/.local/lib/fedora-mac-remoteplay"
run mkdir -p "$BIN" "$LIB"
run install -m 0755 "$REPO_DIR/bin/remoteplay-launch" "$BIN/remoteplay-launch"
run install -m 0755 "$REPO_DIR/bin/remoteplay-doctor" "$BIN/remoteplay-doctor"
run install -m 0644 "$REPO_DIR/lib/env.sh" "$LIB/env.sh"
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN no está en tu PATH; se usa la ruta completa desde el Mac, no pasa nada." ;; esac

# --- 7. Autostart ------------------------------------------------------------
if [ "$OPT_AUTOSTART" = 1 ]; then
  say "Steam arrancará con -pipewire al iniciar sesión"
  AUTO="$HOME/.config/autostart"
  run mkdir -p "$AUTO"
  # Un autostart propio de Steam arrancaría sin -pipewire y se interpondría.
  if [ -f "$AUTO/steam.desktop" ]; then
    run mv "$AUTO/steam.desktop" "$AUTO/steam.desktop.bak"
    info "Moví el autostart original de Steam a steam.desktop.bak (evita arrancar sin -pipewire)."
  fi
  if [ "$DRY" = 1 ]; then
    info "[dry-run] escribir $AUTO/fedora-mac-remoteplay.desktop"
  else
    cat >"$AUTO/fedora-mac-remoteplay.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Steam (Remote Play host)
Comment=Inicia Steam con -pipewire para captura en Wayland
Exec=$BIN/remoteplay-launch --silent --no-restart --delay 8
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  fi
fi

# --- 8. Inicio de sesión automático -----------------------------------------
if [ "$OPT_AUTOLOGIN" = 1 ]; then
  say "Inicio de sesión automático"
  warn "Cualquiera con acceso físico al PC entrará a tu sesión sin contraseña."
  if systemctl is-enabled sddm >/dev/null 2>&1 || [ "$DRY" = 1 ]; then
    sess=plasma
    if [ ! -f /usr/share/wayland-sessions/plasma.desktop ]; then
      first=$(find /usr/share/wayland-sessions -name '*plasma*.desktop' 2>/dev/null | head -n1 || true)
      if [ -n "$first" ]; then sess=$(basename "$first" .desktop); fi
    fi
    run sudo mkdir -p /etc/sddm.conf.d
    if [ "$DRY" = 1 ]; then
      info "[dry-run] escribir /etc/sddm.conf.d/zz-remoteplay-autologin.conf (User=$(id -un), Session=$sess)"
    else
      printf '[Autologin]\nUser=%s\nSession=%s\n' "$(id -un)" "$sess" | sudo tee /etc/sddm.conf.d/zz-remoteplay-autologin.conf >/dev/null
    fi
  else
    warn "SDDM no está habilitado (¿Plasma Login Manager?). Configura el inicio automático en Ajustes > Inicio de sesión."
  fi
fi

# --- Fin ---------------------------------------------------------------------
say "Listo"
ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
cat <<EOF
    Usuario SSH : $(id -un)
    IP del PC   : ${ip:-(no detectada)}   (o  $(hostname).local)

    Siguiente paso, desde tu Mac:
        ./mac/remoteplay-mac setup $(id -un)@${ip:-IP_DEL_PC}

    Para comprobar este PC en cualquier momento:  remoteplay-doctor
EOF
