package br.gov.go.detran.sad.impl;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyStore;
import java.security.Provider;
import java.security.Security;
import java.util.Collection;
import java.util.Enumeration;
import java.util.Iterator;
import java.util.SortedMap;

import javax.security.auth.callback.Callback;
import javax.security.auth.callback.CallbackHandler;
import javax.security.auth.callback.NameCallback;
import javax.security.auth.callback.PasswordCallback;
import javax.security.auth.callback.UnsupportedCallbackException;

import org.demoiselle.signer.core.keystore.loader.configuration.Configuration;

import br.gov.go.detran.sad.model.CertificadoDigital;
import br.gov.go.detran.sad.repository.CertificadoA3Repository;
import br.gov.go.detran.sad.util.EtapasUtil;

public class CertificadoA3RepositoryImpl extends EtapasUtil implements CertificadoA3Repository {

    private final String local;
    private String senha;

    public CertificadoA3RepositoryImpl() {
        this.local = CertificadoA3RepositoryImpl.class.getName();
    }

    public void getKeyStoreToken(String senha) throws Exception {
        this.senha = senha;
        Provider provider = carregaToken();
        Security.addProvider(provider);
        KeyStore keyStore = KeyStore.getInstance("PKCS11", provider);
        keyStore.load(null, senha != null ? senha.toCharArray() : null);

        String alias = null;
        Enumeration<String> aliases = keyStore.aliases();
        while (aliases.hasMoreElements()) {
            String a = aliases.nextElement();
            if (keyStore.isKeyEntry(a)) {
                alias = a;
                break;
            }
        }

        CertificadoDigital certificadoDigital = getCertificadoDigital();
        certificadoDigital.setKeyStore(keyStore);
        certificadoDigital.setAlias(alias);
        certificadoDigital.setSenha(senha != null ? senha.toCharArray() : null);
    }

    public Provider carregaToken() {
        try {
            Configuration configuration = Configuration.getInstance();
            SortedMap<String, String> drivers = configuration.getDrivers();
            Collection<String> values = drivers.values();
            Iterator<String> iterator = values.iterator();

            StringBuilder builder = new StringBuilder();
            builder.append("library = ");
            builder.append(iterator.next());
            builder.append("\nname = A3\n");

            CallbackHandler handler = new CallbackHandler() {
                public void handle(Callback[] callbacks) throws UnsupportedCallbackException {
                    for (Callback callback : callbacks) {
                        if (callback instanceof PasswordCallback) {
                            ((PasswordCallback) callback).setPassword(
                                    senha != null ? senha.toCharArray() : new char[0]);
                        } else if (callback instanceof NameCallback) {
                            ((NameCallback) callback).setName("");
                        } else {
                            throw new UnsupportedCallbackException(callback);
                        }
                    }
                }
            };

            File cfgFile = new File(System.getProperty("java.io.tmpdir"), "sad_pkcs11.cfg");
            Files.write(cfgFile.toPath(), builder.toString().getBytes("UTF-8"));

            Provider provider = new sun.security.pkcs11.SunPKCS11(cfgFile.getAbsolutePath());
            KeyStore.Builder keyStoreBuilder = KeyStore.Builder.newInstance("PKCS11", provider,
                    new KeyStore.CallbackHandlerProtection(handler));
            keyStoreBuilder.getKeyStore();
            return provider;
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }
}
