#!/bin/bash
# sad-assinador.sh - Launcher do SAD Assinador para Linux
# Localiza automaticamente o JDK 8 + JavaFX (Zulu FX) em ~/java e roda o programa.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# Procura um JDK Zulu FX em ~/java
JAVA_BIN="$(ls "$HOME"/java/zulu*fx*/bin/java 2>/dev/null | head -1 || true)"
if [ -z "$JAVA_BIN" ] && command -v java >/dev/null 2>&1; then
  JAVA_BIN="java"
fi

if [ -z "$JAVA_BIN" ]; then
  echo "ERRO: JDK não encontrado. Rode scripts/instalar.sh ou baixe o Zulu 8 FX." >&2
  exit 1
fi

cd "$DIR"
exec "$JAVA_BIN" -cp ".:jdtCompilerAdapter.jar" br.gov.go.detran.sad.MainApp "$@"
