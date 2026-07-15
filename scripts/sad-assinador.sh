#!/bin/bash
# sad-assinador.sh - Launcher do SAD Assinador para Linux
# Detecta automaticamente a pasta do SAD (que contém MainApp.class) e roda o programa.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Procura a subpasta que contém o SAD (tem MainApp.class)
SAD_DIR=""
for candidate in "$DIR"/SAD-Assinador* "$DIR"/SAD*; do
  if [ -f "$candidate/br/gov/go/detran/sad/MainApp.class" ]; then
    SAD_DIR="$candidate"
    break
  fi
done

if [ -z "$SAD_DIR" ]; then
  echo "ERRO: pasta do SAD não encontrada em $DIR" >&2
  echo "Esperado: uma subpasta SAD-Assinadorv1.2.0 (ou similar) com MainApp.class" >&2
  exit 1
fi

# Procura um JDK Zulu FX em ~/java
JAVA_BIN="$(ls "$HOME"/java/zulu*fx*/bin/java 2>/dev/null | head -1 || true)"
if [ -z "$JAVA_BIN" ] && command -v java >/dev/null 2>&1; then
  JAVA_BIN="java"
fi

if [ -z "$JAVA_BIN" ]; then
  echo "ERRO: JDK não encontrado. Rode scripts/instalar.sh ou baixe o Zulu 8 FX." >&2
  exit 1
fi

cd "$SAD_DIR"
exec "$JAVA_BIN" -cp ".:jdtCompilerAdapter.jar" br.gov.go.detran.sad.MainApp "$@"
