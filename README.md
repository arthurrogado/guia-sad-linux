# SAD Assinador para Linux

Launcher que faz o **SAD Assinador (Detran-GO)** — oficialmente só para
Windows — rodar no Linux **com o token A3 já autenticado**.

O resultado é simples: você clica no ícone e a tela de **Consulta de
Documentos** abre direto, com o certificado do token logado. Sem entrar na
engrenagem, sem configurar o A3 na mão, sem digitar a senha toda vez.

> Este repositório **não distribui** o executável do SAD. Ele apenas
> adapta a versão oficial (Windows) para rodar no Linux. Baixe o `.exe` no
> site do Detran-GO:
> <https://goias.gov.br/detran/sad-assinador-digital/>

---

## Requisitos

| Item | Como instalar |
|------|----------------|
| Java 8 com JavaFX (Zulu 8 FX) | veja abaixo |
| Driver do token A3 | `libeToken.so` (SafeNet/eToken) já vem com o driver do fabricante |
| `pcscd` | `sudo apt install pcscd` |
| `7z`, `gpg`, `zenity` | `sudo apt install p7zip-full gnupg zenity` |

### Java 8 FX (uma vez só)

```bash
mkdir -p ~/java && cd ~/java
wget https://cdn.azul.com/zulu/bin/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64.tar.gz
tar -xzf zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64.tar.gz
```

O launcher procura o Java sozinho em `~/java/zulu*fx*/bin/java`.

---

## Instalação (3 passos)

```bash
# 1. clone
git clone https://github.com/arthurrogado/guia-sad-linux.git sad-assinador
cd sad-assinador

# 2. baixe o SAD no site do Detran-GO e coloque o .exe nesta pasta
#    (ex.: SAD-Assinadorv1.4.1.exe)

# 3. rode
./sad-assinador.sh
```

Na primeira execução o script:

1. encontra o `.exe` mais novo da pasta e extrai sozinho;
2. detecta o driver PKCS#11 e o token conectado;
3. compila os ajustes Java contra aquela versão;
4. pergunta se você quer criar o atalho no menu de aplicativos / Área de
   Trabalho;
5. pede a **senha do token uma única vez** e salva criptografada em
   `~/.config/assinador/token.pin.gpg`;
6. abre o SAD já logado.

Depois disso, é só clicar no ícone **SAD Assinador**.

### Se preferir instalar sem abrir

```bash
./sad-assinador.sh --nao-abrir          # prepara tudo e sai
./sad-assinador.sh --atalho             # cria atalho e abre
./sad-assinador.sh --sem-atalho         # abre sem criar atalho
```

---

## Atualizar para uma versão nova

Baixe o `.exe` novo, coloque na pasta e rode:

```bash
./extract-sad.sh                       # pega o .exe mais novo da pasta
# ou
./extract-sad.sh SAD-Assinadorv1.5.0.exe
```

Ele extrai, recompila os ajustes e atualiza o atalho. Versões antigas
continuam na pasta; o launcher sempre usa a mais nova.

---

## Comandos

| Comando | O que faz |
|---------|-----------|
| `./sad-assinador.sh` | Abre o SAD (faz a instalação na primeira vez) |
| `./sad-assinador.sh --nao-abrir` | Prepara tudo sem abrir |
| `./sad-assinador.sh --atalho` | Cria/atualiza o atalho e abre |
| `./sad-assinador.sh --sem-atalho` | Abre sem mexer em atalhos |
| `./sad-assinador.sh --check` | Só valida o ambiente |
| `./sad-assinador.sh --diag` | Diagnóstico completo |
| `./sad-assinador.sh --reset-pin` | Apaga a senha salva (pede de novo) |
| `./sad-assinador.sh --desinstalar` | Remove os atalhos |
| `./extract-sad.sh [arquivo.exe]` | Extrai/atualiza uma versão |
| `SAD_VERSION=1.3.0 ./sad-assinador.sh` | Força uma versão específica |

Log de execução: `~/.local/state/sad-assinador/launcher.log`

---

## Problemas comuns

| Sintoma | Solução |
|---------|---------|
| "Nenhum driver PKCS#11 encontrado" | Instale o driver do seu token (SafeNet/eToken) e reconecte o USB |
| Certificado não aparece | `./sad-assinador.sh --reset-pin` e digite a senha de novo |
| Token não reconhecido | `sudo systemctl restart pcscd` e confira com `pcsc_scan` |
| Não abre pelo ícone | Rode `./sad-assinador.sh` no terminal e veja o log |
| Erro de compilação | Confira se o Zulu 8 FX está em `~/java/` (`./sad-assinador.sh --diag`) |

Mais detalhes em [docs/troubleshooting.md](docs/troubleshooting.md).

---

## Como funciona (resumo)

O SAD foi feito para Windows e tem três comportamentos que quebram no
Linux. O launcher contorna os três:

1. **"Configure o certificado para utilizar o Assinador"** — o
   `VerificaSO` original mostra esse erro quando `isUnix()` é verdadeiro.
   Um `VerificaSO` reescrito segue direto para a seleção de certificado.
2. **`Uninitialized keystore`** — a `KeyStore` PKCS#11 precisa de `load()`
   com o PIN antes de listar aliases. O `WrapperKeyStoreSpi` tolera o erro
   e o `SadPreMain` autentica com o PIN salvo.
3. **Engrenagem toda vez** — a senha do token é salva criptografada (GPG
   AES256, chave derivada de `usuário@machine-id`) e reutilizada.

Fontes dos ajustes em [`src/`](src/). Detalhes técnicos em
[docs/architecture.md](docs/architecture.md) e
[docs/internals.md](docs/internals.md).

---

## Estrutura

```
.
├── sad-assinador.sh      # ponto de entrada: instala e abre
├── extract-sad.sh        # extrai/atualiza uma versão do .exe
├── build.sh              # compila os ajustes Java
├── src/                  # código Java dos ajustes
│   ├── SadPreMain.java
│   └── br/gov/go/detran/sad/
│       ├── WrapperKeyStoreSpi.java
│       └── controller/VerificaSO.java
├── docs/                 # documentação técnica
└── SAD-AssinadorvX.Y.Z/  # gerado na instalação (não versionado)
```

---

## Projeto anterior (A1/.pfx e patches manuais)

A versão antiga deste guia (patching manual de `CertificadoA3RepositoryImpl`,
`TrustAllCertificates` e `OIDGeneric`, com configuração do certificado pela
engrenagem) está preservada em [`legacy/`](legacy/) e no histórico do git.
O launcher atual não usa esses patches; ele já autentica o A3 sozinho.

## Aviso

Projeto não oficial, sem vínculo com o Detran-GO. O SAD Assinador é
propriedade do Detran-GO; use sempre a versão baixada no site oficial.
