#!/bin/bash
# instalar.sh - Instala e prepara o SAD Assinador para Linux (com token eToken)
#
# Pré-requisitos (precisa de sudo):
#   - pcscd (leitor de smartcard) - geralmente já vem; se não: apt install pcscd
#   - SafeNet Authentication Client (SAC) para Linux já instalado, com
#     /usr/lib/libeToken.so presente. O SAC é proprietário (portal Thales) e
#     NÃO é baixado por este script.
#
# O que este script faz:
#   1. Baixa e extrai o JDK 8 + JavaFX (Zulu FX) em ~/java (se ainda não existir).
#   2. Copia a pasta do SAD Assinador (informada pelo usuário) para ~/Apps/SAD.
#   3. Aplica o patch de correções de Linux (patch.sh).
#   4. Cria um atalho .desktop no menu de aplicativos.
#
# Uso:
#   ./instalar.sh /caminho/para/SAD-Assinadorv1.2.0
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Uso: $0 /caminho/para/SAD-Assinadorv1.2.0" >&2
  exit 1
fi

SAD_SRC="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAVA_DIR="$HOME/java"
ZULU_VER="zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64"
ZULU_URL="https://cdn.azul.com/zulu/bin/${ZULU_VER}.tar.gz"
APP_DIR="$HOME/Apps/SAD"

if [ ! -d "$SAD_SRC" ] || [ ! -f "$SAD_SRC/br/gov/go/detran/sad/MainApp.class" ]; then
  echo "ERRO: informe a pasta extraída do SAD Assinador v1.2.0." >&2
  exit 1
fi

# 1) JDK Zulu FX
if [ ! -x "$JAVA_DIR/$ZULU_VER/bin/java" ]; then
  echo "==> Baixando JDK 8 + JavaFX (Zulu FX)..."
  mkdir -p "$JAVA_DIR"
  TMPZ="$(mktemp -d)"
  curl -sL --max-time 600 -o "$TMPZ/zulu.tar.gz" "$ZULU_URL"
  tar xzf "$TMPZ/zulu.tar.gz" -C "$JAVA_DIR"
  rm -rf "$TMPZ"
else
  echo "==> JDK Zulu FX já presente."
fi
JAVA_BIN="$JAVA_DIR/$ZULU_VER/bin/java"

# 2) Copiar pasta do SAD para ~/Apps/SAD
echo "==> Instalando SAD em $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -r "$SAD_SRC/." "$APP_DIR/"

# 3) Aplicar patch de correções
echo "==> Aplicando correções de Linux..."
"$SCRIPT_DIR/patches/patch.sh" "$APP_DIR" "$JAVA_DIR/$ZULU_VER/bin/javac"

# 4) Atalho .desktop
DESKTOP_FILE="$HOME/.local/share/applications/sad-assinador.desktop"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=SAD Assinador (Linux)
Comment=Assinador Digital Detran-GO com token eToken no Linux
Exec=$APP_DIR/sad-assinador.sh
Icon=$APP_DIR/imagens/logoDetran.png
Terminal=false
Type=Application
Categories=Office;Java;
EOF
chmod +x "$DESKTOP_FILE"
echo "==> Atalho criado: $DESKTOP_FILE"

# 5) Launcher local na pasta
cp "$SCRIPT_DIR/scripts/sad-assinador.sh" "$APP_DIR/sad-assinador.sh"
chmod +x "$APP_DIR/sad-assinador.sh"

echo ""
echo "✅ Instalação concluída!"
echo "Abra o SAD pelo menu de aplicativos ou rode: $APP_DIR/sad-assinador.sh"
echo ""
echo "Lembre-se: o SafeNet Authentication Client (SAC) para Linux precisa estar"
echo "instalado e o token USB conectado. Depois, em Configurar Certificado -> A3,"
echo "use Módulo = /usr/lib/libeToken.so e seu PIN."
