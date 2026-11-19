# Guia detalhado de instalação

Este guia cobre a instalação completa do zero, incluindo dependências
e configuração.

## Pré-requisitos

### Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y \
    pcscd \
    libpam-pkcs11 \
    p7zip-full \
    gnupg \
    zenity \
    openjdk-8-jdk \
    openjfx
```

> **Importante**: openjdk-8-jdk não tem JavaFX. Para JavaFX use
> **Zulu 8 FX** (recomendado) — instruções abaixo.

### Fedora

```bash
sudo dnf install -y \
    pcscd \
    opensc \
    p7zip p7zip-plugins \
    gnupg2 \
    zenity \
    java-1.8.0-openjdk-devel \
    java-1.8.0-openjdk-openjfx
```

### Arch Linux

```bash
sudo pacman -S \
    pcsclite \
    ccid \
    opensc \
    p7zip \
    gnupg \
    zenity \
    jdk8-openjdk \
    java-openjfx
```

## 1. Instalar Zulu 8 FX (JDK com JavaFX)

O SAD precisa de Java 8 **com** JavaFX (porque é um app JavaFX). Zulu é
a melhor opção:

```bash
# Baixa Zulu 8 FX
cd ~/java
wget https://cdn.azul.com/zulu/bin/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64.tar.gz

# Extrai
tar -xzf zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64.tar.gz

# Verifica
~/java/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64/bin/java -version
```

## 2. Instalar driver do eToken

### Método 1: pacote oficial (recomendado)

```bash
# Baixa do site da Safenet/Thales
# Ou
sudo apt install libpam-pkcs11  # opensc geralmente vem junto
```

### Método 2: opensc genérico

```bash
sudo apt install opensc
```

Verifica que o driver existe:

```bash
ls -la /usr/lib/libeToken.so /usr/lib/libetoken.so /usr/lib/libaetpkss.so 2>&1
```

Se nenhum aparecer, faça download manual do driver do eToken do site
da Safenet.

## 3. Verifica que o pcscd funciona

```bash
sudo systemctl enable pcscd
sudo systemctl start pcscd

# Conecta o token e:
pcsc_scan -r
# Deve listar: "0: SafeNet eToken 5100 [...] 00 00"
```

## 4. Extrai o SAD Assinador

Coloca o `.exe` do SAD (ex.: `SAD-Assinadorv1.4.1.exe`) na pasta
do launcher e roda:

```bash
cd ~/sad-assinador/
./extract-sad.sh SAD-Assinadorv1.4.1.exe
```

Isso:
1. Extrai o `.exe` usando 7z (que descobre o ZIP embutido)
2. Detecta qual driver PKCS#11 você tem
3. Compila as classes `SadPreMain`, `WrapperKeyStoreSpi`, `VerificaSO`
4. Cria o atalho `.desktop` em `~/.local/share/applications/`

## 5. Roda

```bash
./sad-assinador.sh
```

Na primeira vez, vai aparecer um popup pedindo a senha do token.

Se o popup não aparecer (problema comum em alguns ambientes), use
uma variável de ambiente:

```bash
SAD_TOKEN_PIN='sua_senha_aqui' ./sad-assinador.sh
```

## 6. Adiciona atalho à área de trabalho (opcional)

```bash
# Cria link na área de trabalho
ln -s /home/arthur/.local/share/applications/sad-assinador.desktop \
      /home/arthur/Desktop/

# Torna executável
chmod +x /home/arthur/Desktop/sad-assinador.desktop
```

## Solução de problemas

### "Driver PKCS#11 não encontrado"

Verifica se o driver existe:

```bash
ls /usr/lib/libeToken.so /usr/lib/opensc-pkcs11.so 2>&1
```

Se não existe, instala o driver do eToken ou usa o `opensc`:

```bash
sudo apt install opensc
```

### "pcscd não encontrado"

```bash
sudo apt install pcscd
sudo systemctl enable --now pcscd
```

### "Token não detectado"

Confirma que o token está conectado:

```bash
lsusb | grep -i "safenet\|etoken\|gemalto"
pcsc_scan -r
```

### "Senha incorreta" / token bloqueia após várias tentativas

O eToken bloqueia após 3 tentativas erradas. Use o **eToken PKI Manager**
para desbloquear (Windows-only) ou use o `pkcs11-tool`:

```bash
sudo apt install opensc
pkcs11-tool --module /usr/lib/libeToken.so --login --test-pin
```

### Popup zenity não aparece

Pode acontecer se `$DISPLAY` não estiver setado. Força via env:

```bash
SAD_TOKEN_PIN='senha' ./sad-assinador.sh
```

Ou se quiser rodar em modo 100% terminal:

```bash
# Edita sad-assinador.sh e substitui "zenity" por "whiptail"
# Ou instala zenity: sudo apt install zenity
```

### SAD ainda pede para configurar

Confirma que os patches estão compilados:

```bash
cd ~/sad-assinador
./build.sh
```

Verifica se as classes estão lá:

```bash
ls -la build/classes/br/gov/go/detran/sad/SadPreMain.class \
       build/classes/br/gov/go/detran/sad/WrapperKeyStoreSpi.class \
       build/classes/br/gov/go/detran/sad/controller/VerificaSO.class
```

Se faltarem, o `build.sh` falhou. Rode manualmente:

```bash
cd src
~/java/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64/bin/javac \
    -cp "~/sad-assinador/SAD-Assinadorv1.4.1" \
    -d "~/sad-assinador/build/classes" \
    SadPreMain.java WrapperKeyStoreSpi.java \
    br/gov/go/detran/sad/controller/VerificaSO.java
```

### Erro "Demoiselle Signer não disponível"

Raro. Significa que o Demoiselle não está no classpath. Verifica:

```bash
ls SAD-Assinadorv1.4.1/org/demoiselle/signer/core/keystore/loader/Configuration.class
```

Se não existir, o `.eex` não extraiu corretamente. Re-extrai:

```bash
rm -rf SAD-Assinadorv1.4.1
./extract-sad.sh SAD-Assinadorv1.4.1.exe
```