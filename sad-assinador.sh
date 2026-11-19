#!/bin/bash
# sad-assinador.sh — abre o SAD Assinador (Detran-GO) no Linux.
#
# Feito para ser "clicou e abriu":
#   - acha sozinho o .exe mais novo na pasta e extrai se ainda não extraiu
#   - acha sozinho o driver PKCS#11 (eToken/SafeNet, SafeSign, OpenSC...)
#   - liga o pcscd se precisar
#   - guarda a senha do token uma única vez (criptografada) e autentica
#     o certificado A3 automaticamente nas próximas vezes
#   - cria/atualiza o atalho no menu de aplicativos e na Área de Trabalho
#
# Uso:
#   ./sad-assinador.sh                menu: instalar, abrir, diagnóstico...
#   ./sad-assinador.sh --nao-abrir    prepara tudo e não abre
#   ./sad-assinador.sh --atalho       cria/atualiza o atalho
#   ./sad-assinador.sh --sem-atalho   abre sem mexer em atalhos
#   ./sad-assinador.sh --check        só valida o ambiente (não abre)
#   ./sad-assinador.sh --diag         diagnóstico completo
#   ./sad-assinador.sh --reset-pin    apaga a senha salva (pede de novo)
#   ./sad-assinador.sh --desinstalar  remove os atalhos
#   SAD_VERSION=1.3.0 ./sad-assinador.sh   força uma versão
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$DIR/build/classes"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/assinador"
CONFIG_FILE="$CONFIG_DIR/config.json"
TOKEN_PIN_FILE="$CONFIG_DIR/token.pin.gpg"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sad-assinador"
LOG_FILE="$STATE_DIR/launcher.log"
APPS_DIR="$HOME/.local/share/applications"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -n "${DESKTOP_DIR:-}" ] || DESKTOP_DIR="$HOME/Desktop"

mkdir -p "$CONFIG_DIR" "$STATE_DIR"
chmod 700 "$CONFIG_DIR" 2>/dev/null || true

# ── Saída: terminal + log (para diagnosticar quando aberto pelo ícone) ──────
if [ -t 0 ] || [ -t 1 ]; then SAD_TTY=1; else SAD_TTY=0; fi
if [ -t 1 ]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
else
  exec >>"$LOG_FILE" 2>&1
fi

log()  { echo "[SAD] $*"; }
warn() { echo "[SAD] AVISO: $*"; }
die()  { echo "[SAD] ERRO: $*" >&2; type gui_error >/dev/null 2>&1 && gui_error "SAD Assinador: $*"; exit 1; }

# ── Argumentos ──────────────────────────────────────────────────────────────
MODE="run"
SHORTCUT_MODE="auto"   # auto | yes | no
APP_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check)       MODE="check" ;;
    --diag)        MODE="diag" ;;
    --reset-pin)   MODE="reset-pin" ;;
    --desinstalar) MODE="uninstall" ;;
    --nao-abrir)   MODE="install" ;;
    --atalho)      SHORTCUT_MODE="yes" ;;
    --sem-atalho)  SHORTCUT_MODE="no" ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --) shift; APP_ARGS=("$@"); break ;;
    *) APP_ARGS+=("$1") ;;
  esac
  shift
done

