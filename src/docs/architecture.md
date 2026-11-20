# Arquitetura

Este documento explica como o launcher do SAD funciona internamente, do
launcher `.sh` até os patches em bytecode.

## Visão geral

O SAD Assinador foi feito para Windows. No Linux, ele não funciona por
causa de bugs de design — não porque o PKCS#11 não funciona (funciona!),
mas porque o código Java do SAD assume comportamentos específicos do
Windows.

Este launcher contorna esses bugs com **3 camadas**:

```
┌────────────────────────────────────────────────────────────────────┐
│ 1. sad-assinador.sh (bash)                                         │
│    - Detecta driver PKCS#11                                         │
│    - Inicia pcscd se necessário                                    │
│    - Pede senha do token (1ª vez) via GUI                          │
│    - Salva senha criptografada com GPG                             │
│    - Configura PKCS11_CONFIG_FILE, PKCS11_DRIVER                   │
│    - Exporta SAD_TOKEN_PIN                                         │
└────────────────────────────────────────────────────────────────────┘
                                 ↓
┌────────────────────────────────────────────────────────────────────┐
│ 2. SadPreMain.class (Java) — patch #1                              │
│    - Carrega token PIN                                            │
│    - Cria KeyStore PKCS#11 via SunPKCS11                          │
│    - Autentica com load(null, pin)                                │
│    - Envolve em WrapperKeyStoreSpi                                │
│    - Injeta no EtapasUtil.certificadoDigital via reflection       │
│    - Chama MainApp.main()                                         │
└────────────────────────────────────────────────────────────────────┘
                                 ↓
┌────────────────────────────────────────────────────────────────────┐
│ 3. WrapperKeyStoreSpi.class (Java) — patch #2                     │
│    - Estende KeyStoreSpi                                          │
│    - Captura KeyStoreException em todos os métodos               │
│    - Retorna valores neutros (aliases vazio, size=0, etc)        │
└────────────────────────────────────────────────────────────────────┘
                                 ↓
┌────────────────────────────────────────────────────────────────────┐
│ 4. VerificaSO.class (Java) — patch #3                             │
│    - Versão reescrita do VerificaSO do SAD                         │
│    - Não mostra "Configure o certificado" no Linux                │
│    - Segue direto para SelecionarCertificadoController            │
└────────────────────────────────────────────────────────────────────┘
                                 ↓
                          MainApp.original
```

## Ordem de execução

1. **Usuário clica no ícone** (ou roda `./sad-assinador.sh`)
2. **`sad-assinador.sh`** roda:
   - Detecta `libeToken.so` (ou similar)
   - Inicia `pcscd` se necessário
   - Procura `~/.config/assinador/token.pin.gpg`:
     - Se **existe** → decripta com `gpg` (passphrase = `whoami@machine-id`)
     - Se **não existe** → abre `zenity`/`kdialog`/`whiptail` pedindo senha
       - Salva criptografada com `gpg --symmetric --cipher-algo AES256`
   - Cria `pkcs11.cfg` em `~/.config/assinador/`
   - `exec java ... SadPreMain SADToken::<driver>`
3. **`SadPreMain`**:
   - Cria `SunPKCS11` provider com cfg `name = SADToken\nlibrary = <driver>`
   - `Security.addProvider(provider)`
   - `KeyStore.getInstance("PKCS11", provider)` — **vazio** (uninitialized)
   - Lê `SAD_TOKEN_PIN` do env (vinda do `.sh`)
   - `ks.load(null, pin.toCharArray())` — **autentica o PKCS11**
   - Agora `ks.aliases()` retorna os certificados do token!
   - Envolve a KeyStore em `WrapperKeyStoreSpi` (em outro arquivo)
   - Seta `initialized = true` via reflection
   - `EtapasUtil.setCertificadoDigital(newBean)` via reflection
   - Chama `MainApp.main()`
