package br.gov.go.detran.rs.client;

import java.net.Socket;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManager;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

import br.gov.go.detran.sad.model.CertificadoDigital;
import br.gov.go.detran.sad.util.EtapasUtil;
import br.gov.go.detran.util.LogDetranUtil;

public final class TrustAllCertificates implements X509TrustManager, javax.net.ssl.HostnameVerifier {

    public TrustAllCertificates() {
    }

    public java.security.cert.X509Certificate[] getAcceptedIssuers() {
        return null;
    }

    public void checkClientTrusted(java.security.cert.X509Certificate[] certs, String authType) {
        LogDetranUtil.debug("checkClientTrusted");
    }

    public void checkServerTrusted(java.security.cert.X509Certificate[] certs, String authType) throws CertificateException {
        LogDetranUtil.debug("checkServerTrusted");
    }

    public boolean verify(String hostname, SSLSession session) {
        return hostname.equalsIgnoreCase(session.getPeerHost());
    }

    public static void install() {
        try {
            TrustAllCertificates tm = new TrustAllCertificates();
            SSLContext context = SSLContext.getInstance("TLSv1.2");

            KeyManager[] keyManagers = null;
            try {
                CertificadoDigital cd = EtapasUtil.getCertificadoDigital();
                if (cd != null && cd.getKeyStore() != null) {
                    KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
                    kmf.init(cd.getKeyStore(), cd.getSenha() != null ? cd.getSenha() : new char[0]);
                    keyManagers = kmf.getKeyManagers();
                    LogDetranUtil.debug("KeyManager do token configurado para mTLS");
                }
            } catch (Exception e) {
                LogDetranUtil.debug("Nao foi possivel configurar KeyManager do token: " + e.getMessage());
            }

            context.init(keyManagers, new TrustManager[] { tm }, new SecureRandom());
            HttpsURLConnection.setDefaultSSLSocketFactory(context.getSocketFactory());
            HttpsURLConnection.setDefaultHostnameVerifier(tm);
        } catch (Exception e) {
            throw new br.gov.go.detran.core.exception.ValidationException("Failed setting up all thrusting certificate manager.", e);
        }
    }
}
