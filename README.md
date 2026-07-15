# Guia SAD Assinador no Linux (token eToken)

Este repositório contém as **correções necessárias para rodar o SAD Assinador
(Detran-GO) no Linux com certificado em token USB SafeNet eToken 5100/5110**,
além de scripts de instalação e um launcher reproduzível.

> ⚠️ **Este repositório NÃO redistribui o programa do Detran.** Ele contém apenas
> as correções (código-fonte Java) e os scripts. Você precisa do instalador oficial
> do SAD Assinador (`.exe`) extraído, ou da pasta já descompactada.

## Por que isto existe

O SAD Assinador foi feito para Windows. No Linux, o fluxo de token USB quebra em
dois pontos do código compilado, que foram contornados aqui:

1. **`CertificadoA3RepositoryImpl`** — criava o `KeyStore.Builder` do PKCS#11 com um
   `CallbackHandler` **nulo**, o que lança `NullPointerException` no Java 8/Linux.
   Corrigido para fornecer o PIN ao token via `CallbackHandler` próprio.
2. **`TrustAllCertificates`** — configurava o SSL com `KeyManager = null`, então a
   conexão com o servidor de autenticação (**mTLS**) não enviava o certificado do
   token. Corrigido para usar o `KeyStore` do token como `KeyManager`.

Além disso, o Demoiselle Signer precisa do eToken registrado como **primeiro driver**
em `~/.signer/drivers.properties`.

## Pré-requisitos

- Linux (testado no Zorin OS 18 / Ubuntu 24.04).
- Token USB **SafeNet eToken 5100/5110** conectado.
- **SafeNet Authentication Client (SAC) para Linux** instalado (proprietário, portal
  Thales). Ele fornece `/usr/lib/libeToken.so`. Sem ele, o Java não enxerga o token.
- `pcscd` ativo (`systemctl status pcscd`).
- O programa SAD Assinador v1.2.0 extraído em uma pasta.

## Instalação rápida (recomendada)

```bash
# 1. Extraia o SAD Assinador (do .exe oficial) em alguma pasta, ex.:
#    ~/Downloads/SAD Assinador/SAD-Assinadorv1.2.0

# 2. Rode o instalador deste repositório:
git clone https://github.com/arthurrogado/guia-sad-linux.git
cd guia-sad-linux
./scripts/instalar.sh "/home/arthur/Downloads/SAD Assinador/SAD-Assinadorv1.2.0"
```

O `instalar.sh` vai: baixar o JDK 8 + JavaFX (Zulu FX) para `~/java`, copiar o SAD
para `~/Apps/SAD`, aplicar o patch de correções e criar um atalho no menu de
aplicativos.

## Uso manual (sem o instalador)

```bash
# Aplicar só as correções numa pasta do SAD já existente:
./patches/patch.sh /caminho/para/SAD-Assinadorv1.2.0

# Rodar:
./scripts/sad-assinador.sh   # (dentro da pasta do SAD)
```

## Configurando o certificado (primeiro uso)

1. Abra o SAD (menu de aplicativos ou `sad-assinador.sh`).
2. Na tela de login, clique no **ícone de engrenagem** (canto superior).
3. Vá em **Configurar Certificado → Certificado A3**.
4. Campo **Módulo**: `/usr/lib/libeToken.so`
5. Campo **Senha**: seu **PIN do token**.
6. Clique em **Salvar**.
7. Volte e faça o **login** normalmente.

## Estrutura do repositório

```
guia-sad-linux/
├── patches/
│   ├── patch.sh                      # recompila e injeta os .class corrigidos
│   ├── CertificadoA3RepositoryImpl.java   # correção 1 (CallbackHandler do token)
│   └── TrustAllCertificates.java          # correção 2 (KeyManager / mTLS)
├── scripts/
│   ├── instalar.sh                   # instalação completa (JDK + patch + .desktop)
│   └── sad-assinador.sh              # launcher que detecta o JDK automaticamente
├── .gitignore
└── README.md
```

## Notas de segurança

- Nenhum dado pessoal (PIN, certificados, tokens de API) é versionado.
- O `config.properties` original do Detran **não** é tocado por estes scripts.
- O SAC (SafeNet) é software proprietário e deve ser obtido no portal oficial Thales.

## Licença

As correções aqui são disponibilizadas para fins de compatibilidade no Linux.
O programa SAD Assinador pertence ao Detran-GO; respeite os termos de uso dele.
