#!/bin/bash
# build.sh - Compila os patches Java do launcher Linux do SAD Assinador.
#
#   src/SadPreMain.java
#   src/br/gov/go/detran/sad/WrapperKeyStoreSpi.java
#   src/br/gov/go/detran/sad/controller/VerificaSO.java
#
# Uso:
#   ./build.sh                 # compila contra a versão mais nova extraída
#   ./build.sh 1.4.1           # compila contra SAD-Assinadorv1.4.1/
#   ./build.sh /caminho/da/pasta
#
# Requer um JDK 8 com JavaFX (ex.: Zulu 8 FX em ~/java/).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$DIR/src"
OUT_DIR="$DIR/build/classes"

# Encontra um javac (preferência: Zulu 8 FX em ~/java)
JAVAC="$(ls "$HOME"/java/zulu*fx*/bin/javac 2>/dev/null | head -1 || true)"
if [ -z "$JAVAC" ] && command -v javac >/dev/null 2>&1; then
  JAVAC="$(command -v javac)"
fi
if [ -z "$JAVAC" ]; then
  echo "ERRO: javac não encontrado. Instale o Zulu 8 FX em ~/java/." >&2
  exit 1
fi

# Resolve a pasta do SAD alvo
SAD_DIR=""
if [ $# -ge 1 ] && [ -n "${1:-}" ]; then
  case "$1" in
    */*) SAD_DIR="$1" ;;
    *)   SAD_DIR="$DIR/SAD-Assinadorv${1#SAD-Assinadorv}" ;;
  esac
else
  mapfile -t CANDIDATES < <(
    for d in "$DIR"/SAD-Assinadorv*; do
      [ -d "$d" ] || continue
      [ -f "$d/br/gov/go/detran/sad/MainApp.class" ] || continue
      base="$(basename "$d")"
      ver="${base#SAD-Assinadorv}"
      printf "%s|%s\n" "$(echo "$ver" | awk -F. '{printf "%03d.%03d.%03d", $1, $2, $3}')" "$d"
    done | sort -r | cut -d'|' -f2
  )
  [ "${#CANDIDATES[@]}" -gt 0 ] && SAD_DIR="${CANDIDATES[0]}"
fi

if [ -z "$SAD_DIR" ] || [ ! -f "$SAD_DIR/br/gov/go/detran/sad/MainApp.class" ]; then
  echo "ERRO: pasta do SAD não encontrada (esperado SAD-AssinadorvX.Y.Z/)." >&2
  echo "Extraia o .exe primeiro: ./extract-sad.sh SAD-AssinadorvX.Y.Z.exe" >&2
  exit 1
fi

SAD_VERSION="$(grep -oP '^version\s*=\s*\K\S+' "$SAD_DIR/config.properties" 2>/dev/null \
  || basename "$SAD_DIR" | sed 's/^SAD-Assinadorv//')"
echo "[build] Compilando patches contra a versão $SAD_VERSION ($SAD_DIR)"

# Limpa classes geradas anteriormente (não apaga fontes)
mkdir -p "$OUT_DIR"
find "$OUT_DIR" -name '*.class' -delete 2>/dev/null || true

# Lista de fontes
mapfile -t SOURCES < <(find "$SRC_DIR" -name '*.java' | sort)
if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "ERRO: nenhum .java encontrado em $SRC_DIR" >&2
  exit 1
fi

# Compila tudo de uma vez, com o SAD como classpath.
# (A lista usa arrays, então caminhos com espaço funcionam.)
"$JAVAC" -encoding UTF-8 -cp "$SAD_DIR" -d "$OUT_DIR" "${SOURCES[@]}"

# Marca contra qual versão os patches foram compilados
printf '%s\n' "$SAD_VERSION" > "$OUT_DIR/.build-version"

echo "[build] OK: classes geradas em $OUT_DIR (versão $SAD_VERSION)"
