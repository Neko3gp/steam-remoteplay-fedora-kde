# fedora-mac-remoteplay

Juega los juegos de tu PC con **Fedora KDE Plasma (Wayland)** desde tu **Mac** usando Steam Remote Play, sin pantallas negras ni errores de captura.

Resuelve los problemas típicos de Remote Play en Plasma 6 / Wayland:

| Síntoma | Causa | Lo que hace este repo |
|---|---|---|
| "Ocurrió un error al hacer la captura… usa `-pipewire`" | Steam no captura Wayland por defecto | Lanza Steam con `-pipewire` (y lo deja en autostart) |
| `Authorization required… Unable to open X11 display` al lanzar por SSH | Falta `XAUTHORITY` / `DISPLAY` de la sesión | `remoteplay-launch` los detecta solo |
| Stream en negro aunque conecta | La pantalla del PC está bloqueada | Desactiva el bloqueo automático y avisa si está bloqueada |
| No encuentra el PC / se queda cargando | Puertos cerrados o permiso de red local del Mac | Abre puertos en firewalld; recordatorio del permiso en macOS |
| Mucha carga de CPU / latencia (`Created encoder X264`) | Fedora trae Mesa sin H.264/HEVC | Opción `--codecs` instala drivers *freeworld* de RPM Fusion |

## Requisitos

- **PC (host):** Fedora con KDE Plasma en Wayland, Steam instalado (RPM Fusion o Flatpak), conectado por ethernet de preferencia.
- **Mac (cliente):** macOS con **Steam Link** (App Store) o el cliente de Steam, en la misma red.

## Instalación

### 1. En el PC con Fedora

```bash
git clone <URL-de-este-repo> fedora-mac-remoteplay
cd fedora-mac-remoteplay
./install.sh --dry-run     # ver qué hará, sin cambiar nada
./install.sh               # instalar
```

Opciones útiles: `--codecs` (drivers de video por hardware), `--autologin` (el PC arranca ya en el escritorio), `-y` (sin preguntas). Ver `./install.sh --help`.

> `--autologin` hace que cualquiera con acceso físico al PC entre a tu sesión sin contraseña. Es opcional.

Al terminar, el instalador te muestra tu usuario e IP.

### 2. En el Mac

```bash
git clone <URL-de-este-repo> fedora-mac-remoteplay
cd fedora-mac-remoteplay
./mac/remoteplay-mac setup usuario@IP_DEL_PC
```

Luego en **Ajustes del Sistema → Privacidad y seguridad → Red local**, activa Steam / Steam Link.

### 3. Jugar

```bash
./mac/remoteplay-mac up
```

Reinicia Steam en el PC con `-pipewire`, abre Steam Link en el Mac y ya puedes elegir tu PC y el juego. Otros comandos: `down`, `doctor`, `ssh`, `open`.

## Diagnóstico

En el PC (o desde el Mac con `remoteplay-mac doctor`):

```bash
remoteplay-doctor
```

Revisa sesión Wayland, bloqueo de pantalla, Steam con `-pipewire`, PipeWire/portal, firewall, sshd, codificación por hardware y el último `streaming_log.txt`, con la solución sugerida para cada fallo.

## Limitaciones conocidas

- **El PC necesita una sesión gráfica abierta.** Si está en la pantalla de login, no hay nada que capturar (usa `--autologin`).
- Con `-pipewire`, la **primera vez** Plasma puede mostrar en el PC un diálogo de permiso para compartir pantalla; hay que aceptarlo una vez físicamente.
- Si el PC no tiene monitor, algunos drivers no generan imagen: usa un *dummy plug* HDMI.
- El mensaje "Unable to open a connection to X" que puede quedar en pantalla por un lanzamiento anterior se cierra con *Aceptar*; no afecta al stream.
- Fedora con **Plasma Login Manager** en lugar de SDDM: `--autologin` no lo configura; hazlo en Ajustes.
- GPU NVIDIA: el instalador no toca drivers; Steam usa NVENC con el driver propietario.
- Si Steam Remote Play sigue dando problemas, **Sunshine + Moonlight** es una alternativa que captura por KMS y evita el portal.

## Desinstalar

```bash
./uninstall.sh                 # quita scripts y autostart
./uninstall.sh --close-ports   # además cierra los puertos
```

## Estado

Los scripts nacieron de una configuración real (Fedora 44, KDE Plasma, AMD RX 6600 → Mac M1 por ethernet). El flujo manual de lanzamiento con `-pipewire` fue verificado; los scripts de este repositorio se escribieron después y deben probarse en cada equipo. Reporta lo que falle junto con la salida de `remoteplay-doctor`.

## Licencia

MIT
