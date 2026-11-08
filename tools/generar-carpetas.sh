#!/usr/bin/env bash
# Genera el tema de iconos superpuesto "SelNic-folders": recolorea las carpetas
# de Yaru-blue con el color `folder` de colors.toml.
#
# Por qué hace falta:
#
#   GTK marca un icono como "symbolic" por extensión ('symb.*',
#   '*.symbolic.png', '*-symbolic.svg'). Si el archivo se llama *-symbolic.svg,
#   GTK lo repinta con el color de primer plano del tema e ignora el atributo
#   fill. Editar el fill a mano no produce ningún cambio visible.
#
#   La rejilla de Nautilus usa PNG a color, así que aquí se recolorean esos PNG:
#   se fija el tono al del color pedido y se escalan saturación y luminosidad
#   por la razón destino/origen. El cuerpo cae en el color exacto y sobreviven
#   el relieve 3D y los emblemas de las carpetas especiales.
#
#   El lateral de Nautilus se deja sin tocar: GTK pinta los glifos simbólicos
#   con el color de primer plano, así que heredan el blanco de Yaru-blue.
#
# El tema solo hereda de Yaru-blue: el resto de iconos sigue viniendo de ahí y
# las actualizaciones de Yaru se propagan solas.
#
#   Uso:  tools/generar-carpetas.sh
#   Variables: SELNIC_CARPETAS_COLOR, SELNIC_ICONS_DIR

set -euo pipefail

COLOR="${SELNIC_CARPETAS_COLOR:-#5A96BA}"
DESTINO="${SELNIC_ICONS_DIR:-$HOME/.local/share/icons/SelNic-folders}"
BASE=/usr/share/icons/Yaru-blue

# H, S y L en HSL de un color #RRGGBB, en bash para no depender de python en la
# ruta de instalación. Se usa HSL y no HSV porque es lo que hace ImageMagick con
# `-colorspace HSL`: canal R = H, G = S, B = L.
hsl_de() {
  local h="${1#\#}" r g b mx mn d
  r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
  mx=$r; [ "$g" -gt "$mx" ] && mx=$g; [ "$b" -gt "$mx" ] && mx=$b
  mn=$r; [ "$g" -lt "$mn" ] && mn=$g; [ "$b" -lt "$mn" ] && mn=$b
  d=$((mx - mn))
  # H en grados. Con d=0 (gris) no hay tono que forzar: se deja en 0.
  if [ "$d" -eq 0 ]; then hue=0
  elif [ "$mx" -eq "$r" ]; then hue=$(( ((g - b) * 60 / d + 360) % 360 ))
  elif [ "$mx" -eq "$g" ]; then hue=$(( ((b - r) * 60 / d + 120) % 360 ))
  else hue=$(( ((r - g) * 60 / d + 240) % 360 )); fi
  # L = (max+min)/2, en porcentaje
  awk -v hue="$hue" -v mx="$mx" -v mn="$mn" -v d="$d" 'BEGIN{
    l = (mx+mn)*50/255
    if (l > 0.5) s = d/(510 - mx - mn); else s = d/(mx + mn)
    printf "%d %.6f %.6f", hue, s*100, l
  }'
}

# Factores de recoloreado calculados a partir del cuerpo real de Yaru-blue y
# del color pedido, en vez de fijos a ojo.
#
# El cuerpo de la rejilla es opaco, así que el píxel escrito es el color que se
# ve: no hace falta componer sobre el fondo. Se lleva H al destino (con set) y
# se multiplican S y L por la razón destino/origen, con lo que el cuerpo cae
# justo en $COLOR y el relieve se conserva en proporción.
CUERPO="${SELNIC_CARPETAS_CUERPO:-#2686E6}"
read -r _ S_O L_O <<<"$(hsl_de "$CUERPO")"
read -r H_D S_D L_D <<<"$(hsl_de "$COLOR")"

TONO="${SELNIC_CARPETAS_TONO:-$(awk -v h="$H_D" 'BEGIN{printf "%.4f%%", h*100/360}')}"
F_S="${SELNIC_CARPETAS_SAT:-$(awk -v d="$S_D" -v o="$S_O" 'BEGIN{printf "%.6f", (o+0>0? d/o : 1)}')}"
F_L="${SELNIC_CARPETAS_LUX:-$(awk -v d="$L_D" -v o="$L_O" 'BEGIN{printf "%.6f", (o+0>0? d/o : 1)}')}"

rm -rf "$DESTINO"
mkdir -p "$DESTINO"