# ── Interface gráfica opcional (para quando aberto pelo ícone) ──────────────
HAS_GUI=0
if [ -n "${DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
  HAS_GUI=1
fi

gui_progress() { # gui_progress "texto" comando...
  local text="$1"; shift
  if [ "$HAS_GUI" = 1 ] && [ "$MODE" = "run" ]; then
    zenity --progress --pulsate --auto-close --no-cancel --width=380 \
      --title="SAD Assinador" --text="$text" >/dev/null 2>&1 &
    local zpid=$!
    "$@" && { kill "$zpid" 2>/dev/null || true; return 0; }
    local rc=$?
    kill "$zpid" 2>/dev/null || true
    return $rc
  fi
  "$@"
}

gui_error() {
  if [ "$HAS_GUI" = 1 ] && [ "$MODE" = "run" ]; then
    zenity --error --title="SAD Assinador" --text="$1" --width=420 >/dev/null 2>&1 || true
  fi
}

# ── 1. Java ─────────────────────────────────────────────────────────────────
find_java() {
  local j
  j="$(ls "$HOME"/java/zulu*fx*/bin/java 2>/dev/null | head -1 || true)"
  if [ -z "$j" ]; then
    for j in "$HOME"/java/zulu*/bin/java /usr/lib/jvm/*fx*/bin/java; do
      [ -x "$j" ] && break
      j=""
    done
  fi
  if [ -z "$j" ] && command -v java >/dev/null 2>&1; then
    j="$(command -v java)"
  fi
  printf '%s' "$j"
}

# ── 2. Driver PKCS#11 ───────────────────────────────────────────────────────
detect_driver() {
  local d
  # 1) variável de ambiente apontando para o driver
  if [ -n "${PKCS11_DRIVER:-}" ] && [ -f "${PKCS11_DRIVER#*::}" ]; then
    printf '%s' "${PKCS11_DRIVER#*::}"; return 0
  fi
  # 2) drivers registrados pelo Demoiselle em ~/.signer/drivers.properties
  if [ -f "$HOME/.signer/drivers.properties" ]; then
    while IFS='=' read -r _ p; do
      p="$(echo "${p:-}" | tr -d '\r' | xargs 2>/dev/null || true)"
      [ -n "$p" ] && [ -f "$p" ] && { printf '%s' "$p"; return 0; }
    done < "$HOME/.signer/drivers.properties"
  fi
  # 3) busca nos caminhos usuais, na ordem dos drivers mais comuns
  local search_path driver
  local paths=(/usr/lib/x86_64-linux-gnu/pkcs11 /usr/lib/x86_64-linux-gnu
               /usr/lib /usr/lib64 /usr/local/lib /usr/local/lib64
               /usr/lib/i386-linux-gnu /opt/watchdata/lib64 "$HOME/.signer")
  local drivers=(libeToken.so libetoken.so libaetpkss.so libpk2priv.so
                 libwdpkcs.so opensc-pkcs11.so onepin-opensc-pkcs11.so)
  for search_path in "${paths[@]}"; do
    [ -d "$search_path" ] || continue
    for driver in "${drivers[@]}"; do
      if [ -f "$search_path/$driver" ]; then
        printf '%s' "$search_path/$driver"; return 0
      fi
    done
  done
  return 1
}

# ── 3. pcscd / token ────────────────────────────────────────────────────────
ensure_pcscd() {
  command -v pcscd >/dev/null 2>&1 || { warn "pcscd não instalado (sudo apt install pcscd)"; return 0; }
  pgrep -x pcscd >/dev/null 2>&1 && { log "pcscd já está rodando."; return 0; }
  log "Iniciando pcscd..."
  systemctl start pcscd 2>/dev/null || sudo -n systemctl start pcscd 2>/dev/null || {
    pcscd --auto-exit >/dev/null 2>&1 &
  }
  local i
  for i in 1 2 3 4 5; do
    pgrep -x pcscd >/dev/null 2>&1 && { log "pcscd iniciado."; return 0; }
    sleep 1
  done
  warn "pcscd não subiu — o token pode não ser reconhecido."
}

token_present() {
  if command -v pcsc_scan >/dev/null 2>&1; then
    local out
    out="$(timeout 6 pcsc_scan -r 2>/dev/null | grep -viE '^(PC/SC|Scanning|Using|$)' || true)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  fi
  if command -v lsusb >/dev/null 2>&1; then
    lsusb 2>/dev/null | grep -iE 'safenet|etoken|gemalto|thales|watchdata|feitian|smart.?card|token' || return 1
    return 0
  fi
  return 1
}

# ── 4. Extração automática de .exe novo ─────────────────────────────────────
version_key() { echo "$1" | awk -F. '{printf "%03d.%03d.%03d", $1, $2, $3}'; }

sad_dir_ok() { [ -n "${1:-}" ] && [ -f "$1/br/gov/go/detran/sad/MainApp.class" ]; }

extract_exe() { # extract_exe <arquivo.exe> <versao>
  local exe="$1" ver="$2" target="$DIR/SAD-Assinadorv$2" tmp
  command -v 7z >/dev/null 2>&1 || die "7z não instalado (sudo apt install p7zip-full)"
  mkdir -p "$target"
  log "Extraindo $exe (versão $ver)..."
  tmp="$(mktemp -d)"
  7z x -y -o"$tmp" "$exe" >/dev/null 2>&1 || { rm -rf "$tmp"; die "falha ao extrair $exe"; }
  # 7z deixa o conteúdo na raiz; se veio em subpasta, achamos o MainApp.class
  if [ -f "$tmp/br/gov/go/detran/sad/MainApp.class" ]; then
    cp -a "$tmp"/. "$target"/
  else
    local found parent
    found="$(find "$tmp" -path '*/br/gov/go/detran/sad/MainApp.class' | head -1)"
    [ -n "$found" ] || { rm -rf "$tmp"; die "MainApp.class não encontrado dentro de $exe"; }
    parent="${found%/br/gov/go/detran/sad/MainApp.class}"
    cp -a "$parent"/. "$target"/
  fi
  rm -rf "$tmp"
  sad_dir_ok "$target" || die "extração de $exe ficou incompleta"
  log "Versão $ver extraída em $target"
}

auto_extract_pending() {
  local exe base ver
  shopt -s nullglob
  for exe in "$DIR"/SAD-Assinadorv*.exe; do
    base="$(basename "$exe")"
    ver="${base#SAD-Assinadorv}"; ver="${ver%.exe}"
    if ! sad_dir_ok "$DIR/SAD-Assinadorv$ver"; then
      gui_progress "Preparando a versão $ver..." extract_exe "$exe" "$ver"
    fi
  done
  shopt -u nullglob
}

# ── 5. Escolha da versão ────────────────────────────────────────────────────
choose_sad_dir() {
  local d base ver chosen=""
  local best_key=""
  shopt -s nullglob
  for d in "$DIR"/SAD-Assinadorv*; do
    sad_dir_ok "$d" || continue
    base="$(basename "$d")"; ver="${base#SAD-Assinadorv}"
    if [ -n "${SAD_VERSION:-}" ] && [ "$ver" != "$SAD_VERSION" ]; then continue; fi
    local key; key="$(version_key "$ver")"
    if [ -z "$best_key" ] || [[ "$key" > "$best_key" ]]; then best_key="$key"; chosen="$d"; fi
  done
  shopt -u nullglob
  printf '%s' "$chosen"
}

# ── 6. Senha do token ───────────────────────────────────────────────────────
pin_passphrase() { printf '%s@%s' "$(whoami)" "$(cat /etc/machine-id 2>/dev/null || hostname)"; }

read_saved_pin() {
  [ -f "$TOKEN_PIN_FILE" ] || return 1
  local pin
  pin="$(gpg --batch --quiet --passphrase "$(pin_passphrase)" -d "$TOKEN_PIN_FILE" 2>/dev/null)" || return 1
  [ -n "$pin" ] || return 1
  printf '%s' "$pin"
}

save_pin() {
  printf '%s' "$1" | gpg --batch --yes --quiet --symmetric \
    --cipher-algo AES256 --passphrase "$(pin_passphrase)" \
    --output "$TOKEN_PIN_FILE" 2>/dev/null || return 1
  chmod 600 "$TOKEN_PIN_FILE" 2>/dev/null || true
}

ask_pin() {
  local pin=""
  if [ "$HAS_GUI" = 1 ]; then
    pin="$(zenity --password --title="SAD Assinador — Senha do Token" \
      --text="Digite a senha do seu token A3 (eToken/SafeNet):" 2>/dev/null || true)"
  elif [ -t 0 ]; then
    read -r -s -p "Senha do token A3: " pin || true
    echo ""
  fi
  [ -n "$pin" ] || return 1
  printf '%s' "$pin"
}

# ── 7. Configuração local (JSON válido) ─────────────────────────────────────
ensure_config() { # ensure_config <driver|"">
  local driver="${1:-}"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<EOF
{
  "lastCertificateId": null,
  "defaultOutputDirectory": null,
  "customDriverPaths": [$([ -n "$driver" ] && printf '"%s"' "$driver")],
  "enableTokenMonitoring": true,
  "tokenPollIntervalMs": 3000,
  "locale": "pt-BR"
}
EOF
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
  else
    # Corrige JSON inválido de versões antigas do launcher (vírgula sobrando)
    sed -i -E 's/,[[:space:]]*\]/ ]/g; s/\[[[:space:]]*,/[ /g' "$CONFIG_FILE" 2>/dev/null || true
    if [ -n "$driver" ] && ! grep -qF "$driver" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s|\"customDriverPaths\"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]|\"customDriverPaths\": [\"$driver\"]|" "$CONFIG_FILE" 2>/dev/null || true
    fi
  fi
}

# ── 8. Atalhos (menu de apps + Área de Trabalho) ────────────────────────────
install_shortcuts() { # install_shortcuts <sad_dir> <versao>
  local sad_dir="$1" ver="$2" icon entry target changed=0
  icon="$sad_dir/imagens/detran-log.png"
  [ -f "$icon" ] || icon="applications-office"
  entry="[Desktop Entry]
Type=Application
Version=$ver
Name=SAD Assinador
GenericName=Assinador Digital
Comment=Assinador Digital Detran-GO com token A3 — versão $ver
Exec=\"$DIR/sad-assinador.sh\"
Path=$DIR
Icon=$icon
Terminal=false
Categories=Office;Java;
Keywords=assinador;digital;detran;certificado;a3;token;etoken;pdf;icp-brasil;
StartupNotify=true
StartupWMClass=br.gov.go.detran.sad.MainApp"
  mkdir -p "$APPS_DIR"
  for target in "$APPS_DIR/sad-assinador.desktop" "$DESKTOP_DIR/sad-assinador.desktop"; do
    mkdir -p "$(dirname "$target")"
    if [ ! -f "$target" ] || [ "$(cat "$target" 2>/dev/null)" != "$entry" ]; then
      printf '%s\n' "$entry" > "$target"
      chmod +x "$target"
      changed=1
    fi
  done
  if [ "$changed" = 1 ]; then
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    command -v gio >/dev/null 2>&1 && gio set "$DESKTOP_DIR/sad-assinador.desktop" metadata::trusted true >/dev/null 2>&1 || true
  fi
}

# ── Menu único (quando aberto pelo terminal) ───────────────────────────────
# Sem argumentos e num terminal: mostra o menu e deixa escolher o que fazer.
# Pelo ícone (sem terminal) ou com flags, segue direto sem menu.
if [ "$MODE" = "run" ] && [ "$SAD_TTY" = 1 ] && [ "${SAD_NAO_MENU:-0}" != "1" ]; then
  MENU_SAD="$(choose_sad_dir)"
  if [ -n "$MENU_SAD" ]; then
    MENU_VER="$(grep -oP '^version\s*=\s*\K\S+' "$MENU_SAD/config.properties" 2>/dev/null || echo '?')"
    MENU_ESTADO="Instalado: versão $MENU_VER"
  else
    MENU_ESTADO="Ainda não instalado"
  fi
  shopt -s nullglob
  MENU_EXES=("$DIR"/SAD-Assinadorv*.exe)
  shopt -u nullglob
  if [ "${#MENU_EXES[@]}" -gt 0 ]; then
    MENU_EXE="Executável na pasta: $(basename "${MENU_EXES[${#MENU_EXES[@]}-1]}")"
  else
    MENU_EXE="Nenhum .exe na pasta (baixe no site do Detran-GO)"
  fi

  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  SAD Assinador — Linux"
  echo "  $MENU_ESTADO"
  echo "  $MENU_EXE"
  echo "═══════════════════════════════════════════════"
  echo ""
  echo "  1) Instalar / atualizar o .exe desta pasta"
  echo "  2) Abrir o SAD"
  echo "  3) Diagnóstico do ambiente"
  echo "  4) Apagar a senha do token salva"
  echo "  5) Remover os atalhos"
  echo "  6) Sair"
  echo ""
  if [ -n "$MENU_SAD" ]; then MENU_PADRAO=2; else MENU_PADRAO=1; fi
  read -r -p "Escolha [$MENU_PADRAO]: " MENU_OPT || MENU_OPT=""
  MENU_OPT="${MENU_OPT:-$MENU_PADRAO}"
  case "$MENU_OPT" in
    1) MODE="install" ;;
    2) MODE="run" ;;
    3) MODE="diag" ;;
    4) MODE="reset-pin" ;;
    5) MODE="uninstall" ;;
    6) exit 0 ;;
    *) echo "Opção inválida: $MENU_OPT"; exit 2 ;;
  esac
  echo ""
