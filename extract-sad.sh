#!/bin/bash
# extract-sad.sh — extrai uma nova versão do SAD Assinador (.exe) para Linux.
#
# Uso:
#   ./extract-sad.sh SAD-Assinadorv1.4.1.exe
#   ./extract-sad.sh                 # pega o .exe mais novo nesta pasta
#   ./extract-sad.sh --reset-pin     # apaga a senha do token salva
#
# O que faz:
#   1) Extrai o .exe (que é um ZIP embutido) para ./SAD-AssinadorvX.Y.Z/
#   2) Detecta o driver PKCS#11 instalado
#   3) Recompila os patches Java contra a nova versão
#   4) Atualiza os atalhos (menu de apps + Área de Trabalho)
#
# É idempotente: pode rodar de novo com o mesmo .exe sem quebrar nada.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Uso: $0 [SAD-AssinadorvX.Y.Z.exe | --reset-pin]

Sem argumento, usa o .exe mais recente encontrado em:
  $DIR
EOF
}

if [ "${1:-}" = "--reset-pin" ]; then
  exec "$DIR/sad-assinador.sh" --reset-pin
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage; exit 0
fi

if [ $# -ge 1 ]; then
  INSTALLER="$1"
else
  # Procura o .exe mais novo (mtime)
  INSTALLER="$(ls -t "$DIR"/SAD-Assinadorv*.exe 2>/dev/null | head -1 || true)"
  if [ -z "$INSTALLER" ]; then
    echo "ERRO: nenhum SAD-AssinadorvX.Y.Z.exe encontrado em $DIR" >&2
    usage >&2
    exit 2
  fi
fi

[ -f "$INSTALLER" ] || { echo "ERRO: arquivo não encontrado: $INSTALLER" >&2; exit 1; }

BASENAME="$(basename "$INSTALLER")"
case "$BASENAME" in
  SAD-Assinadorv*.exe) ;;
  *) echo "ERRO: o nome do arquivo deve ser 'SAD-AssinadorvX.Y.Z.exe' (recebido: $BASENAME)" >&2; exit 1 ;;
esac

VERSION="${BASENAME#SAD-Assinadorv}"; VERSION="${VERSION%.exe}"
TARGET_DIR="$DIR/SAD-Assinadorv${VERSION}"

command -v 7z >/dev/null 2>&1 || { echo "ERRO: 7z não instalado (sudo apt install p7zip-full)" >&2; exit 1; }

echo "===== SAD Assinador — versão ${VERSION} ====="

if [ -f "$TARGET_DIR/br/gov/go/detran/sad/MainApp.class" ]; then
  echo "[1/4] Já extraída em $TARGET_DIR — pulando extração."
else
  echo "[1/4] Extraindo $BASENAME ..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  7z x -y -o"$TMP" "$INSTALLER" >/dev/null 2>&1 || {
    echo "ERRO: falha ao extrair $BASENAME" >&2; exit 1
  }
  mkdir -p "$TARGET_DIR"
  if [ -f "$TMP/br/gov/go/detran/sad/MainApp.class" ]; then
    cp -a "$TMP"/. "$TARGET_DIR"/
  else
    FOUND="$(find "$TMP" -path '*/br/gov/go/detran/sad/MainApp.class' | head -1)"
    [ -n "$FOUND" ] || { echo "ERRO: MainApp.class não encontrado dentro de $BASENAME" >&2; exit 1; }
    PARENT="${FOUND%/br/gov/go/detran/sad/MainApp.class}"
    cp -a "$PARENT"/. "$TARGET_DIR"/
  fi
fi

ACTUAL_VER="$(grep -oP '^version\s*=\s*\K\S+' "$TARGET_DIR/config.properties" 2>/dev/null || echo "$VERSION")"
echo "       Versão reportada: $ACTUAL_VER"

echo "[2/4] Compilando patches contra a versão $ACTUAL_VER ..."
bash "$DIR/build.sh" "$TARGET_DIR"

echo "[3/4] Detectando/configurando token A3 ..."
"$DIR/sad-assinador.sh" --check --atalho || true

echo "[4/4] Atalhos atualizados."

cat <<EOF

===== Pronto! =====

  Versão:   ${ACTUAL_VER}
  Pasta:    ${TARGET_DIR}
  Abrir:    ${DIR}/sad-assinador.sh
  Atalhos:  menu de aplicativos + Área de Trabalho

Só abrir o ícone "SAD Assinador" (ou rodar o comando acima).
A senha do token é pedida uma única vez e fica salva criptografada.
Se trocar o token/senha: ./extract-sad.sh --reset-pin
EOF
