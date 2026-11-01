# shellcheck shell=bash
# Funciones compartidas: detectan la sesión gráfica de Plasma desde SSH o desde la sesión local.

rp_msg()  { printf '%s\n' "$*"; }
rp_err()  { printf 'ERROR: %s\n' "$*" >&2; }

# Exporta XDG_RUNTIME_DIR, WAYLAND_DISPLAY, DISPLAY, XAUTHORITY y DBUS_SESSION_BUS_ADDRESS
# apuntando a la sesión gráfica activa del usuario actual.
rp_detect_env() {
  local uid s d x
  uid=$(id -u)
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"

  if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do
      case $s in *.lock) continue ;; esac
      if [ -S "$s" ]; then WAYLAND_DISPLAY=$(basename "$s"); break; fi
    done
  fi
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then export WAYLAND_DISPLAY; fi

  if [ -z "${DISPLAY:-}" ]; then
    d=$(find /tmp/.X11-unix -maxdepth 1 -name 'X[0-9]*' 2>/dev/null | sort | head -n1 || true)
    if [ -n "$d" ]; then DISPLAY=":${d##*/X}"; fi
  fi
  if [ -n "${DISPLAY:-}" ]; then export DISPLAY; fi

  if [ -z "${XAUTHORITY:-}" ] || [ ! -f "${XAUTHORITY:-/nonexistent}" ]; then
    x=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'xauth_*' 2>/dev/null | head -n1 || true)
    if [ -n "$x" ]; then XAUTHORITY=$x; fi
  fi
  if [ -n "${XAUTHORITY:-}" ]; then export XAUTHORITY; fi

  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  fi
}

# ¿Hay una sesión gráfica del usuario? (0 = sí)
rp_have_graphical_session() {
  rp_detect_env
  [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]
}

# ¿Está bloqueada la pantalla? (0 = bloqueada). Una pantalla bloqueada da imagen negra en el stream.
rp_session_locked() {
  command -v loginctl >/dev/null 2>&1 || return 1
  local id type locked
  for id in $(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$(id -un)" '$3==u {print $1}'); do
    type=$(loginctl show-session "$id" -p Type --value 2>/dev/null || true)
    case $type in wayland|x11) ;; *) continue ;; esac
    locked=$(loginctl show-session "$id" -p LockedHint --value 2>/dev/null || true)
    if [ "$locked" = "yes" ]; then return 0; fi
  done
  return 1
}

# Rellena el array STEAM_CMD con el comando para lanzar Steam (nativo o Flatpak).
rp_steam_cmd() {
  STEAM_CMD=()
  STEAM_KIND=""
  if command -v steam >/dev/null 2>&1; then
    STEAM_CMD=(steam); STEAM_KIND=native
  elif command -v flatpak >/dev/null 2>&1 && flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
    STEAM_CMD=(flatpak run com.valvesoftware.Steam); STEAM_KIND=flatpak
  else
    return 1
  fi
}