fi

# ── 9. Modos especiais ──────────────────────────────────────────────────────
if [ "$MODE" = "uninstall" ]; then
  rm -f "$APPS_DIR/sad-assinador.desktop" "$DESKTOP_DIR/sad-assinador.desktop"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
  log "Atalhos removidos."
  log "Para apagar tudo, remova esta pasta, ~/.config/assinador e ~/.local/state/sad-assinador."
  exit 0
fi

if [ "$MODE" = "reset-pin" ]; then
  rm -f "$TOKEN_PIN_FILE"
  log "Senha salva apagada. A próxima abertura vai pedir a senha do token."
  exit 0
fi

JAVA_BIN="$(find_java)"

if [ "$MODE" = "run" ] || [ "$MODE" = "install" ]; then
  log "Iniciando SAD Assinador..."
  ensure_pcscd
  auto_extract_pending
fi

PKCS11_DRIVER="$(detect_driver || true)"
[ -n "$PKCS11_DRIVER" ] || warn "Nenhum driver PKCS#11 encontrado — instale o driver do seu token."

SAD_DIR="$(choose_sad_dir)"
if [ -z "$SAD_DIR" ]; then
  if [ "$MODE" = "check" ]; then
    warn "Nenhuma versão do SAD extraída (nenhum SAD-Assinadorv* válido)."
    exit 1
  fi
  die "Nenhuma versão do SAD encontrada. Coloque o SAD-AssinadorvX.Y.Z.exe nesta pasta e abra de novo."
