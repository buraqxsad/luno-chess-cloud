import com.android.aapt.Resources;
import com.android.bundle.Config;
import com.google.gson.Gson;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.TreeSet;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

// Java 21 source-file launch. Only --self-test writes a temporary synthetic ZIP.
class V217ReleaseBundleVerify {
    static final String ANDROID = "http://schemas.android.com/apk/res/android";
    static final Set<String> ABIS = Set.of("armeabi-v7a", "arm64-v8a", "x86_64");
    static final Set<String> DEFAULT_PERMISSIONS = Set.of(
        "android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE",
        "com.android.vending.BILLING", "com.google.android.providers.gsf.permission.READ_GSERVICES",
        "com.luno.chess.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION");
    static final int PROTO_LIMIT = 4 * 1024 * 1024;
    static final int ELF_PREFIX_LIMIT = 1024 * 1024;

    static final class Rejected extends Exception {
        final String code;
        Rejected(String code) { this.code = code; }
    }

    static void require(boolean condition, String code) throws Rejected {
        if (!condition) throw new Rejected(code);
    }

    static Map<String, Object> map() { return new LinkedHashMap<>(); }

    static byte[] configuredCertificate(Path root) throws Exception {
        Properties properties = new Properties();
        char[] password = null;
        try {
            Path android = root.resolve("android");
            try (InputStream input = Files.newInputStream(android.resolve("key.properties"))) {
                properties.load(input);
            }
            for (String field : List.of("storeFile", "storePassword", "keyAlias", "keyPassword")) {
                require(!properties.getProperty(field, "").isBlank(), "LOCAL_SIGNING_UNAVAILABLE");
            }
            Path store = Path.of(properties.getProperty("storeFile"));
            if (!store.isAbsolute()) store = android.resolve(store);
            password = properties.getProperty("storePassword").toCharArray();
            String alias = properties.getProperty("keyAlias");
            properties.clear();
            KeyStore keys = KeyStore.getInstance(store.toFile(), password);
            require(keys.isKeyEntry(alias), "LOCAL_SIGNING_UNAVAILABLE");
            require(keys.getCertificate(alias) instanceof X509Certificate, "LOCAL_SIGNING_UNAVAILABLE");
            X509Certificate certificate = (X509Certificate) keys.getCertificate(alias);
            certificate.checkValidity();
            return certificate.getEncoded();
        } finally {
            if (password != null) Arrays.fill(password, '\0');
            properties.clear();
        }
    }

    static String fileHash(Path file) throws Exception {
        MessageDigest hash = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[64 * 1024];
        try (InputStream input = Files.newInputStream(file)) {
            int count;
            while ((count = input.read(buffer)) != -1) hash.update(buffer, 0, count);
        }
        return HexFormat.of().formatHex(hash.digest());
    }

    static Map<String, Object> verifyEntries(JarFile jar, byte[] expected) throws Exception {
        int payload = 0;
        int directories = 0;
        int metadata = 0;
        Set<String> names = new HashSet<>();
        var entries = jar.entries();
        while (entries.hasMoreElements()) {
            JarEntry entry = entries.nextElement();
            String name = entry.getName();
            require(names.add(name), "DUPLICATE_ZIP_ENTRY");
            require(!name.startsWith("/") && !name.contains("\\") &&
                Arrays.stream(name.split("/", -1)).noneMatch(p -> p.equals("..") || p.equals(".")),
                "INVALID_ZIP_ENTRY_PATH");
            if (entry.isDirectory()) { directories++; continue; }
            if (name.toUpperCase(java.util.Locale.ROOT).startsWith("META-INF/")) {
                metadata++;
                continue;
            }
            // Signers are populated only after the entire entry has been consumed.
            try (InputStream input = jar.getInputStream(entry)) {
                input.transferTo(OutputStream.nullOutputStream());
            }
            var signers = entry.getCodeSigners();
            require(signers != null && signers.length == 1, "UNSIGNED_OR_MULTISIGNED_PAYLOAD");
            var certificate = signers[0].getSignerCertPath().getCertificates().get(0);
            require(certificate instanceof X509Certificate, "UNSUPPORTED_SIGNER_CERTIFICATE");
            require(MessageDigest.isEqual(expected, certificate.getEncoded()), "UPLOAD_CERTIFICATE_MISMATCH");
            payload++;
        }
        require(payload > 0, "NO_SIGNED_PAYLOAD");
        Map<String, Object> result = map();
        result.put("verifiedPayloadEntries", payload);
        result.put("excludedDirectoryEntries", directories);
        result.put("excludedMetaInfEntries", metadata);
        result.put("everyNonMetaInfPayloadSignatureVerified", true);
        result.put("everyPayloadMatchesConfiguredUploadCertificate", true);
        result.put("signaturePolicy", "JDK21_JarFile_verification_and_disabled_algorithms");
        return result;
    }

