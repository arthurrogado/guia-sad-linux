#!/bin/bash
# patch.sh - Aplica as correções de Linux no SAD Assinador
#
# O que este script faz:
#   1. Recompila os 2 arquivos .java de correção (CertificadoA3RepositoryImpl e
#      TrustAllCertificates) usando um JDK 8 que contenha JavaFX (ex.: Zulu FX).
#   2. Injeta os .class gerados dentro da pasta do SAD Assinador (que o usuário
#      já extraiu do instalador oficial do Detran-GO).
#   3. Cria/atualiza o ~/.signer/drivers.properties para o eToken ser o 1º driver.
#
# Uso:
#   ./patch.sh /caminho/para/SAD-Assinadorv1.2.0 [CAMINHO_DO_JAVAC]
#
# Se CAMINHO_DO_JAVAC não for informado, o script procura por um JDK Zulu FX em
# ~/java e por 'javac' no PATH.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Uso: $0 /caminho/para/SAD-Assinadorv1.2.0 [CAMINHO_DO_JAVAC]" >&2
  exit 1
fi

SAD_DIR="$1"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$SAD_DIR" ]; then
  echo "ERRO: pasta do SAD não encontrada: $SAD_DIR" >&2
  exit 1
fi

if [ ! -f "$SAD_DIR/br/gov/go/detran/sad/MainApp.class" ]; then
  echo "ERRO: esta não parece ser a pasta do SAD Assinador (MainApp.class ausente)." >&2
  exit 1
fi

# --- Resolver javac -------------------------------------------------------
JAVAC="${2:-}"
if [ -z "$JAVAC" ]; then
  # tenta Zulu FX em ~/java
  ZULU=$(ls -d "$HOME"/java/zulu*fx* 2>/dev/null | head -1 || true)
  if [ -n "$ZULU" ] && [ -x "$ZULU/bin/javac" ]; then
    JAVAC="$ZULU/bin/javac"
  elif command -v javac >/dev/null 2>&1; then
    JAVAC="javac"
  fi
fi

if [ -z "$JAVAC" ] || [ ! -x "$JAVAC" ]; then
  echo "ERRO: não foi possível encontrar 'javac' (JDK 8). Informe o caminho como 2º argumento." >&2
  echo "Dica: baixe o Zulu 8 FX em https://cdn.azul.com/zulu/bin/" >&2
  exit 1
fi

echo "Usando javac: $JAVAC"

# --- Compilar -------------------------------------------------------------
TMPOUT="$(mktemp -d)"
trap 'rm -rf "$TMPOUT"' EXIT

echo "Compilando correções..."
"$JAVAC" -cp "$SAD_DIR:$(ls "$SAD_DIR"/*.jar 2>/dev/null | tr '\n' ':')" \
  -d "$TMPOUT" \
  "$PATCH_DIR/CertificadoA3RepositoryImpl.java" \
  "$PATCH_DIR/TrustAllCertificates.java"

# --- Injetar .class -------------------------------------------------------
echo "Injetando .class corrigidos em $SAD_DIR ..."
cp -v "$TMPOUT/br/gov/go/detran/sad/impl/CertificadoA3RepositoryImpl.class" \
      "$SAD_DIR/br/gov/go/detran/sad/impl/"
cp -v "$TMPOUT/br/gov/go/detran/sad/impl/CertificadoA3RepositoryImpl\$1.class" \
      "$SAD_DIR/br/gov/go/detran/sad/impl/" 2>/dev/null || true
cp -v "$TMPOUT/br/gov/go/detran/rs/client/TrustAllCertificates.class" \
      "$SAD_DIR/br/gov/go/detran/rs/client/"

# --- drivers.properties (eToken como 1º driver) ---------------------------
SIGNNER_DIR="$HOME/.signer"
mkdir -p "$SIGNNER_DIR"
printf '0_eToken=/usr/lib/libeToken.so\n' > "$SIGNNER_DIR/drivers.properties"
echo "Criado $SIGNNER_DIR/drivers.properties"

echo ""
echo "✅ Correções aplicadas com sucesso em: $SAD_DIR"
echo "Agora abra o SAD (via scripts/sad-assinador.sh) e configure o Certificado A3."