fi

DETECTED_VERSION="$(grep -oP '^version\s*=\s*\K\S+' "$SAD_DIR/config.properties" 2>/dev/null \
  || basename "$SAD_DIR" | sed 's/^SAD-Assinadorv//')"

if [ "$MODE" = "diag" ]; then
  echo "──────────────────────────────────────────────"
  echo " SAD Assinador — diagnóstico"
  echo "──────────────────────────────────────────────"
  echo " Pasta do projeto : $DIR"
  echo " Versão do SAD    : $DETECTED_VERSION"
  echo " Pasta do SAD     : $SAD_DIR"
  echo " Java             : ${JAVA_BIN:-NÃO ENCONTRADO}"
  echo " Driver PKCS#11   : ${PKCS11_DRIVER:-NÃO ENCONTRADO}"
  echo " Token conectado  : $(token_present >/dev/null 2>&1 && echo sim || echo não)"
  echo " Senha salva      : $([ -f "$TOKEN_PIN_FILE" ] && (read_saved_pin >/dev/null 2>&1 && echo 'sim (descriptografa OK)' || echo 'arquivo existe, mas não descriptografa') || echo não)"
  echo " Config           : $CONFIG_FILE"
  echo " Log              : $LOG_FILE"
  echo " Patches          : $(ls "$BUILD_DIR"/br/gov/go/detran/sad/SadPreMain.class >/dev/null 2>&1 && echo ok || echo faltando)"
  echo "──────────────────────────────────────────────"
  exit 0