    static byte[] boundedEntry(JarFile jar, String name) throws Exception {
        JarEntry entry = jar.getJarEntry(name);
        require(entry != null && !entry.isDirectory(), "REQUIRED_PROTO_ENTRY_MISSING");
        require(entry.getSize() >= 0 && entry.getSize() <= PROTO_LIMIT, "PROTO_ENTRY_TOO_LARGE");
        try (InputStream input = jar.getInputStream(entry)) {
            byte[] bytes = input.readNBytes(PROTO_LIMIT + 1);
            require(bytes.length <= PROTO_LIMIT, "PROTO_ENTRY_TOO_LARGE");
            require(bytes.length == entry.getSize(), "PROTO_ENTRY_SIZE_MISMATCH");
            return bytes;
        }
    }

    static Resources.XmlAttribute attribute(Resources.XmlElement element, String ns, String name)
            throws Exception {
        Resources.XmlAttribute result = null;
        for (var candidate : element.getAttributeList()) {
            if (candidate.getNamespaceUri().equals(ns) && candidate.getName().equals(name)) {
                require(result == null, "DUPLICATE_MANIFEST_ATTRIBUTE");
                result = candidate;
            }
        }
        return result;
    }

    static String value(Resources.XmlAttribute attribute) throws Exception {
        if (attribute == null) return null;
        String raw = attribute.getValue();
        String compiled = null;
        if (attribute.hasCompiledItem()) {
            var item = attribute.getCompiledItem();
            if (item.hasStr()) compiled = item.getStr().getValue();
            else if (item.hasRawStr()) compiled = item.getRawStr().getValue();
            else if (item.hasPrim()) {
                var primitive = item.getPrim();
                if (primitive.hasBooleanValue()) compiled = Boolean.toString(primitive.getBooleanValue());
                else if (primitive.hasIntDecimalValue()) compiled = Integer.toUnsignedString(primitive.getIntDecimalValue());
                else if (primitive.hasIntHexadecimalValue()) compiled = Integer.toUnsignedString(primitive.getIntHexadecimalValue());
            }
            require(compiled != null, "UNRESOLVED_MANIFEST_ATTRIBUTE");
        }
        if (compiled != null) {
            // Decimal integers / booleans may have lexical forms such as 0x11 / 0.
            if (!raw.isEmpty() && !raw.equals(compiled)) {
                boolean equal = false;
                try { equal = Long.decode(raw).longValue() == Long.parseLong(compiled); }
                catch (NumberFormatException ignored) { }
                if (compiled.equals("false") && raw.equals("0")) equal = true;
                if (compiled.equals("true") && (raw.equals("1") || raw.equals("-1"))) equal = true;
                require(equal, "MANIFEST_RAW_COMPILED_MISMATCH");
            }
            return compiled;
        }
        require(!raw.isEmpty(), "EMPTY_MANIFEST_ATTRIBUTE");
        return raw;
    }

    static String attr(Resources.XmlElement element, String ns, String name) throws Exception {
        return value(attribute(element, ns, name));
    }

