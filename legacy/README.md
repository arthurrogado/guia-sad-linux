# Versão anterior dos patches (legacy)

Estes arquivos são a primeira abordagem deste projeto (julho/2026), feita
para o SAD 1.2.0, quando a configuração do certificado era manual:

- `patches/CertificadoA3RepositoryImpl.java` — fornece o `CallbackHandler`
  do PKCS#11 (evitava `NullPointerException` no token);
- `patches/TrustAllCertificates.java` — usa o `KeyStore` do token como
  `KeyManager` na conexão mTLS;
- `patches/OIDGeneric.java` — leitura tolerante de extensões ICP-Brasil
  (corrige `ClassCastException` com certificados A1/.pfx modernos);
- `patches/patch.sh` — recompilava os `.class` dentro da pasta do SAD;
- `scripts/instalar.sh` e `scripts/sad-assinador.sh` — instalador antigo.

**O launcher atual (`sad-assinador.sh` na raiz) não usa estes arquivos.**
Ele autentica o token A3 automaticamente e não exige entrar na engrenagem.

Ficam aqui como referência — em especial o patch de `OIDGeneric`, útil
para quem usa certificado **A1 (.pfx)** em versões antigas do SAD.
