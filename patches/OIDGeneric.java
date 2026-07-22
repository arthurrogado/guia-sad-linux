package org.demoiselle.signer.core.oid;

import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import org.bouncycastle.asn1.ASN1Encodable;
import org.bouncycastle.asn1.ASN1InputStream;
import org.bouncycastle.asn1.ASN1ObjectIdentifier;
import org.bouncycastle.asn1.ASN1Primitive;
import org.bouncycastle.asn1.ASN1Sequence;
import org.bouncycastle.asn1.DERIA5String;
import org.bouncycastle.asn1.DEROctetString;
import org.bouncycastle.asn1.DERPrintableString;
import org.bouncycastle.asn1.DERTaggedObject;
import org.bouncycastle.asn1.DERUTF8String;
import org.bouncycastle.asn1.DLSequence;
import org.demoiselle.signer.core.util.MessagesBundle;
import sun.security.util.DerValue;
import sun.security.x509.OtherName;

public class OIDGeneric {
    private String oid = null;
    private String data = null;
    private static String packageName = "org.demoiselle.signer.core.oid.OID_";
    protected Map<String, String> properties = new HashMap<String, String>();
    private static ASN1InputStream is;
    private static MessagesBundle coreMessagesBundle;

    protected OIDGeneric() {
    }

    public static OIDGeneric getInstance(byte[] data) throws IOException, Exception {
        OIDGeneric oidGenerico;
        is = new ASN1InputStream(data);
        ASN1Primitive obj = is.readObject();
        
        ASN1ObjectIdentifier oid = null;
        String extractedData = "";
        
        // Certificados ICP-Brasil podem usar diferentes estruturas ASN.1
        if (obj instanceof DLSequence) {
            DLSequence sequence = (DLSequence) obj;
            if (sequence.size() >= 2) {
                ASN1Encodable first = sequence.getObjectAt(0);
                ASN1Encodable second = sequence.getObjectAt(1);
                
                if (first instanceof ASN1ObjectIdentifier) {
                    oid = (ASN1ObjectIdentifier) first;
                }
                
                // Extrai dados do segundo elemento (pode ser tagged, octet, string, etc)
                extractedData = extractData(second);
            }
        } else if (obj instanceof DERTaggedObject) {
            // Formato moderno: tagged object direto
            ASN1Encodable content = ((DERTaggedObject) obj).getObject();
            
            if (content instanceof ASN1Sequence) {
                ASN1Sequence seq = (ASN1Sequence) content;
                if (seq.size() >= 2) {
                    ASN1Encodable first = seq.getObjectAt(0);
                    ASN1Encodable second = seq.getObjectAt(1);
                    
                    if (first instanceof ASN1ObjectIdentifier) {
                        oid = (ASN1ObjectIdentifier) first;
                    }
                    extractedData = extractData(second);
                }
            } else {
                // Conteúdo direto no tagged object
                extractedData = extractData(content);
            }
        } else if (obj instanceof DEROctetString) {
            // Alguns OIDs podem vir como octet string direto
            extractedData = new String(((DEROctetString) obj).getOctets(), "UTF-8");
        }
        
        // Se não conseguiu extrair OID, usa um padrão
        if (oid == null) {
            oid = new ASN1ObjectIdentifier("0.0.0");
        }
        
        String className = OIDGeneric.getPackageName() + oid.getId().replaceAll("[.]", "_");
        try {
            oidGenerico = (OIDGeneric) Class.forName(className).newInstance();
        } catch (InstantiationException e) {
            throw new Exception(coreMessagesBundle.getString("error.class.instance", className), e);
        } catch (IllegalAccessException e) {
            throw new Exception(coreMessagesBundle.getString("error.class.illegal.access", className), e);
        } catch (ClassNotFoundException e) {
            oidGenerico = new OIDGeneric();
        }
        
        oidGenerico.oid = oid.getId();
        oidGenerico.data = extractedData;
        oidGenerico.initialize();
        return oidGenerico;
    }
    
    /**
     * Extrai dados de qualquer tipo ASN.1 de forma segura
     */
    private static String extractData(ASN1Encodable encodable) {
        if (encodable == null) {
            return "";
        }
        
        try {
            if (encodable instanceof DERTaggedObject) {
                DERTaggedObject tagged = (DERTaggedObject) encodable;
                ASN1Encodable inner = tagged.getObject();
                
                // Recursivamente extrai do conteúdo interno
                if (inner instanceof DERTaggedObject) {
                    // Tagged dentro de tagged - continua recursivo
                    return extractData(inner);
                } else if (inner instanceof DEROctetString) {
                    return new String(((DEROctetString) inner).getOctets(), "UTF-8");
                } else if (inner instanceof DERPrintableString) {
                    return ((DERPrintableString) inner).getString();
                } else if (inner instanceof DERUTF8String) {
                    return ((DERUTF8String) inner).getString();
                } else if (inner instanceof DERIA5String) {
                    return ((DERIA5String) inner).getString();
                } else if (inner instanceof ASN1Sequence) {
                    // Se for sequence, tenta extrair do primeiro elemento
                    ASN1Sequence seq = (ASN1Sequence) inner;
                    if (seq.size() > 0) {
                        return extractData(seq.getObjectAt(0));
                    }
                }
            } else if (encodable instanceof DEROctetString) {
                return new String(((DEROctetString) encodable).getOctets(), "UTF-8");
            } else if (encodable instanceof DERPrintableString) {
                return ((DERPrintableString) encodable).getString();
            } else if (encodable instanceof DERUTF8String) {
                return ((DERUTF8String) encodable).getString();
            } else if (encodable instanceof DERIA5String) {
                return ((DERIA5String) encodable).getString();
            }
        } catch (Exception e) {
            // Se falhar qualquer conversão, retorna string vazia
            return "";
        }
        
        return "";
    }

    public static OIDGeneric getInstance(DerValue der) throws IOException, Exception {
        OIDGeneric oidGenerico;
        OtherName on = new OtherName(der);
        String className = OIDGeneric.getPackageName() + on.getOID().toString().replaceAll("[.]", "_");
        try {
            oidGenerico = (OIDGeneric) Class.forName(className).newInstance();
        } catch (InstantiationException e) {
            throw new Exception(coreMessagesBundle.getString("error.class.instance", className), e);
        } catch (IllegalAccessException e) {
            throw new Exception(coreMessagesBundle.getString("error.class.illegal.access", className), e);
        } catch (ClassNotFoundException e) {
            oidGenerico = new OIDGeneric();
        }
        oidGenerico.oid = on.getOID().toString();
        oidGenerico.data = new String(on.getNameValue()).substring(6);
        oidGenerico.initialize();
        return oidGenerico;
    }

    protected void initialize() {
    }

    protected void initialize(Object[] fields) {
        int tmp = 0;
        for (int i = 0; i < fields.length; i += 2) {
            String key = (String) fields[i];
            int size = (Integer) fields[i + 1];
            this.properties.put(key, this.data.substring(tmp, Math.min(tmp + size, this.data.length())));
            tmp += size;
        }
    }

    public String getOid() {
        return this.oid;
    }

    public String getData() {
        return this.data;
    }

    public static String getPackageName() {
        return packageName;
    }

    static {
        coreMessagesBundle = new MessagesBundle();
    }
}