    static void falseOrAbsent(Resources.XmlElement element, String name) throws Exception {
        String value = attr(element, ANDROID, name);
        require(value == null || value.equals("false") || value.equals("0"), "UNSAFE_APPLICATION_" + name.toUpperCase(java.util.Locale.ROOT));
    }

    static Map<String, Object> manifest(byte[] bytes, Set<String> allowed) throws Exception {
        return manifest(bytes, allowed, map());
    }

    static Map<String, Object> manifest(byte[] bytes, Set<String> allowed, Map<String, Object> result) throws Exception {
        return manifest(bytes, allowed, result, 17);
    }

    static Map<String, Object> manifest(byte[] bytes, Set<String> allowed, Map<String, Object> result, int expectedBuild) throws Exception {
        Resources.XmlNode node = Resources.XmlNode.parseFrom(bytes);
        require(node.hasElement(), "MANIFEST_ROOT_MISSING");
        var root = node.getElement();
        require(root.getName().equals("manifest") && root.getNamespaceUri().isEmpty(), "MANIFEST_ROOT_INVALID");
        require("com.luno.chess".equals(attr(root, "", "package")), "APPLICATION_ID_MISMATCH");
        require("1.6.3".equals(attr(root, ANDROID, "versionName")), "VERSION_NAME_MISMATCH");
        require(Integer.toString(expectedBuild).equals(attr(root, ANDROID, "versionCode")), "VERSION_CODE_MISMATCH");
        String major = attr(root, ANDROID, "versionCodeMajor");
        require(major == null || major.equals("0"), "VERSION_CODE_MAJOR_MISMATCH");
        Resources.XmlElement sdk = null;
        Resources.XmlElement application = null;
        Set<String> permissions = new TreeSet<>();
        for (var child : root.getChildList()) {
            if (!child.hasElement()) continue;
            var element = child.getElement();
            require(element.getNamespaceUri().isEmpty(), "UNEXPECTED_MANIFEST_ELEMENT_NAMESPACE");
            switch (element.getName()) {
                case "uses-sdk" -> { require(sdk == null, "DUPLICATE_USES_SDK"); sdk = element; }
                case "application" -> { require(application == null, "DUPLICATE_APPLICATION"); application = element; }
                case "uses-permission", "uses-permission-sdk-23", "uses-permission-sdk-m" -> {
                    String name = attr(element, ANDROID, "name");
                    require(name != null && permissions.add(name), "INVALID_OR_DUPLICATE_PERMISSION");
                    require(attribute(element, ANDROID, "maxSdkVersion") == null, "CAPPED_PERMISSION_REQUIRES_REVIEW");
                }
                default -> { }
            }
        }
        require(sdk != null && application != null, "SDK_OR_APPLICATION_MISSING");
        require("24".equals(attr(sdk, ANDROID, "minSdkVersion")), "MIN_SDK_MISMATCH");
        require("36".equals(attr(sdk, ANDROID, "targetSdkVersion")), "TARGET_SDK_MISMATCH");
        result.put("permissions", permissions);
        result.put("allowedPermissions", new TreeSet<>(allowed));
        Set<String> unreviewed = new TreeSet<>(permissions);
        unreviewed.removeAll(allowed);
        result.put("unreviewedPermissions", unreviewed);
        require(permissions.containsAll(Set.of("android.permission.INTERNET", "com.android.vending.BILLING")), "REQUIRED_PERMISSION_MISSING");
        require(allowed.containsAll(permissions), "UNREVIEWED_PERMISSION");
        falseOrAbsent(application, "debuggable");
        falseOrAbsent(application, "testOnly");
        falseOrAbsent(application, "usesCleartextTraffic");
        require(attribute(application, ANDROID, "networkSecurityConfig") == null,
            "NETWORK_SECURITY_CONFIG_REQUIRES_SEPARATE_REVIEW");
        result.put("applicationId", "com.luno.chess");
        result.put("versionName", "1.6.3");
        result.put("versionCode", expectedBuild);
        result.put("minSdk", 24);
        result.put("targetSdk", 36);
        result.put("permissions", permissions);
        result.put("allowedPermissions", new TreeSet<>(allowed));
        result.put("debuggable", false);
        result.put("testOnly", false);
        result.put("cleartextTrafficPermitted", false);
        result.put("cleartextBasis", "false_or_absent_with_target_36_and_no_network_security_config");
        return result;
    }