fi

if [ -z "$JAVA_BIN" ]; then
  gui_error "Java não encontrado. Instale o Zulu 8 FX em ~/java/."
  die "JDK 8 com JavaFX não encontrado (esperado em ~/java/zulu*fx*)."
fi

# ── 10. Compila os patches se necessário ────────────────────────────────────
need_build=0
[ -f "$BUILD_DIR/br/gov/go/detran/sad/SadPreMain.class" ] || need_build=1
[ -f "$BUILD_DIR/br/gov/go/detran/sad/WrapperKeyStoreSpi.class" ] || need_build=1
[ -f "$BUILD_DIR/br/gov/go/detran/sad/controller/VerificaSO.class" ] || need_build=1
if [ -f "$BUILD_DIR/.build-version" ]; then
  [ "$(cat "$BUILD_DIR/.build-version" 2>/dev/null)" = "$DETECTED_VERSION" ] || need_build=1
else
  need_build=1
fi
if [ "$need_build" = 0 ]; then
  if find "$DIR/src" -name '*.java' -newer "$BUILD_DIR/.build-version" | grep -q .; then
    need_build=1
  fi
fi

if [ "$need_build" = 1 ]; then
  [ "$MODE" = "check" ] && { warn "Patches não compilados para a versão $DETECTED_VERSION."; exit 1; }
  log "Compilando patches para a versão $DETECTED_VERSION..."
  gui_progress "Preparando a versão $DETECTED_VERSION..." bash "$DIR/build.sh" "$SAD_DIR" \
    || { gui_error "Falha ao compilar os patches. Veja o log: $LOG_FILE"; die "build.sh falhou"; }
