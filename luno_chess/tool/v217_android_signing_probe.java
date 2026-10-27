import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.Properties;
import java.util.jar.JarFile;

// Source-file launch with Java 17+: no Gradle, key generation, or key writes.
class V217AndroidSigningProbe {
    private static String digest(X509Certificate certificate, String algorithm) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance(algorithm).digest(certificate.getEncoded()));
    }

    public static void main(String[] args) {
        char[] storePassword = null;
        char[] keyPassword = null;
        Properties properties = new Properties();
        int status = 0;
        try {
            Path android = Path.of(args[0]).toAbsolutePath().resolve("android");
            try (InputStream input = Files.newInputStream(android.resolve("key.properties"))) {
                properties.load(input);
            }
            for (String name : new String[]{"storeFile", "storePassword", "keyAlias", "keyPassword"}) {
                if (properties.getProperty(name, "").isBlank()) throw new IllegalStateException();
            }
            Path store = Path.of(properties.getProperty("storeFile"));
            if (!store.isAbsolute()) store = android.resolve(store);
            storePassword = properties.getProperty("storePassword").toCharArray();
            keyPassword = properties.getProperty("keyPassword").toCharArray();
            KeyStore keyStore = KeyStore.getInstance(store.toFile(), storePassword);
            String alias = properties.getProperty("keyAlias");
            PrivateKey key = (PrivateKey) keyStore.getKey(alias, keyPassword);
            X509Certificate certificate = (X509Certificate) keyStore.getCertificate(alias);
            certificate.checkValidity();
            String algorithm = switch (key.getAlgorithm()) {
                case "RSA" -> "SHA256withRSA";
                case "EC" -> "SHA256withECDSA";
                case "DSA" -> "SHA256withDSA";
                default -> throw new IllegalStateException();
            };
            byte[] challenge = "luno-v217-read-only-key-pair-probe".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
            Signature signature = Signature.getInstance(algorithm);
            signature.initSign(key);
            signature.update(challenge);
            byte[] signed = signature.sign();
            signature.initVerify(certificate.getPublicKey());
            signature.update(challenge);
            if (!signature.verify(signed)) throw new IllegalStateException();
            String localDigest = digest(certificate, "SHA-256");
            StringBuilder bundles = new StringBuilder();
            boolean allMatch = true;
            for (int i = 1; i < args.length; i++) {
                boolean verified = false;
                boolean matches = false;
                try (JarFile jar = new JarFile(Path.of(args[i]).toFile(), true)) {
                    var entry = jar.getJarEntry("base/manifest/AndroidManifest.xml");
                    if (entry == null) entry = jar.getJarEntry("manifest/AndroidManifest.xml");
                    if (entry == null) throw new IllegalStateException();
                    try (InputStream input = jar.getInputStream(entry)) {
                        input.transferTo(java.io.OutputStream.nullOutputStream());
                    }
                    var signers = entry.getCodeSigners();
                    if (signers != null && signers.length == 1) {
                        var signer = (X509Certificate) signers[0].getSignerCertPath().getCertificates().get(0);
                        verified = true;
                        matches = localDigest.equals(digest(signer, "SHA-256"));
                    }
                } catch (Exception ignored) {
                    // Never print exception messages: providers may include local key metadata.
                }
                if (i > 1) bundles.append(',');
                bundles.append("{\"argumentIndex\":").append(i)
                    .append(",\"sampledEntrySignatureVerified\":").append(verified)
                    .append(",\"matchesLocalUploadCertificate\":").append(matches).append('}');
                allMatch &= verified && matches;
            }
            System.out.println("{\"localSigningUsable\":true,\"certificateCurrentlyValid\":true,"
                + "\"publicCertificateSha1\":\"" + digest(certificate, "SHA-1") + "\","
                + "\"historicalBundles\":[" + bundles + "],\"allHistoricalCertificatesMatch\":" + allMatch + "}");
            if (!allMatch) status = 2;
        } catch (Exception ignored) {
            System.out.println("{\"localSigningUsable\":false,\"error\":\"Local signing probe failed; values and exception details withheld.\"}");
            status = 1;
        } finally {
            if (storePassword != null) Arrays.fill(storePassword, '\0');
            if (keyPassword != null) Arrays.fill(keyPassword, '\0');
            properties.clear();
        }
        if (status != 0) System.exit(status);
    }
}