    static Map<String, Object> bundleConfig(byte[] bytes) throws Exception {
        var config = Config.BundleConfig.parseFrom(bytes);
        require(config.hasOptimizations() && config.getOptimizations().hasUncompressNativeLibraries(),
            "BUNDLE_PAGE_ALIGNMENT_UNSPECIFIED");
        var nativeConfig = config.getOptimizations().getUncompressNativeLibraries();
        require(nativeConfig.getEnabled(), "BUNDLE_NATIVE_UNCOMPRESSION_DISABLED");
        require(nativeConfig.getAlignment() == Config.UncompressNativeLibraries.PageAlignment.PAGE_ALIGNMENT_16K ||
            nativeConfig.getAlignment() == Config.UncompressNativeLibraries.PageAlignment.PAGE_ALIGNMENT_64K,
            "BUNDLE_PAGE_ALIGNMENT_BELOW_16K_OR_UNKNOWN");
        Map<String, Object> result = map();
        result.put("uncompressNativeLibraries", true);
        result.put("pageAlignment", nativeConfig.getAlignment().name());
        result.put("bundletoolVersion", config.getBundletool().getVersion());
        result.put("apkZipAlignmentVerified", false);
        return result;
    }

    static long unsigned32(ByteBuffer buffer, int offset) { return Integer.toUnsignedLong(buffer.getInt(offset)); }

    static Map<String, Object> elf(InputStream input, long fileSize, String abi) throws Exception {
        byte[] header = input.readNBytes(64);
        require(header.length == 64 && header[0] == 0x7f && header[1] == 'E' && header[2] == 'L' && header[3] == 'F', "INVALID_ELF_HEADER");
        int elfClass = Byte.toUnsignedInt(header[4]);
        boolean is64 = abi.equals("arm64-v8a") || abi.equals("x86_64");
        require(ABIS.contains(abi) && elfClass == (is64 ? 2 : 1) && header[5] == 1 && header[6] == 1,
            "ELF_CLASS_ENDIAN_OR_VERSION_MISMATCH");
        ByteBuffer h = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
        int machine = Short.toUnsignedInt(h.getShort(18));
        require(machine == (abi.equals("arm64-v8a") ? 183 : abi.equals("x86_64") ? 62 : 40), "ELF_MACHINE_ABI_MISMATCH");
        require(h.getShort(16) == 3 && h.getInt(20) == 1, "ELF_NOT_SHARED_OBJECT");
        long phoff = is64 ? h.getLong(32) : unsigned32(h, 28);
        int entrySize = Short.toUnsignedInt(h.getShort(is64 ? 54 : 42));
        int count = Short.toUnsignedInt(h.getShort(is64 ? 56 : 44));
        require(entrySize == (is64 ? 56 : 32) && count > 0 && count != 65535, "INVALID_ELF_PROGRAM_HEADER_LAYOUT");
        long end = phoff + (long) entrySize * count;
        require(phoff >= (is64 ? 64 : 52) && end >= phoff && end <= ELF_PREFIX_LIMIT && end <= fileSize,
            "ELF_PROGRAM_HEADERS_OUT_OF_BOUNDS");
        byte[] prefix = Arrays.copyOf(header, (int) end);
        if (end > header.length) {
            byte[] rest = input.readNBytes((int) end - header.length);
            require(rest.length == end - header.length, "TRUNCATED_ELF_PROGRAM_HEADERS");
            System.arraycopy(rest, 0, prefix, header.length, rest.length);
        }
        ByteBuffer table = ByteBuffer.wrap(prefix).order(ByteOrder.LITTLE_ENDIAN);
        long minimum = Long.MAX_VALUE;
        int loads = 0;
        for (int i = 0; i < count; i++) {
            int p = (int) phoff + i * entrySize;
            if (table.getInt(p) != 1) continue;
            long offset = is64 ? table.getLong(p + 8) : unsigned32(table, p + 4);
            long address = is64 ? table.getLong(p + 16) : unsigned32(table, p + 8);
            long filesz = is64 ? table.getLong(p + 32) : unsigned32(table, p + 16);
            long memsz = is64 ? table.getLong(p + 40) : unsigned32(table, p + 20);
            long align = is64 ? table.getLong(p + 48) : unsigned32(table, p + 28);
            require(offset >= 0 && address >= 0 && filesz >= 0 && memsz >= filesz &&
                offset <= fileSize && filesz <= fileSize - offset, "ELF_LOAD_OUT_OF_BOUNDS");
            require(align >= 0 && (align <= 1 || (align & (align - 1)) == 0), "ELF_LOAD_ALIGNMENT_NOT_POWER_OF_TWO");
            require(align <= 1 || offset % align == address % align, "ELF_LOAD_OFFSET_ADDRESS_NOT_CONGRUENT");
            require(!is64 || align >= 16384, "ELF64_LOAD_ALIGNMENT_BELOW_16K");
            minimum = Math.min(minimum, align);
            loads++;
        }
        require(loads > 0, "ELF_HAS_NO_LOAD_SEGMENTS");
        Map<String, Object> result = map();
        result.put("abi", abi);
        result.put("elfBits", is64 ? 64 : 32);
        result.put("loadSegments", loads);
        result.put("minimumLoadAlignmentBytes", minimum);
        result.put("requires16KbAlignment", is64);
        return result;
    }