# Copia la sección [dir] tal cual desde el index.theme de Yaru-blue, para no
# tener que acertar Size/MinSize/MaxSize/Scale a mano (GTK avisa y lo ignora).
# Si la sección no existe, la inventa: un directorio sin Size rompe el tema.
seccion_de() {
  local d="$1" cuerpo
  cuerpo="$(awk -v s="[$d]" 'BEGIN{p=0} $0==s{p=1;next} /^\[/{p=0} p&&NF' "$BASE/index.theme")"
  if [ -z "$cuerpo" ]; then
    local px="${d%%/*}"
    cuerpo="Context=Places"$'\n'"Size=$px"$'\n'"Type=Fixed"
  fi
  echo "[$d]"
  printf '%s\n' "$cuerpo"
  echo
}

DIRS_USADOS=()

marcar_dir() {
  local d="$1"
  for x in "${DIRS_USADOS[@]:-}"; do [ "$x" = "$d" ] && return 0; done
  DIRS_USADOS+=("$d")
}

echo "  color: $COLOR   destino: $DESTINO"

# ------------------------------------------------------------------ rejilla
# Recolorea conservando la estructura de cada píxel (relieve 3D, emblemas de
# Documents/Downloads/Music): se fija el tono y se reajustan saturación y luz
# para que el cuerpo dominante de la rejilla caiga en $COLOR.
recolorear() {
  magick "$1" \
    -colorspace HSL \
    -channel R -evaluate set "$TONO" +channel \
    -channel G -evaluate multiply "$F_S" +channel \
    -channel B -evaluate multiply "$F_L" +channel \
    -colorspace sRGB "$2"
}

n_png=0
while IFS= read -r f; do
  rel="${f#"$BASE"/}"
  dir="${rel%/*}"
  mkdir -p "$DESTINO/$dir"
  recolorear "$f" "$DESTINO/$rel"
  marcar_dir "$dir"
  n_png=$((n_png + 1))
done < <(find "$BASE" -type f \( \
  -name 'folder.png' -o -name 'folder-*.png' -o \
  -name 'user-home.png' -o -name 'user-desktop.png' -o \
  -name 'inode-directory.png' \) | sort)

# --------------------------------------------------------------------- índice
{
  echo "[Icon Theme]"
  echo "Name=SelNic-folders"
  echo "Comment=Carpetas de la rejilla en $COLOR (acento SelNic); lateral blanco heredado de Yaru-blue"
  echo "Inherits=Yaru-blue,Humanity,hicolor"
  echo "Example=folder"
  printf 'Directories='
  sep=""
  for d in "${DIRS_USADOS[@]}"; do
    printf '%s%s' "$sep" "$d"
    sep=","
  done
  echo
  echo
  for d in "${DIRS_USADOS[@]}"; do
    seccion_de "$d"
  done
} > "$DESTINO/index.theme"

gtk-update-icon-cache -q -f -t "$DESTINO"

# --------------------------------------------------------------- autocomprobación
# Un directorio declarado sin Size, o vacío, hace que GTK lo ignore y caiga de
# vuelta al SVG. Se comprueba aquí.
fallos=0
for d in "${DIRS_USADOS[@]}"; do
  if ! awk -v s="[$d]" 'BEGIN{p=0} $0==s{p=1;next} /^\[/{p=0} p&&/^Size=/' \
       "$DESTINO/index.theme" | grep -q .; then
    echo "  FALLO: el directorio $d no declara Size" >&2
    fallos=$((fallos + 1))
  fi
  if [ -z "$(find "$DESTINO/$d" -name '*.png' -print -quit 2>/dev/null)" ]; then
    echo "  FALLO: el directorio $d no tiene ningún PNG" >&2
    fallos=$((fallos + 1))
  fi
done

echo "  lateral:  glifos planos, sin tocar (heredados en blanco de Yaru-blue)"
echo "  rejilla:  $n_png PNG recoloreados"
echo "  peso:     $(du -sh "$DESTINO" | cut -f1)"
[ "$fallos" -gt 0 ] && { echo "  $fallos problemas, no apliques el tema todavía" >&2; exit 1; }
echo "  autocomprobación: ${#DIRS_USADOS[@]} directorios correctos"
echo
echo "  aplica con:   gsettings set org.gnome.desktop.interface icon-theme 'SelNic-folders'"
echo "  revierte con: gsettings set org.gnome.desktop.interface icon-theme 'Yaru-blue'"
