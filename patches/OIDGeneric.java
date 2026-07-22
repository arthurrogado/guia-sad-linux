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
        
        ASN1ObjectIdentifier oid;
        DERTaggedObject taggedObject;
        
        // Certificados ICP-Brasil modernos podem usar DERTaggedObject em vez de DLSequence
        if (obj instanceof DLSequence) {
            DLSequence sequence = (DLSequence) obj;
            oid = (ASN1ObjectIdentifier) sequence.getObjectAt(0);
            taggedObject = (DERTaggedObject) sequence.getObjectAt(1);
        } else if (obj instanceof DERTaggedObject) {
            // Formato moderno: tagged object direto
            taggedObject = (DERTaggedObject) obj;
            // Extrai o OID do conteúdo do tagged object
            ASN1Encodable content = taggedObject.getObject();
            if (content instanceof ASN1Sequence) {
                ASN1Sequence seq = (ASN1Sequence) content;
                oid = (ASN1ObjectIdentifier) seq.getObjectAt(0);
                taggedObject = (DERTaggedObject) seq.getObjectAt(1);
            } else {
                // Não conseguiu extrair, usa valores padrão
                oid = new ASN1ObjectIdentifier("0.0.0");
            }
        } else {
            throw new Exception("Formato ASN.1 não suportado: " + obj.getClass().getName());
        }
        
        DERTaggedObject taggedObject2 = (DERTaggedObject) taggedObject.getObject();
        DEROctetString octet = null;
        DERPrintableString print = null;
        DERUTF8String utf8 = null;
        DERIA5String ia5 = null;
        
        try {
            octet = (DEROctetString) taggedObject2.getObject();
        } catch (Exception e) {
            try {
                print = (DERPrintableString) taggedObject2.getObject();
            } catch (Exception e1) {
                try {
                    utf8 = (DERUTF8String) taggedObject2.getObject();
                } catch (Exception e2) {
                    ia5 = (DERIA5String) taggedObject2.getObject();
                }
            }
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
        oidGenerico.data = octet != null ? new String(octet.getOctets()) 
                         : (print != null ? print.getString() 
                         : (utf8 != null ? utf8.getString() : (ia5 != null ? ia5.getString() : "")));
        oidGenerico.initialize();
        return oidGenerico;
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