    static List<Map<String, Object>> nativeLibraries(JarFile jar) throws Exception {
        List<Map<String, Object>> results = new ArrayList<>();
        Set<String> abis = new TreeSet<>();
        var entries = jar.entries();
        while (entries.hasMoreElements()) {
            var entry = entries.nextElement();
            if (entry.isDirectory() || !entry.getName().contains("/lib/")) continue;
            require(entry.getName().matches("[A-Za-z0-9._-]+/lib/[A-Za-z0-9_-]+/[A-Za-z0-9._-]+\\.so"), "UNEXPECTED_NATIVE_ENTRY_LAYOUT");
            String abi = entry.getName().split("/")[2];
            Map<String, Object> result;
            try (InputStream input = jar.getInputStream(entry)) { result = elf(input, entry.getSize(), abi); }
            result.put("entry", entry.getName());
            results.add(result);
            abis.add(abi);
        }
        require(abis.equals(ABIS), "EXPECTED_ALL_ABI_SET_MISSING_OR_EXTRA");
        return results;
    }

    static void verify(Path root, Path bundle, Set<String> allowed, Map<String, Object> report) throws Exception {
        require(Files.isRegularFile(bundle) && bundle.getFileName().toString().endsWith(".aab"), "AAB_NOT_FOUND");
        long size = Files.size(bundle);
        var modified = Files.getLastModifiedTime(bundle);
        String before = fileHash(bundle);
        report.put("bundleSha256", before);
        report.put("bundleSizeBytes", size);
        report.put("stage", "local_upload_certificate");
        byte[] certificate = configuredCertificate(root);
        try (JarFile jar = new JarFile(bundle.toFile(), true)) {
            report.put("stage", "every_payload_signature");
            report.put("signatures", verifyEntries(jar, certificate));
            report.put("stage", "merged_manifest");
            Map<String, Object> manifestReport = map();
            report.put("manifest", manifestReport);
            int expectedBuild = Integer.getInteger("luno.expectedBuild", 17);
            require(expectedBuild > 0 && expectedBuild <= 2100000000, "INVALID_EXPECTED_BUILD");
            manifest(boundedEntry(jar, "base/manifest/AndroidManifest.xml"), allowed, manifestReport, expectedBuild);
            // Extra modules would need their own manifest review; do not silently inspect base only.
            var entries = jar.entries();
            while (entries.hasMoreElements()) {
                String name = entries.nextElement().getName();
                require(!name.endsWith("/manifest/AndroidManifest.xml") || name.equals("base/manifest/AndroidManifest.xml"),
                    "ADDITIONAL_MODULE_MANIFEST_REQUIRES_REVIEW");
            }
            report.put("stage", "bundle_config");
            report.put("bundleConfig", bundleConfig(boundedEntry(jar, "BundleConfig.pb")));
            report.put("stage", "native_elf_load_alignment");
            report.put("nativeLibraries", nativeLibraries(jar));
        } finally { Arrays.fill(certificate, (byte) 0); }
        report.put("stage", "artifact_stability");
        require(Files.size(bundle) == size && Files.getLastModifiedTime(bundle).equals(modified) && fileHash(bundle).equals(before),
            "AAB_CHANGED_DURING_VERIFICATION");
        report.put("artifactStable", true);
        report.put("stage", "complete");
        report.put("passed", true);
        report.put("assetAuditIncluded", false);
        report.put("deviceOrPlayAcceptanceIncluded", false);
    }

