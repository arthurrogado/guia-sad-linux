# Changelog

## [1.4.1-linux] — 2026-11-19

Preparado para o SAD Assinador **1.4.1 (DCXE)** e reorganizado para ser
fácil de distribuir e usar.

### Adicionado
- **Instalação em um passo**: `./sad-assinador.sh` acha o `.exe` mais
  novo da pasta, extrai, detecta o driver, compila os patches, configura
  o token e abre. Não precisa rodar `extract-sad.sh` antes.
- **Extração automática** de qualquer `SAD-AssinadorvX.Y.Z.exe` que ainda
  não tenha sido extraído.
- **Pergunta na primeira execução** se o usuário quer criar atalho no
  menu de aplicativos / Área de Trabalho, só abrir, ou apenas preparar
  (`--atalho`, `--sem-atalho`, `--nao-abrir`).
- **`--diag`**: diagnóstico do Java, driver, token, senha salva e patches.
- **`--desinstalar`**: remove os atalhos criados.
- **Log persistente** em `~/.local/state/sad-assinador/launcher.log`
  (essencial quando aberto pelo ícone, sem terminal).
- **`src/`**: código Java dos patches saiu de `lib/` para `src/`; a
  compilação vai para `build/classes/`.
- **README** reescrito com instalação, atualização e solução de problemas.
- **LICENSE (MIT)** e **.gitignore** para publicar o repositório sem
  versionar o executável do Detran nem as pastas extraídas.

### Corrigido
- **`WrapperKeyStoreSpi.java` ausente**: o build falhava/quebrava sem
  essa classe. Reescrita em `src/br/gov/go/detran/sad/`.
- **`config.json` com JSON inválido** (vírgula sobrando em
  `customDriverPaths`), gerado pelas versões antigas do launcher.
- **Duplicação de `cat > .desktop`** no `extract-sad.sh`, que escrevia
  uma linha inválida dentro do atalho.
- **`extract-sad.sh` chamava `--check`**, que não existia e acabava
  abrindo o SAD no meio da extração.
- **Caminho errado do `MainApp.class`** na checagem de extração.

### Compatibilidade
- Funciona com 1.2.0, 1.3.0 e 1.4.1; usa sempre a versão mais nova
  extraída (ou `SAD_VERSION=X.Y.Z`).
- O launcher do SAD 1.4.1 (`SadBootstrap`) detecta JavaFX e abre o
  `MainApp` normalmente; o fluxo patcheado continua igual.

## [1.3.0-linux] — 2026-10-16

Versão inicial do launcher Linux para o SAD Assinador.

### Adicionado
- **`sad-assinador.sh`**: launcher principal que detecta driver PKCS#11,
  inicia `pcscd`, pede senha do token via GUI (zenity/kdialog/whiptail),
  criptografa com GPG, e inicia o SAD via `SadPreMain`.
- **`extract-sad.sh`**: extrator de versões `.exe` usando `7z`.
- **`build.sh`**: compila os 3 patches Java (`SadPreMain`,
  `WrapperKeyStoreSpi`, `VerificaSO`).
- **`lib/SadPreMain.java`**: hook de pré-inicialização que cria uma
  KeyStore PKCS#11 autenticada com a senha do token e injeta no
  `EtapasUtil.certificadoDigital` via reflection.
- **`lib/WrapperKeyStoreSpi.java`**: subclasse de `KeyStoreSpi` que
  captura `KeyStoreException` e retorna valores neutros.
- **`lib/br/gov/go/detran/sad/controller/VerificaSO.java`**: patch do
  `VerificaSO` original que não mostra "Configure o certificado" no
  Linux.
- **Autenticação automática do token**: a senha é pedida UMA vez via
  GUI e salva criptografada em `~/.config/assinador/token.pin.gpg`.
- **Cache da senha em classpath**: o `.sh` seta `SAD_TOKEN_PIN` antes
  de chamar o Java, que o `SadPreMain` lê para autenticar o PKCS11.
- **Geração de atalho `.desktop`** em `~/.local/share/applications/`
  com nome amigável "SAD Assinador".
- **Documentação completa** em `docs/` (architecture, internals,
  installation, troubleshooting).

### Bugs do SAD contornados
1. **"Configure o certificado para utilizar o Assinador"** no Linux:
   patch em `VerificaSO.class` faz o caminho Unix seguir direto para
   `SelecionarCertificadoController`.
2. **`KeyStoreException: Uninitialized keystore`**: `WrapperKeyStoreSpi`
   captura a exceção em `engineAliases()` etc. + `SadPreMain` força
   `initialized = true` no campo do `KeyStore` via reflection.
3. **Necessidade de entrar na engrenagem toda vez**: `SadPreMain` chama
   `ks.load(null, pin)` automaticamente quando há senha salva, então o
   PKCS11 autentica e os aliases aparecem direto na tela de seleção.
4. **`Exec` sem aspas no `.desktop`** (descoberto depois): o GNOME só
   reconhece o atalho se o `Exec` estiver entre aspas duplas quando o
   caminho tem espaços (ex.: `/home/arthur/Dev/SAD Assinador/...`).
   Sem aspas, `gio launch` retorna "Não foi possível carregar
   informações de aplicativo" e o atalho não aparece no menu de apps.

### Notas
- O atalho `.desktop` é registrado automaticamente via
  `update-desktop-database` em cada execução do `extract-sad.sh`.
- A senha do token é criptografada com `gpg --symmetric --cipher-algo
  AES256` e chave derivada de `whoami@$(cat /etc/machine-id)`. Apenas
  o usuário dono da máquina consegue decriptar.
- O `Exec` no `.desktop` precisa de aspas duplas no caminho. O
  `extract-sad.sh` agora gera com aspas automaticamente.