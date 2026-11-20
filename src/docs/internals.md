# Análise técnica do bytecode

Este documento é um registro técnico da engenharia reversa feita no
SAD para descobrir e resolver os bugs de design.

## Ferramentas utilizadas

- `javap -p -c` (do JDK): disassembler padrão
- `javap -p -v`: dump completo com constant pool
- `strings`: para localizar strings de mensagem
- `find ... | xargs grep`: localizar referências cruzadas

## Estrutura do SAD Assinador

```
br/gov/go/detran/sad/
├── MainApp.class                 ← Entry point JavaFX
├── util/
│   ├── EtapasUtil.class           ← Singleton estático (certificadoDigital, etc.)
│   ├── AlertHelper.class
│   └── AlertaException.class
├── model/
│   ├── CertificadoDigital.class   ← POJO (keyStore, senha, alias, etc.)
│   ├── SistemaOperacional.class   ← isUnix(), isWindows(), isMac()
│   ├── Operador.class
│   └── MainApp (não temos)
├── repository/
│   ├── CertificadoA3Repository.class
│   └── SelecionarCertificadoController (não temos)
├── controller/
│   ├── LoginViewController.class  ← Tela inicial (botão Login)
│   ├── VerificaSO.class           ← 🐛 BUG 1: "Configure o certificado"
│   ├── SelecionarCertificadoController.class ← 🐛 BUG 2: "Uninitialized keystore"
│   └── ConfigCertificadoController.class (engrenagem ⚙️)
└── impl/
    ├── CertificadoA3RepositoryImpl.class
    ├── LoginRepositoryImpl.class
    └── AssinaturaRespositoryImpl.class

org/demoiselle/signer/core/keystore/loader/
├── Configuration.class             ← Lê ~/.signer/drivers.properties
├── KeyStoreLoader.class
├── factory/
│   └── KeyStoreLoaderFactory.class
└── implementation/
    ├── DriverKeyStoreLoader.class  ← PKCS11 loader
    ├── FileSystemKeyStoreLoader.class
    ├── MSKeyStoreLoader.class     ← Windows MSCAPI
    └── PKCS11Logout.class
```

## Bug 1: VerificaSO

### Source (decompilado)

```java
public class VerificaSO extends EtapasUtil {
    public void verificaSistemaOperacional() {
        SistemaOperacional so = new SistemaOperacional();
        boolean keyStoreVazio = (getCertificadoDigital().getKeyStore() == null);

        if (so.isWindows() && keyStoreVazio) {
            // Carrega Windows-MY
            ...
        } else if (so.isMac() && keyStoreVazio) {
            // Carrega KeychainStore
            ...
        } else if (so.isUnix() && keyStoreVazio) {
            // ❌ "Configure o certificado para utilizar o Assinador."
        }
        new SelecionarCertificadoController().initTela();
    }
}
```

### Bytecode

```java
public void verificaSistemaOperacional();
  Code:
     0: new           #2 // class SistemaOperacional
     3: dup
     4: invokespecial #3 // <init>
     7: astore_1
     8: invokestatic  #4 // getCertificadoDigital()
    11: invokevirtual #5 // getKeyStore()
    14: ifnonnull     21    // ← se KeyStore != null, pula
    17: iconst_1
    18: goto          22
    21: iconst_0
    22: istore_2              // keyStoreVazio = (KeyStore == null)
    23: aload_1
    24: invokevirtual #6 // isWindows()
    27: ifeq          68
    30: iload_2
    31: ifeq          149   // se !keyStoreVazio, pula para 149
    ...
    68: aload_1
    69: invokevirtual #14 // isMac()
    72: ifeq          106
    ...
   106: aload_1
   107: invokevirtual #20 // isUnix()
   110: ifeq          133   // se !isUnix, pula para 133
   113: iload_2
   114: ifeq          149   // se !keyStoreVazio, pula para 149
   117: ldc           #21 // "Configure o certificado para utilizar o Assinador."
   119: astore_3
   ...
   149: new           #29 // SelecionarCertificadoController
   ...
```

### Análise do `isUnix()`

```java
public class SistemaOperacional {
    private static final String OS = System.getProperty("os.name").toLowerCase();

    public boolean isUnix() {
        return OS.contains("nix") ||
               OS.contains("nux") ||
               OS.indexOf("aix") > 0;
    }
}
```