fi

# ── 11. Senha do token ──────────────────────────────────────────────────────
PIN=""
if [ -n "${SAD_TOKEN_PIN:-}" ]; then
  PIN="$SAD_TOKEN_PIN"
  log "Usando senha do token vinda do ambiente (SAD_TOKEN_PIN)."
elif PIN="$(read_saved_pin 2>/dev/null)"; then
  log "Senha do token carregada (já salva)."
else
  PIN=""
  if [ -f "$TOKEN_PIN_FILE" ]; then
    warn "Não consegui decriptar a senha salva — vou pedir de novo."
  fi
  if { [ "$MODE" = "run" ] || [ "$MODE" = "install" ]; } \
     && [ -n "$PKCS11_DRIVER" ] && token_present >/dev/null 2>&1; then
    if PIN="$(ask_pin 2>/dev/null)"; then
      save_pin "$PIN" && log "Senha salva criptografada em $TOKEN_PIN_FILE."
    else
      warn "Sem senha do token — o certificado pode não aparecer."
    fi
  fi
fi
export SAD_TOKEN_PIN="$PIN"

# ── 12. Primeira execução: pergunta se quer atalho ──────────────────────────
WIZARD_MARKER="$STATE_DIR/.wizard-done"
if { [ "$MODE" = "run" ] || [ "$MODE" = "install" ]; } \
   && [ "$SHORTCUT_MODE" = "auto" ] && [ ! -f "$WIZARD_MARKER" ] \
   && [ "${SAD_NAO_PERGUNTAR:-0}" != "1" ]; then
  escolha=""
  if [ -t 0 ]; then
    # Rodando no terminal: menu completo, tudo visível de uma vez.
    echo ""
    echo "Como você quer usar o SAD Assinador?"
    echo "  1) Criar atalho e abrir agora (recomendado)"
    echo "  2) Só abrir agora"
    echo "  3) Só preparar (criar atalho, sem abrir)"
    read -r -p "Escolha [1]: " resp || resp="1"
    case "${resp:-1}" in
      2) escolha="Só abrir agora" ;;
      3) escolha="Só preparar (criar atalho, sem abrir)" ;;
      *) escolha="Criar atalho e abrir agora (recomendado)" ;;
    esac
  elif [ "$HAS_GUI" = 1 ]; then
    escolha="$(zenity --list --radiolist --title="SAD Assinador" --width=500 --height=380 \
      --text="Como você quer usar o SAD Assinador?" \
      --column="" --column="Opção" \
      TRUE  "Criar atalho e abrir agora (recomendado)" \
      FALSE "Só abrir agora" \
      FALSE "Só preparar (criar atalho, sem abrir)" 2>/dev/null || true)"
  fi

  case "$escolha" in
    *"Só preparar"*)  SHORTCUT_MODE="yes"; MODE="install" ;;
    "Só abrir agora") SHORTCUT_MODE="no";  MODE="run" ;;
    *"Criar atalho"*) SHORTCUT_MODE="yes"; MODE="run" ;;
    *) : ;;  # cancelou: mantém o padrão
  esac
  touch "$WIZARD_MARKER" 2>/dev/null || true