    static Resources.XmlAttribute raw(String namespace, String name, String value) {
        return Resources.XmlAttribute.newBuilder().setNamespaceUri(namespace).setName(name).setValue(value).build();
    }

    static byte[] syntheticManifest(String version, String debug, String permission) {
        var sdk = Resources.XmlElement.newBuilder().setName("uses-sdk")
            .addAttribute(raw(ANDROID, "minSdkVersion", "24")).addAttribute(raw(ANDROID, "targetSdkVersion", "36"));
        var app = Resources.XmlElement.newBuilder().setName("application");
        if (debug != null) app.addAttribute(raw(ANDROID, "debuggable", debug));
        var root = Resources.XmlElement.newBuilder().setName("manifest")
            .addAttribute(raw("", "package", "com.luno.chess"))
            .addAttribute(raw(ANDROID, "versionName", "1.6.3"))
            .addAttribute(raw(ANDROID, "versionCode", version))
            .addChild(Resources.XmlNode.newBuilder().setElement(sdk))
            .addChild(Resources.XmlNode.newBuilder().setElement(app));
        for (String name : List.of("android.permission.INTERNET", "com.android.vending.BILLING", permission)) {
            if (name.isEmpty()) continue;
            root.addChild(Resources.XmlNode.newBuilder().setElement(Resources.XmlElement.newBuilder().setName("uses-permission")
                .addAttribute(raw(ANDROID, "name", name))));
        }
        return Resources.XmlNode.newBuilder().setElement(root).build().toByteArray();
    }

    static byte[] syntheticElf(long alignment) {
        ByteBuffer b = ByteBuffer.allocate(120).order(ByteOrder.LITTLE_ENDIAN);
        b.put(0, (byte) 0x7f).put(1, (byte) 'E').put(2, (byte) 'L').put(3, (byte) 'F');
        b.put(4, (byte) 2).put(5, (byte) 1).put(6, (byte) 1);
        b.putShort(16, (short) 3).putShort(18, (short) 183).putInt(20, 1);
        b.putLong(32, 64).putShort(54, (short) 56).putShort(56, (short) 1);
        b.putInt(64, 1).putLong(96, 120).putLong(104, 120).putLong(112, alignment);
        return b.array();
    }

    static byte[] syntheticApplicationAttribute(String name, String value) throws Exception {
        var root = Resources.XmlNode.parseFrom(syntheticManifest("17", null, "")).getElement();
        var changed = root.toBuilder().clearChild();
        for (var child : root.getChildList()) {
            if (child.hasElement() && child.getElement().getName().equals("application")) {
                changed.addChild(child.toBuilder().setElement(child.getElement().toBuilder().addAttribute(raw(ANDROID, name, value))));
            } else changed.addChild(child);
        }
        return Resources.XmlNode.newBuilder().setElement(changed).build().toByteArray();
    }