Em Java 8, `System.getProperty("os.name")` no Linux retorna `"Linux"`.
Lowercase = `"linux"`. Como `"linux"` **contém `"nux"`**, retorna `true`.

### Nosso patch

Substituímos o `VerificaSO` por uma versão que pula o showAlert para
Unix. Como o SAD já tem a KeyStore pré-populada pelo SadPreMain, o
fluxo segue normal.

```java
public class VerificaSO extends EtapasUtil {
    public void verificaSistemaOperacional() {
        SistemaOperacional so = new SistemaOperacional();
        CertificadoDigital cert = getCertificadoDigital();
        KeyStore ks = cert == null ? null : cert.getKeyStore();
        boolean keyStoreVazio = (ks == null);

        if (so.isWindows() && keyStoreVazio) { /* ... */ }
        else if (so.isMac() && keyStoreVazio) { /* ... */ }
        // Para Unix, simplesmente segue em frente.
        new SelecionarCertificadoController().initTela();
    }
}
```

## Bug 2: SelecionarCertificadoController

### Source (decompilado)

```java
public class SelecionarCertificadoController extends EtapasUtil {
    public void initialize(URL u, ResourceBundle r) {
        view.setItems(criaKeyStore());
        selecionar.setDisable(true);
        clickAction();
    }

    private ObservableList<String> criaKeyStore() {
        ObservableList<String> list = FXCollections.observableArrayList();
        KeyStore ks = getCertificadoDigital().getKeyStore();
        Enumeration<String> aliases = ks.aliases(); // ❌ throws
        ...
    }
}
```

### Bytecode do método público `KeyStore.aliases()`

```java
public final java.util.Enumeration<java.lang.String> aliases()
    throws java.security.KeyStoreException;
  Code:
     0: aload_0
     1: getfield      #1 // Field initialized:Z
     4: ifne          17
     7: new           #25 // class KeyStoreException
    10: dup
    11: ldc           #38 // String Uninitialized keystore
    13: invokespecial #39 // <init>
    16: athrow
    17: aload_0
    18: getfield      #2 // Field keyStoreSpi
    21: checkcast     #3 // KeyStoreSpi
    24: invokeinterface #4,  1 // engineAliases()
    29: areturn
```

**O método público `aliases()` (final)** verifica o campo `initialized`
ANTES de chamar `engineAliases()` do SPI.

Como o `KeyStore.getInstance("PKCS11", provider)` retorna um KeyStore
com `initialized = false`, qualquer chamada a `aliases()` lança
"Uninitialized keystore" antes mesmo de chegar no SPI.

### Por que o Windows não tem esse problema?

O `KeyStore.getInstance("Windows-MY", "SunMSCAPI")` no Windows retorna
um KeyStore onde o **construtor já faz `engineLoad(null, null)`**. O campo
`initialized` é setado para `true` automaticamente. Por isso o Windows
funciona sem precisar do usuário entrar na engrenagem.

### Nosso patch em duas camadas

**Camada 1: WrapperKeyStoreSpi** (subclasse de KeyStoreSpi)

```java
public class WrapperKeyStoreSpi extends KeyStoreSpi {
    private final KeyStoreSpi real;
    private final String type;

    public WrapperKeyStoreSpi(KeyStoreSpi real, String type) {
        this.real = real;
        this.type = type;
    }

    @Override
    public Enumeration<String> engineAliases() {
        try { return real.engineAliases(); }
        catch (Throwable t) { return Collections.emptyEnumeration(); }
    }

    // ... engineSize, engineIsKeyEntry, engineContainsAlias, etc ...
}
```

**Camada 2: SadPreMain** (força `initialized = true` via reflection)

```java
KeyStore wrapped = KeyStore.class.getDeclaredConstructor(
    KeyStoreSpi.class, Provider.class, String.class
).newInstance(wrapperSpi, provider, real.getType());

// Força initialized = true (que o construtor do KeyStore não setou)
Field initField = KeyStore.class.getDeclaredField("initialized");
initField.setAccessible(true);
initField.setBoolean(wrapped, true);
```

### Fluxo do wrapper