fi

should_install_shortcut() {
  case "$SHORTCUT_MODE" in
    yes)      return 0 ;;
    no)       return 1 ;;
    existing) [ -f "$APPS_DIR/sad-assinador.desktop" ] ;;
    *)        [ -f "$APPS_DIR/sad-assinador.desktop" ] ;;
  esac
}

# ── 13. Config, driver e atalhos ────────────────────────────────────────────
ensure_config "$PKCS11_DRIVER"

export SAD_PKCS11_DRIVER="$PKCS11_DRIVER"
export SAD_CONFIG_DIR="$CONFIG_DIR"

JAVA_PKCS11_OPTS=()
if [ -n "$PKCS11_DRIVER" ]; then
  cat > "$CONFIG_DIR/pkcs11.cfg" <<EOF
name = SADToken
library = $PKCS11_DRIVER
EOF
  chmod 600 "$CONFIG_DIR/pkcs11.cfg" 2>/dev/null || true
  export PKCS11_CONFIG_FILE="$CONFIG_DIR/pkcs11.cfg"
  JAVA_PKCS11_OPTS+=("-Dsun.security.pkcs11.cfg=$CONFIG_DIR/pkcs11.cfg")
fi

if should_install_shortcut; then
  install_shortcuts "$SAD_DIR" "$DETECTED_VERSION"
  log "Atalho pronto: menu de aplicativos e Área de Trabalho."
else
  log "Atalho não criado (use --atalho quando quiser criar)."
fi

if [ "$MODE" = "check" ]; then
  log "OK: ambiente pronto (versão $DETECTED_VERSION)."
  exit 0
fi

if [ "$MODE" = "install" ]; then
  log "Tudo preparado. Para abrir: $DIR/sad-assinador.sh (opção 2) ou pelo atalho."
  [ "$HAS_GUI" = 1 ] && zenity --info --timeout=5 --title="SAD Assinador" --width=380 \
    --text="Tudo pronto para a versão $DETECTED_VERSION.\n\nAbra pelo atalho \"SAD Assinador\"." >/dev/null 2>&1 || true
  exit 0
fi

# ── 14. Executa ─────────────────────────────────────────────────────────────
log "Abrindo SAD $DETECTED_VERSION..."
cd "$SAD_DIR"

JAVA_CMD=("$JAVA_BIN")
if [ "${#JAVA_PKCS11_OPTS[@]}" -gt 0 ]; then
  JAVA_CMD+=("${JAVA_PKCS11_OPTS[@]}")
fi
JAVA_CMD+=(-cp "$BUILD_DIR:.:jdtCompilerAdapter.jar" br.gov.go.detran.sad.SadPreMain "${PKCS11_DRIVER:--}")
if [ "${#APP_ARGS[@]}" -gt 0 ]; then
  JAVA_CMD+=("${APP_ARGS[@]}")
fi
exec "${JAVA_CMD[@]}"