4. **`MainApp`**:
   - Splash screen → Login view → usuário clica "Login / Certificado Digital"
5. **`LoginViewController.verificaSO()`**:
   - Se `versaoAtualizada()` retornar true → chama `VerificaSO.verificaSistemaOperacional()`
6. **`VerificaSO`** (nosso patch):
   - `getCertificadoDigital().getKeyStore()` — não é null! ✓
   - `SistemaOperacional.isUnix()` → true
   - `keyStoreVazio` → false
   - **NÃO mostra "Configure o certificado"** ✓
   - Prossegue para `SelecionarCertificadoController.initTela()`
7. **`SelecionarCertificadoController.criaKeyStore()`**:
   - `getCertificadoDigital().getKeyStore()` → nosso wrapper
   - `wrapper.aliases()` → captura exceção → Enumeration vazia
   - Mas como o PKCS11 está autenticado, retorna os aliases reais!
   - Lista aparece com o alias do certificado, no formato
     **"NOME COMPLETO:CPF"**
8. **Usuário clica no item da lista** → fluxo normal de login

## Por que patches separados em 3 arquivos?

Porque cada um resolve um problema específico:

| Patch | Resolve | Onde fica |
|-------|---------|-----------|
| `VerificaSO` | Mensagem "Configure o certificado" no Linux | `src/br/gov/go/detran/sad/controller/` |
| `WrapperKeyStoreSpi` | Crash em `aliases()` quando KeyStore não-inicializada | `src/br/gov/go/detran/sad/` |
| `SadPreMain` | Pré-configura tudo automaticamente | `src/br/gov/go/detran/sad/` |

Cada um é gerado pelo `build.sh` (que compila os 3 `.java` contra o
classpath da versão do SAD).

## Classpath e precedência

```
java -cp ~/sad-assinador/build/classes:.:jdtCompilerAdapter.jar SadPreMain
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^                  ^^^^^^^^^^^
                 nossas classes (PRIMEIRO!)                    classes do SAD
```

Como o `build/classes/` vem **antes** do `.` (SAD) no classpath, o classloader
Java carrega nossas classes primeiro. Quando o SAD referencia
`br.gov.go.detran.sad.controller.VerificaSO`, encontra a nossa versão.

Se a nossa classe lançar exceção ao carregar (e.g., método com
assinatura diferente), o classloader faz fallback para a versão do SAD.
Por isso nossos patches são **idênticos em API** ao original — só
mudam a lógica interna.

## Segurança

### Senha do token

```
~/.config/assinador/token.pin.gpg
├── Algoritmo: AES256
├── Modo: GPG symmetric (-c)
├── Passphrase: whoami@$(cat /etc/machine-id)
└── Permissões: 600 (só seu usuário)
```

A passphrase é única por máquina + usuário. Mesmo que outro usuário
do sistema consiga ler o arquivo, ele não consegue decriptar.

### Variável de ambiente

```
SAD_TOKEN_PIN='123456' java SadPreMain
```

Aparece em `ps aux` por alguns milissegs (até o `exec` no shell substituir
o processo), mas o risco é mínimo porque:
- O `.sh` seta a env var e faz `exec` na mesma linha
- O processo pai (bash) morre imediatamente após o `exec`
- Outros usuários precisam ser root para ver `ps` de outros processos

## Dependências externas

- **JDK 8 com JavaFX**: `~/java/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64/bin/java`
- **Driver PKCS#11**: `/usr/lib/libeToken.so` (instalado pelo `sudo apt install libpam-pkcs11`)
- **pcscd**: daemon de smart card (`sudo apt install pcscd`)
- **7z**: extrai o `.exe` do SAD (`sudo apt install p7zip-full`)
- **GPG**: criptografa a senha do token (`sudo apt install gnupg`)
- **zenity/kdialog/whiptail**: GUI popup para pedir a senha na 1ª vez
  (`sudo apt install zenity` ou `dialog`)