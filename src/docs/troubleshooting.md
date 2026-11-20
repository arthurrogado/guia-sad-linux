# Solução de problemas

Problemas comuns e suas soluções.

## Problemas com o token

### "Não foi possível realizar a ação, por favor tente mais tarde."

**Causa**: A KeyStore foi pré-populada pelo SadPreMain, mas quando o SAD
tenta usar o certificado, alguma chamada falha (ex.: certificado
revogado, expirado, ou falha de rede).

**Soluções**:
1. Verifica se o token está desbloqueado (tente desbloquear via outro app)
2. Conecta o token, desconecta, reconecta
3. Verifica se o certificado está válido: `pcsc_scan -r`
4. Remove a senha salva: `rm ~/.config/assinador/token.pin.gpg`
   e roda o SAD de novo (vai pedir a senha)

### Token não detectado pelo `pcsc_scan`

**Sintomas**:
```
[SAD] Nenhum token A3 conectado no momento.
```

**Soluções**:
1. Verifica conexão USB: `lsusb | grep -i safenet`
2. Reinicia `pcscd`: `sudo systemctl restart pcscd`
3. Verifica se o daemon do token está rodando:
   - `pcscd --version` deve funcionar
   - `pcscd --foreground --debug` para ver logs

### Senha errada 3 vezes seguidas — token bloqueia

**Causa**: O eToken tem contador de tentativas erradas. Após 3, ele
bloqueia.

**Soluções**:
1. Use o **eToken PKI Manager** no Windows para desbloquear
2. Ou use `pkcs11-tool --module /usr/lib/libeToken.so --login --test-pin`
   (mas isso geralmente também bloqueia)

## Problemas com a senha salva

### "Falha ao decriptar ~/.config/assinador/token.pin.gpg"

**Causa**: A passphrase mudou (ex.: você renomeou o usuário, ou o
machine-id mudou).

**Solução**:
```bash
rm ~/.config/assinador/token.pin.gpg
./sad-assinador.sh  # vai pedir a senha de novo
```

### Quero ver a senha em texto puro

A senha está em GPG. Para decriptar:
```bash
gpg --batch --passphrase "whoami@$(cat /etc/machine-id)" \
    -d ~/.config/assinador/token.pin.gpg
```

### Quero apagar a senha e digitar de novo toda vez

```bash
rm ~/.config/assinador/token.pin.gpg
```

## Problemas com o atalho do menu

### Atalho não aparece no menu de apps

**Causa**: O cache do GNOME pode estar desatualizado. Outro motivo
comum é que o campo `Exec` precisa estar **entre aspas duplas** quando
o caminho tem espaços.

**Solução**:
```bash
# 1. Atualiza o cache
update-desktop-database ~/.local/share/applications/

# 2. Verifica que as aspas estão certas
grep '^Exec=' ~/.local/share/applications/sad-assinador.desktop
# Deve mostrar: Exec="~/sad-assinador/sad-assinador.sh"

# 3. Testa diretamente
gio launch ~/.local/share/applications/sad-assinador.desktop

# 4. Se ainda não aparecer, reinicia o GNOME Shell: Alt+F2, digite 'r'
```

### Atalho aparece mas ícone está errado

**Causa**: O caminho do ícone no `.desktop` está incorreto.

**Verifica**:
```bash
cat ~/.local/share/applications/sad-assinador.desktop | grep Icon=
ls -la ~/sad-assinador/SAD-Assinadorv1.4.1/imagens/detran-log.png
```

**Solução** (se o ícone não existir):
```bash
# Re-extrai a pasta
./src/extract-sad.sh SAD-Assinadorv1.4.1.exe
```

## Problemas com o launcher

### "ERRO: JDK não encontrado"

**Causa**: O `java` não está no PATH nem em `~/java/`.

**Solução**:
```bash
# Instala Zulu 8 FX
mkdir -p ~/java
cd ~/java
wget https://cdn.azul.com/zulu/bin/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64.tar.gz
tar -xzf zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64.tar.gz
```

### "ERRO: pasta do SAD não encontrada em ~/sad-assinador"

**Causa**: Você não extraiu a versão `.exe` ainda.

**Solução**:
```bash
./src/extract-sad.sh SAD-Assinadorv1.4.1.exe
```

### "javac: invalid flag: ..."

**Causa**: O `build.sh` está tentando compilar de forma errada.

**Solução**: Compile manualmente:
```bash
cd ~/sad-assinador/src
~/java/zulu8.78.0.19-ca-fx-jdk8.0.412-linux_x64/bin/javac \
    -cp "~/sad-assinador/SAD-Assinadorv1.4.1" \
    -d "~/sad-assinador/build/classes" \
    SadPreMain.java WrapperKeyStoreSpi.java \
    br/gov/go/detran/sad/controller/VerificaSO.java
```

## Problemas com o SAD em si

### "Uninitialized keystore"

Geralmente não aparece mais após nossos patches. Se aparecer:

1. Confirma que `build/classes/` vem **antes** do SAD no classpath:
   ```bash
   grep -n "cp " sad-assinador.sh
   ```
   Deve mostrar: `-cp "$BUILD_DIR:.:jdtCompilerAdapter.jar"`

2. Re-compila os patches:
   ```bash
   ./src/build.sh
   ```

3. Limpa e re-extrai a versão:
   ```bash
   rm -rf build SAD-Assinadorv1.4.1
   ./src/extract-sad.sh SAD-Assinadorv1.4.1.exe
   ```

### "Configure o certificado para utilizar o Assinador"

Mesmo problema que "Uninitialized keystore" — solução acima.

### SAD não detecta token

Confirma que `pcscd` está rodando e o token está conectado:

```bash
pgrep -a pcscd
pcsc_scan -r  # deve listar o token
```

Se o token aparece no `pcsc_scan` mas o SAD não usa, tenta:
```bash
# Força re-detecção
sudo systemctl restart pcscd
# Desconecta e reconecta o token
# Roda:
./sad-assinador.sh
```

## Logs e debugging

### Ver log do launch

```bash
./sad-assinador.sh 2>&1 | tee /tmp/sad-launch.log
```

### Ver o que o SAD faz (debug)

Adiciona variáveis de ambiente para debug do Java:
```bash
export JAVA_TOOL_OPTIONS="-Djava.util.logging.config.file=/tmp/jul.properties"
echo ".level=ALL" > /tmp/jul.properties
./sad-assinador.sh
```

### Capturar screenshots da tela do SAD

```bash
# Instala scrot ou usa gnome-screenshot
sudo apt install scrot
sleep 10
scrot /tmp/sad-screen.png  # captura depois de 10s
```

## Reset completo

Se nada funcionar, faça reset completo:

```bash
# 1. Mata qualquer SAD rodando
pkill -9 -f br.gov.go.detran
pkill -9 -f SadPreMain

# 2. Remove configs
rm -rf ~/.config/assinador/

# 3. Remove SAD extraído
rm -rf ~/sad-assinador/SAD-Assinadorv*

# 4. Remove patches compilados
rm -rf ~/sad-assinador/build

# 5. Re-extrai tudo
cd ~/sad-assinador/
./src/extract-sad.sh SAD-Assinadorv1.4.1.exe

# 6. Roda
./sad-assinador.sh
```