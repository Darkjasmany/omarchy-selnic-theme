#!/usr/bin/env bash
#
# selnic — completa la instalación del tema SelNic.
#
# Este script se ejecuta DESPUÉS de instalar el tema con Omarchy:
#
#   omarchy theme install https://github.com/Darkjasmany/omarchy-selnic-theme.git
#   ~/.config/omarchy/themes/selnic/install.sh
#
# Hace dos cosas que Omarchy no puede hacer por sí solo:
#   1. Genera el tema de iconos SelNic-folders con el color `folder`.
#   2. Aplica unlock.png a Plymouth con omarchy-plymouth-set-by-theme.
#
# Si faltan dependencias para los iconos, el tema cae a Yaru-blue sin romper
# nada. Plymouth solo se ve al reiniciar.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="selnic"
TEMA_INSTALADO="$HOME/.config/omarchy/themes/$THEME_NAME"
ICONS_DIR="$HOME/.local/share/icons/SelNic-folders"

if [ -t 1 ]; then
  TITULO=$'\033[1;36m'; OK=$'\033[32m'; AVISO=$'\033[33m'
  ERROR=$'\033[31m'; TENUE=$'\033[2m'; FIN=$'\033[0m'
else
  TITULO=""; OK=""; AVISO=""; ERROR=""; TENUE=""; FIN=""
fi

titulo() { printf '\n%s%s%s\n' "$TITULO" "$1" "$FIN"; }
paso()   { printf '  %s->%s %s\n' "$TENUE" "$FIN" "$1"; }
hecho()  { printf '  %sok%s  %s\n' "$OK" "$FIN" "$1"; }
aviso()  { printf '  %s!!%s  %s\n' "$AVISO" "$FIN" "$1"; }
fallo()  { printf '  %sXX%s  %s\n' "$ERROR" "$FIN" "$1"; }

color_de_carpetas() {
  sed -n 's/^folder *= *"\(#[0-9A-Fa-f]\{6\}\)".*/\1/p' "$REPO/colors.toml" 2>/dev/null | head -1
}

titulo "SelNic · instalación del tema"

if [ ! -d "$HOME/.config/omarchy" ] || ! command -v omarchy >/dev/null 2>&1; then
  fallo "no se encontró una instalación de Omarchy."
  exit 1
fi

COLOR="$(color_de_carpetas)"
[ -n "$COLOR" ] || COLOR="#5A96BA"

# ------------------------------------------------------------- 1. iconos
titulo "1. Carpetas SelNic-folders"

ICONOS_OK=0
if ! command -v magick >/dev/null 2>&1; then
  aviso "falta ImageMagick (magick); se usará Yaru-blue."
elif [ ! -d /usr/share/icons/Yaru-blue ]; then
  aviso "falta el tema base Yaru-blue; se usará Yaru-blue por defecto."
elif [ ! -x "$REPO/tools/generar-carpetas.sh" ]; then
  aviso "falta tools/generar-carpetas.sh; se usará Yaru-blue."
elif SELNIC_CARPETAS_COLOR="$COLOR" "$REPO/tools/generar-carpetas.sh"; then
  ICONOS_OK=1
  hecho "carpetas generadas en $ICONS_DIR"
else
  aviso "no se pudieron generar los iconos; se usará Yaru-blue."
fi

# `omarchy theme set` lee icons.theme de la copia instalada. Si los iconos no
# existen, se deja Yaru-blue para que el siguiente cambio de tema no aplique un
# tema de iconos inexistente.
if [ -d "$TEMA_INSTALADO" ]; then
  if [ "$ICONOS_OK" -eq 1 ]; then
    printf 'SelNic-folders\n' >"$TEMA_INSTALADO/icons.theme"
    gsettings set org.gnome.desktop.interface icon-theme 'SelNic-folders' 2>/dev/null || true
  else
    printf 'Yaru-blue\n' >"$TEMA_INSTALADO/icons.theme"
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru-blue' 2>/dev/null || true
  fi
fi

# ------------------------------------------------------------- 2. tema
titulo "2. Tema"

if [ ! -d "$TEMA_INSTALADO" ]; then
  aviso "el tema no está instalado en $TEMA_INSTALADO."
  aviso "instálalo con: omarchy theme install https://github.com/Darkjasmany/omarchy-selnic-theme.git"
else
  if omarchy theme set "$THEME_NAME" >/dev/null 2>&1; then
    hecho "tema aplicado: $(omarchy theme current 2>/dev/null || echo "$THEME_NAME")"
  else
    aviso "no se pudo aplicar el tema; revisa: omarchy theme list"
  fi
fi

# ------------------------------------------------------------- 3. Plymouth
titulo "3. Pantalla de desbloqueo"

if ! command -v omarchy-plymouth-set-by-theme >/dev/null 2>&1; then
  aviso "omarchy-plymouth-set-by-theme no está disponible; Plymouth no se tocó."
elif [ -x "$HOME/.config/omarchy/hooks/theme-set.d/selnic-plymouth" ]; then
  paso "Plymouth ya se aplicó con el hook selnic-plymouth"
elif [ ! -f "$REPO/unlock.png" ] || [ ! -f "$REPO/colors.toml" ]; then
  aviso "faltan unlock.png o colors.toml; Plymouth no se tocó."
elif omarchy-plymouth-set-by-theme "$THEME_NAME"; then
  hecho "Plymouth actualizado (se verá al reiniciar)"
else
  aviso "no se pudo aplicar Plymouth; el tema del escritorio sí quedó."
fi

# ------------------------------------------------------------- resumen
titulo "Listo"
cat <<EOF
  Tema:      $TEMA_INSTALADO
  Carpetas:  $([ "$ICONOS_OK" -eq 1 ] && echo "SelNic-folders ($COLOR)" || echo "Yaru-blue")
  Plymouth:  se dibuja al arrancar; reinicia para verlo.

  Comprobar:
    omarchy theme current
    gsettings get org.gnome.desktop.interface icon-theme
EOF
echo