    interface Check { void run() throws Exception; }

    static void test(List<Map<String, Object>> results, String name, String expectedFailure, Check check) throws Exception {
        String observed = null;
        try { check.run(); } catch (Rejected failure) { observed = failure.code; }
        require(java.util.Objects.equals(expectedFailure, observed), "SYNTHETIC_TEST_FAILED");
        Map<String, Object> result = map();
        result.put("name", name);
        result.put("passed", true);
        if (observed != null) result.put("expectedRejection", observed);
        results.add(result);
    }

    static void selfTest(Path root, Map<String, Object> report) throws Exception {
        List<Map<String, Object>> tests = new ArrayList<>();
        report.put("syntheticTests", tests);
        test(tests, "manifest_expected", null, () -> manifest(syntheticManifest("17", null, ""), DEFAULT_PERMISSIONS));
        test(tests, "manifest_wrong_version", "VERSION_CODE_MISMATCH", () -> manifest(syntheticManifest("18", null, ""), DEFAULT_PERMISSIONS));
        test(tests, "manifest_explicit_build", null, () -> manifest(syntheticManifest("18", null, ""), DEFAULT_PERMISSIONS, map(), 18));
        test(tests, "manifest_explicit_build_rejects_old", "VERSION_CODE_MISMATCH", () -> manifest(syntheticManifest("17", null, ""), DEFAULT_PERMISSIONS, map(), 18));
        test(tests, "manifest_debuggable", "UNSAFE_APPLICATION_DEBUGGABLE", () -> manifest(syntheticManifest("17", "true", ""), DEFAULT_PERMISSIONS));
        test(tests, "manifest_unreviewed_camera", "UNREVIEWED_PERMISSION", () -> manifest(syntheticManifest("17", null, "android.permission.CAMERA"), DEFAULT_PERMISSIONS));
        test(tests, "manifest_cleartext_enabled", "UNSAFE_APPLICATION_USESCLEARTEXTTRAFFIC", () -> manifest(syntheticApplicationAttribute("usesCleartextTraffic", "true"), DEFAULT_PERMISSIONS));
        test(tests, "manifest_cleartext_false", null, () -> manifest(syntheticApplicationAttribute("usesCleartextTraffic", "false"), DEFAULT_PERMISSIONS));
        test(tests, "manifest_network_security_unresolved", "NETWORK_SECURITY_CONFIG_REQUIRES_SEPARATE_REVIEW", () -> manifest(syntheticApplicationAttribute("networkSecurityConfig", "@xml/network_policy"), DEFAULT_PERMISSIONS));
        test(tests, "elf64_16k", null, () -> elf(new ByteArrayInputStream(syntheticElf(16384)), 120, "arm64-v8a"));
        test(tests, "elf64_4k", "ELF64_LOAD_ALIGNMENT_BELOW_16K", () -> elf(new ByteArrayInputStream(syntheticElf(4096)), 120, "arm64-v8a"));
        test(tests, "elf64_non_power_of_two", "ELF_LOAD_ALIGNMENT_NOT_POWER_OF_TWO", () -> elf(new ByteArrayInputStream(syntheticElf(24576)), 120, "arm64-v8a"));
        test(tests, "elf_truncated", "INVALID_ELF_HEADER", () -> elf(new ByteArrayInputStream(new byte[12]), 12, "arm64-v8a"));
        test(tests, "elf_abi_mismatch", "ELF_MACHINE_ABI_MISMATCH", () -> elf(new ByteArrayInputStream(syntheticElf(16384)), 120, "x86_64"));
        test(tests, "bundle_config_missing_alignment", "BUNDLE_PAGE_ALIGNMENT_UNSPECIFIED", () -> bundleConfig(new byte[0]));
        var nativeConfig = Config.UncompressNativeLibraries.newBuilder().setEnabled(true)
            .setAlignment(Config.UncompressNativeLibraries.PageAlignment.PAGE_ALIGNMENT_16K);
        byte[] config = Config.BundleConfig.newBuilder().setOptimizations(Config.Optimizations.newBuilder()
            .setUncompressNativeLibraries(nativeConfig)).build().toByteArray();
        test(tests, "bundle_config_16k", null, () -> bundleConfig(config));
        byte[] config4k = Config.BundleConfig.newBuilder().setOptimizations(Config.Optimizations.newBuilder()
            .setUncompressNativeLibraries(nativeConfig.setAlignment(Config.UncompressNativeLibraries.PageAlignment.PAGE_ALIGNMENT_4K)))
            .build().toByteArray();
        test(tests, "bundle_config_4k", "BUNDLE_PAGE_ALIGNMENT_BELOW_16K_OR_UNKNOWN", () -> bundleConfig(config4k));
        // No keystore creation or real signing: the end-to-end signature test is unsigned only.
        Path qa = root.resolve("qa/v217").toRealPath();
        require(qa.startsWith(root.toRealPath()), "SYNTHETIC_OUTPUT_OUTSIDE_QA");
        Path zip = Files.createTempFile(qa, "release-bundle-helper-synthetic-", ".aab");
        try {
            for (String entry : List.of("base/manifest/AndroidManifest.xml",
                    "base/root/META-INF/com/android/build/gradle/app-metadata.properties", "META-INF/unsigned-note.txt")) {
                try (ZipOutputStream output = new ZipOutputStream(Files.newOutputStream(zip))) {
                    output.putNextEntry(new ZipEntry(entry));
                    output.write(syntheticManifest("17", null, ""));
                    output.closeEntry();
                }
                boolean topMetadata = entry.startsWith("META-INF/");
                String name = topMetadata ? "top_level_metadata_is_not_signed_payload" :
                    entry.startsWith("base/root/") ? "nested_meta_inf_is_not_exempt" : "unsigned_payload";
                test(tests, name, topMetadata ? "NO_SIGNED_PAYLOAD" : "UNSIGNED_OR_MULTISIGNED_PAYLOAD", () -> {
                    try (JarFile jar = new JarFile(zip.toFile(), true)) { verifyEntries(jar, new byte[0]); }
                });
            }
        } finally { Files.deleteIfExists(zip); }
        report.put("stage", "synthetic_complete");
        report.put("passed", true);
        report.put("actualAabInspected", false);
        report.put("realSigningMaterialRead", false);
    }

