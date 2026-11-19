/*
 * SadPreMain.java
 *
 * Hook de pré-inicialização do SAD Assinador para Linux.
 *
 * Resolve os problemas do SAD rodando no Linux:
 *
 *   1) Configura o driver PKCS#11 (libeToken.so, etc.) ANTES da MainApp.
 *   2) Pré-popula o EtapasUtil.certificadoDigital com uma KeyStore PKCS#11
 *      robusta (WrapperKeyStoreSpi), evitando:
 *      - "Configure o certificado para utilizar o Assinador" (VerificaSO)
 *      - "Uninitialized keystore" (SelecionarCertificadoController.criaKeyStore)
 *
 * Uso: java -cp ... br.gov.go.detran.sad.SadPreMain <driver.so|-> [args para MainApp]
 *
 * O PreMain faz, em ordem:
 *   a) Detecta o driver PKCS#11 e configura o SunPKCS11 provider
 *   b) Cria uma KeyStore PKCS11 (que pode precisar de load() com senha)
 *   c) Envolve a KeyStore num WrapperKeyStoreSpi (em outro arquivo) que
 *      captura KeyStoreException e retorna valores neutros para os métodos
 *      problemáticos (aliases(), size(), etc.).
 *   d) Seta o WrapperKeyStoreSpi no EtapasUtil.certificadoDigital.
 *   e) Chama o main() da MainApp original.
 */
package br.gov.go.detran.sad;

import java.io.ByteArrayInputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.security.KeyStore;
import java.security.KeyStoreSpi;
import java.security.Provider;
import java.security.Security;
import java.util.Collections;
import java.util.Enumeration;

public final class SadPreMain {