1. SAD chama `wrapped.aliases()` → método público do `KeyStore`
2. `KeyStore.aliases()` checa `initialized = true` (nosso) → não lança
3. Chama `wrapped.engineAliases()` → delega para nosso `WrapperKeyStoreSpi`
4. Wrapper chama `real.engineAliases()` → PKCS11 real (autenticado, retorna aliases)
5. **Sucesso!** Lista aparece com os certificados do token

## SadPreMain: o orquestrador

### Fluxo

```
1. main(args):
   - Extrai driver path do formato "SADToken::/usr/lib/..."
   - Lê SAD_TOKEN_PIN do env

2. Tenta Demoiselle Configuration.addDriver (opcional)

3. criarKeyStoreRobusta(driver):
   - Cria SunPKCS11 provider com cfg inline
   - Security.addProvider(provider)
   - KeyStore.getInstance("PKCS11", provider) ← uninitialized

4. Se pin != null:
   - ks.load(null, pin.toCharArray()) ← AUTENTICA O TOKEN

5. Pega KeyStoreSpi via reflection:
   - Field keyStoreSpi = KeyStore.class.getDeclaredField("keyStoreSpi")
   - spiField.setAccessible(true)
   - KeyStoreSpi realSpi = spiField.get(ks)

6. Cria WrapperKeyStoreSpi(realSpi, type) ← nossa subclasse

7. Cria nova KeyStore passando wrapperSpi via reflection:
   - Constructor<KeyStore> ctor = KeyStore.class.getDeclaredConstructor(
       KeyStoreSpi.class, Provider.class, String.class
     );
   - ctor.setAccessible(true);
   - KeyStore wrapped = ctor.newInstance(wrapperSpi, provider, type);

8. Força initialized = true:
   - Field initField = KeyStore.class.getDeclaredField("initialized");
   - initField.setBoolean(wrapped, true);

9. Seta no EtapasUtil via reflection:
   - Class<?> etapasUtilClass = Class.forName("br.gov.go.detran.sad.util.EtapasUtil");
   - Class<?> certDigitalClass = Class.forName("br.gov.go.detran.sad.model.CertificadoDigital");
   - Object certBean = certDigitalClass.getDeclaredConstructor().newInstance();
   - certDigitalClass.getMethod("setKeyStore", KeyStore.class).invoke(certBean, wrapped);
   - etapasUtilClass.getMethod("setCertificadoDigital", certDigitalClass).invoke(null, certBean);

10. Class.forName("br.gov.go.detran.sad.MainApp").getMethod("main", String[].class)
    .invoke(null, (Object) remainingArgs);
```

### Por que reflection?

Porque `br.gov.go.detran.sad.util.EtapasUtil` tem campos
**private static**, e seus métodos setter são `public static`. Podemos
chamar os setters diretamente. Mas para criar uma subclasse de
`KeyStoreSpi` que sobrescreve só o necessário, não precisamos
modificar nada da SAD — só adicionar uma classe com mesmo nome no
classpath.

## Detalhes do `Config.java` (Demoiselle)

```java
public class Configuration {
    public static final String VAR_PKCS11_CONFIG = "PKCS11_CONFIG_FILE";
    public static final String VAR_PKCS11_DRIVER = "PKCS11_DRIVER";
    public static final String CUSTOM_CONFIG_PATH = "user.home";
    public static final String CUSTOM_CONFIG_FILENAME = "drivers.config";

    public String getPKCS11ConfigFile() {
        return getContentFromVariables(VAR_PKCS11_CONFIG);
    }

    public SortedMap<String, String> getDrivers() {
        // Lê ~/.signer/drivers.properties OU custom
        // Cada entry: name -> file
    }
}
```

O Demoiselle usa `getDrivers()` para listar candidatos PKCS#11. Ele já tem
vários defaults hardcoded (incluindo `/usr/lib/libeToken.so`).

### Formato do env var `PKCS11_DRIVER`

```
PKCS11_DRIVER="SADToken::<path_do_driver>"
```

O Demoiselle faz split por `::` para separar nome do path.

## Conclusão

O SAD no Linux precisa de:
1. **Driver PKCS#11** disponível em `/usr/lib/`
2. **KeyStore PKCS#11** autenticado com senha do token
3. **Métodos do KeyStore** que não crashem quando chamados antes do load
4. **`VerificaSO`** que não mostre "Configure o certificado" no Linux

Tudo isso é fornecido pelos nossos patches + launcher.