/*
 * VerificaSO.java — Patched: no Linux, NÃO mostra "Configure o certificado".
 *
 * Esta classe substitui a versão do SAD-Assinadorv1.3.0 (e versões
 * anteriores) e tem o mesmo comportamento EXCETO pelo bug de design:
 *
 *   - No SAD original, quando KeyStore é null e SO é Linux, mostra
 *     "Configure o certificado para utilizar o Assinador."
 *
 *   - Aqui, nós sempre seguimos para o SelecionarCertificadoController,
 *     porque o SadPreMain pré-populou a KeyStore. Mesmo que a KeyStore
 *     seja null, é melhor cair no SelecionarCertificadoController para
 *     deixar o usuário tentar autenticar com a senha do token.
 *
 * A versão Linux do VerificaSO é quase idêntica à do SAD — só removemos
 * o showAlert de "Configure o certificado" e "Sistema Operacional não
 * compatível".
 */
package br.gov.go.detran.sad.controller;

import br.gov.go.detran.sad.util.EtapasUtil;
import br.gov.go.detran.sad.controller.SelecionarCertificadoController;
import br.gov.go.detran.sad.model.SistemaOperacional;
import br.gov.go.detran.sad.util.AlertHelper;
import br.gov.go.detran.sad.model.CertificadoDigital;
import java.security.KeyStore;

public class VerificaSO extends EtapasUtil {

    public VerificaSO() {
        super();
    }

    public void verificaSistemaOperacional() {
        SistemaOperacional so = new SistemaOperacional();
        CertificadoDigital cert = getCertificadoDigital();
        KeyStore ks = cert == null ? null : cert.getKeyStore();
        boolean keyStoreVazio = (ks == null);

        // BUGFIX: no Linux, NÃO mostra "Configure o certificado".
        // Mesmo que a KeyStore esteja null, deixamos o SAD prosseguir
        // para o SelecionarCertificadoController — ele tentará carregar
        // os certificados do token via PKCS11 quando o usuário informar
        // a senha. Isso evita o erro que só serve para confundir o
        // usuário no Linux.
        //
        // Janela/MS mantêm o comportamento original para compatibilidade.
        if (so.isWindows() && keyStoreVazio) {
            // Carregar Windows-MY
            try {
                KeyStore winKs = KeyStore.getInstance("Windows-MY", "SunMSCAPI");
                cert.setKeyStore(winKs);
                winKs.load(null, null);
            } catch (Exception e) {
                e.printStackTrace();
            }
        } else if (so.isMac() && keyStoreVazio) {
            // Carregar KeychainStore
            try {
                KeyStore macKs = KeyStore.getInstance("KeychainStore", "Apple");
                cert.setKeyStore(macKs);
                macKs.load(null, null);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        // Para Unix (incl. Linux) e qualquer caso onde keyStoreVazio=true,
        // simplesmente seguimos em frente. O SelecionarCertificadoController
        // vai lidar com o token.
        try {
            new SelecionarCertificadoController().initTela();
        } catch (Exception e) {
            AlertHelper alertHelper = getAlertHelper();
            String msg = br.gov.go.detran.sad.util.ConexaoUtil.msgException(e);
            try {
                Class<?> t = Class.forName("br.gov.go.detran.sad.util.Tracer");
                java.lang.reflect.Method m = t.getDeclaredMethod("enviarTracerError",
                    String.class, String.class, String.class);
                m.invoke(null, "VERIFICA_SO", e.getClass().getName(), msg);
            } catch (Throwable ignore) {}
            new br.gov.go.detran.sad.util.AlertaException().mostrarException(e,
                "Assinador Digital - Detran GO");
        }
    }
}