    public static void main(String[] args) {
        Map<String, Object> report = map();
        report.put("schemaVersion", 1);
        report.put("passed", false);
        report.put("stage", "arguments");
        int status = 2;
        try {
            require(args.length >= 2, "INVALID_ARGUMENTS");
            Path root = Path.of(args[1]).toAbsolutePath().normalize();
            if (args[0].equals("--self-test")) {
                require(args.length == 2, "INVALID_ARGUMENTS");
                selfTest(root, report);
            } else {
                require(args[0].equals("--parent-final-build-complete") && args.length >= 3, "PARENT_COMPLETION_REQUIRED");
                Set<String> allowed = args.length == 3 ? DEFAULT_PERMISSIONS : new HashSet<>(Arrays.asList(args).subList(3, args.length));
                verify(root, Path.of(args[2]).toAbsolutePath().normalize(), allowed, report);
            }
            status = 0;
        } catch (Rejected failure) {
            report.put("errorCode", failure.code);
        } catch (SecurityException ignored) {
            report.put("errorCode", "JAR_SIGNATURE_OR_SECURITY_FAILURE");
        } catch (Exception | LinkageError ignored) {
            // Exception details can expose local signing metadata; never emit them.
            report.put("errorCode", "VERIFIER_PREREQUISITE_OR_PARSE_FAILURE_DETAILS_WITHHELD");
            status = 1;
        }
        System.out.println(new Gson().toJson(report));
        if (status != 0) System.exit(status);
    }
}