    private SadPreMain() {}

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("Uso: java ... br.gov.go.detran.sad.SadPreMain " +
                "<driver.so|-> [args para MainApp]");
            System.exit(1);
        }

        String driverArg = args[0];
        String[] remaining = new String[args.length - 1];
        System.arraycopy(args, 1, remaining, 0, remaining.length);

        // Extrai o caminho do driver do formato "SADToken::/usr/lib/..."
        if (driverArg != null && driverArg.contains("::")) {
            driverArg = driverArg.substring(driverArg.indexOf("::") + 2);
        }

        System.out.println("[SAD-PreMain] Driver PKCS#11: " + driverArg);

        // Tenta usar o Demoiselle Signer Configuration
        try {
            Class<?> configClass = Class.forName(
                "org.demoiselle.signer.core.keystore.loader.configuration.Configuration");
            Method getInstance = configClass.getDeclaredMethod("getInstance");
            Object config = getInstance.invoke(null);
            if (driverArg != null && !driverArg.isEmpty() && !driverArg.equals("-")) {
                Method addDriver = configClass.getDeclaredMethod(
                    "addDriver", String.class, String.class);
                addDriver.invoke(config, "SADToken", driverArg);
            }
        } catch (Throwable t) {
            // OK — Demoiselle não disponível, segue sem ele.
        }

        // Cria uma KeyStore PKCS#11 robusta
        KeyStore ks;
        try {
            ks = criarKeyStoreRobusta(driverArg);
        } catch (Throwable t) {
            System.err.println("[SAD-PreMain] Falha ao criar KeyStore: " + t);
            t.printStackTrace(System.err);
            // Segue sem key store pré-populada; o usuário entrará na engrenagem.
            chamarMainApp(remaining);
            return;
        }

        // NOVO: Se temos a senha do token (env SAD_TOKEN_PIN), autenticamos
        // o PKCS11 automaticamente. Isso faz o KeyStore carregar os certificados
        // do token, que aparecem na tela de seleção sem precisar entrar na
        // engrenagem.
        String pin = System.getenv("SAD_TOKEN_PIN");
        if (pin != null && !pin.isEmpty() && ks != null) {
            System.out.println("[SAD-PreMain] Autenticando token com PIN...");
            try {
                // Carrega o KeyStore com a senha
                ks.load(null, pin.toCharArray());
                System.out.println("[SAD-PreMain] Token autenticado. " +
                    "Aliases: " + Collections.list(ks.aliases()));
            } catch (Throwable t) {
                System.err.println("[SAD-PreMain] Falha ao autenticar token: " + t.getMessage());
                // Não bloqueia — o usuário pode autenticar manualmente.
            }
        }

        // Seta no EtapasUtil.certificadoDigital via reflection
        try {
            Class<?> etapasUtilClass = Class.forName(
                "br.gov.go.detran.sad.util.EtapasUtil");
            Class<?> certDigitalClass = Class.forName(
                "br.gov.go.detran.sad.model.CertificadoDigital");

            Method setCertDigital = etapasUtilClass.getDeclaredMethod(
                "setCertificadoDigital", certDigitalClass);

            Object certBean = certDigitalClass.getDeclaredConstructor().newInstance();
            certDigitalClass.getMethod("setKeyStore", KeyStore.class)
                .invoke(certBean, ks);

            setCertDigital.invoke(null, certBean);

            System.out.println("[SAD-PreMain] KeyStore PKCS#11 robusta " +
                "pré-carregada no EtapasUtil.");
        } catch (Throwable t) {
            System.err.println("[SAD-PreMain] Falha ao setar KeyStore no EtapasUtil: " + t);
            t.printStackTrace(System.err);
        }

        // Chama a MainApp original
        chamarMainApp(remaining);
    }

    private static void chamarMainApp(String[] args) throws Exception {
        Class<?> mainAppClass = Class.forName("br.gov.go.detran.sad.MainApp");
        Method mainMethod = mainAppClass.getDeclaredMethod("main", String[].class);
        mainMethod.invoke(null, (Object) args);
    }

    /**
     * Cria uma KeyStore PKCS#11 envolta num WrapperKeyStoreSpi que captura
     * KeyStoreException("Uninitialized keystore") retornando valores neutros.
     *
     * Sem esse wrapper, o SelecionarCertificadoController.criaKeyStore()
     * do SAD chama ks.aliases() e trava com "Uninitialized keystore" porque
     * o PKCS11 exige load() (que precisa de senha) antes de listar aliases.
     *
     * Aqui:
     *   1. Cria a KeyStore PKCS#11 via SunPKCS11.
     *   2. Tenta ks.load(null, null). Se funcionar (token off-line, ou
     *      sem PIN), aliases() vai funcionar. Se falhar, capturamos.
     *   3. Envolve a KeyStore num WrapperKeyStoreSpi (definido em arquivo
     *      separado para evitar problemas com classe anônima) que intercepta
     *      aliases()/size()/etc e captura KeyStoreException.
     */
    private static KeyStore criarKeyStoreRobusta(String driver) throws Exception {
        if (driver == null || driver.isEmpty() || driver.equals("-")) {
            // Sem driver — não cria KeyStore PKCS11.
            return null;
        }

        // 1. Cria o SunPKCS11 provider
        String cfg = "name = SADToken\nlibrary = " + driver + "\n";
        byte[] cfgBytes = cfg.getBytes("UTF-8");

        Class<?> sunPkcs11Class = Class.forName("sun.security.pkcs11.SunPKCS11");
        Constructor<?> sunCtor = sunPkcs11Class.getConstructor(java.io.InputStream.class);
        Provider provider = (Provider) sunCtor.newInstance(
            new ByteArrayInputStream(cfgBytes));
        Security.addProvider(provider);

        // 2. Cria a KeyStore PKCS11
        KeyStore real = KeyStore.getInstance("PKCS11", provider);

        // 3. Tenta load(null, null) — pode falhar se o token exigir PIN
        try {
            real.load(null, null);
            System.out.println("[SAD-PreMain] KeyStore PKCS11 inicializada com load() OK.");
        } catch (Throwable t) {
            System.out.println("[SAD-PreMain] KeyStore PKCS11 criada, load() " +
                "falhou (provavelmente precisa de PIN): " + t.getMessage());
        }

        // 4. Pega o KeyStoreSpi do real via reflection
        java.lang.reflect.Field spiField = KeyStore.class.getDeclaredField("keyStoreSpi");
        spiField.setAccessible(true);
        KeyStoreSpi realSpi = (KeyStoreSpi) spiField.get(real);

        // 5. Cria o wrapper (classe separada)
        KeyStoreSpi wrapperSpi = new WrapperKeyStoreSpi(realSpi, real.getType());

        // 6. Cria uma nova KeyStore passando o wrapperSpi via reflection
        Constructor<KeyStore> ksCtor = KeyStore.class.getDeclaredConstructor(
            KeyStoreSpi.class, Provider.class, String.class);
        ksCtor.setAccessible(true);
        KeyStore wrapped = ksCtor.newInstance(wrapperSpi, provider, real.getType());

        // 7. IMPORTANTE: KeyStore.aliases() (público, final) checa o campo
        //    `initialized` ANTES de chamar engineAliases() do SPI. Como o
        //    PKCS11 não foi inicializado (load falhou), `initialized=false`
        //    e o método público lança "Uninitialized keystore" direto.
        //
        //    Solução: setar `initialized = true` via reflection. Isso faz
        //    o método público chamar nosso wrapperSpi.engineAliases() que
        //    captura a exceção e retorna Enumeration vazia.
        java.lang.reflect.Field initField = KeyStore.class.getDeclaredField("initialized");
        initField.setAccessible(true);
        initField.setBoolean(wrapped, true);

        return wrapped;
    }
}