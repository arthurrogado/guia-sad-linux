/*
 * WrapperKeyStoreSpi.java
 *
 * KeyStoreSpi "tolerante" usado pelo SadPreMain.
 *
 * O SAD (SelecionarCertificadoController.criaKeyStore) chama metodos como
 * aliases()/size() na KeyStore PKCS#11. Quando o token ainda nao foi
 * autenticado (load(null, pin) nao foi chamado), o SunPKCS11 lanca
 * KeyStoreException("Uninitialized keystore") — e a tela de selecao quebra.
 *
 * Esta classe delega tudo para o SPI real do PKCS#11, mas captura
 * KeyStoreException (e RuntimeException do provedor) nos metodos de leitura,
 * devolvendo valores neutros. Assim a tela abre sempre; quando o token e
 * autenticado, os certificados aparecem normalmente.
 */
package br.gov.go.detran.sad;

import java.io.InputStream;
import java.io.OutputStream;
import java.security.Key;
import java.security.KeyStoreException;
import java.security.KeyStoreSpi;
import java.security.NoSuchAlgorithmException;
import java.security.UnrecoverableKeyException;
import java.security.cert.Certificate;
import java.security.cert.CertificateException;
import java.util.Collections;
import java.util.Date;
import java.util.Enumeration;

public class WrapperKeyStoreSpi extends KeyStoreSpi {

    private final KeyStoreSpi real;
    private final String type;

    public WrapperKeyStoreSpi(KeyStoreSpi real, String type) {
        this.real = real;
        this.type = type;
    }

    private boolean delegar() {
        return real != null;
    }

    private static Enumeration<String> vazio() {
        return Collections.enumeration(Collections.<String>emptyList());
    }

    @Override
    public Key engineGetKey(String alias, char[] password)
            throws NoSuchAlgorithmException, UnrecoverableKeyException {
        if (!delegar()) {
            return null;
        }
        try {
            return real.engineGetKey(alias, password);
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public Certificate[] engineGetCertificateChain(String alias) {
        if (!delegar()) {
            return null;
        }
        try {
            return real.engineGetCertificateChain(alias);
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public Certificate engineGetCertificate(String alias) {
        if (!delegar()) {
            return null;
        }
        try {
            return real.engineGetCertificate(alias);
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public Date engineGetCreationDate(String alias) {
        if (!delegar()) {
            return null;
        }
        try {
            return real.engineGetCreationDate(alias);
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public void engineSetKeyEntry(String alias, Key key, char[] password,
            Certificate[] chain) throws KeyStoreException {
        if (!delegar()) {
            throw new KeyStoreException("KeyStore indisponivel (" + type + ")");
        }
        real.engineSetKeyEntry(alias, key, password, chain);
    }

    @Override
    public void engineSetKeyEntry(String alias, byte[] key,
            Certificate[] chain) throws KeyStoreException {
        if (!delegar()) {
            throw new KeyStoreException("KeyStore indisponivel (" + type + ")");
        }
        real.engineSetKeyEntry(alias, key, chain);
    }

    @Override
    public void engineSetCertificateEntry(String alias, Certificate cert)
            throws KeyStoreException {
        if (!delegar()) {
            throw new KeyStoreException("KeyStore indisponivel (" + type + ")");
        }
        real.engineSetCertificateEntry(alias, cert);
    }

    @Override
    public void engineDeleteEntry(String alias) throws KeyStoreException {
        if (!delegar()) {
            throw new KeyStoreException("KeyStore indisponivel (" + type + ")");
        }
        real.engineDeleteEntry(alias);
    }

    @Override
    public Enumeration<String> engineAliases() {
        if (!delegar()) {
            return vazio();
        }
        try {
            return real.engineAliases();
        } catch (RuntimeException e) {
            return vazio();
        }
    }

    @Override
    public boolean engineContainsAlias(String alias) {
        if (!delegar()) {
            return false;
        }
        try {
            return real.engineContainsAlias(alias);
        } catch (RuntimeException e) {
            return false;
        }
    }

    @Override
    public int engineSize() {
        if (!delegar()) {
            return 0;
        }
        try {
            return real.engineSize();
        } catch (RuntimeException e) {
            return 0;
        }
    }

    @Override
    public boolean engineIsKeyEntry(String alias) {
        if (!delegar()) {
            return false;
        }
        try {
            return real.engineIsKeyEntry(alias);
        } catch (RuntimeException e) {
            return false;
        }
    }

    @Override
    public boolean engineIsCertificateEntry(String alias) {
        if (!delegar()) {
            return false;
        }
        try {
            return real.engineIsCertificateEntry(alias);
        } catch (RuntimeException e) {
            return false;
        }
    }

    @Override
    public String engineGetCertificateAlias(Certificate cert) {
        if (!delegar()) {
            return null;
        }
        try {
            return real.engineGetCertificateAlias(cert);
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public void engineStore(OutputStream stream, char[] password)
            throws java.io.IOException, NoSuchAlgorithmException,
            CertificateException {
        if (!delegar()) {
            return;
        }
        real.engineStore(stream, password);
    }

    @Override
    public void engineLoad(InputStream stream, char[] password)
            throws java.io.IOException, NoSuchAlgorithmException,
            CertificateException {
        if (!delegar()) {
            return;
        }
        // IMPORTANTE: delegar de verdade — e aqui que o PKCS#11 autentica
        // com o PIN e libera os certificados.
        real.engineLoad(stream, password);
    }
}
