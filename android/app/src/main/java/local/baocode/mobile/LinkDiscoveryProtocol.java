package local.baocode.mobile;

final class LinkDiscoveryProtocol {
    private LinkDiscoveryProtocol() {}

    static String deviceId(String version, byte[] publicKey) {
        if (!"2".equals(version) || publicKey == null || publicKey.length != 32) return null;
        char[] digits = "0123456789abcdef".toCharArray();
        char[] id = new char[64];
        for (int i = 0; i < publicKey.length; i++) {
            int value = publicKey[i] & 0xff;
            id[i * 2] = digits[value >>> 4];
            id[i * 2 + 1] = digits[value & 0xf];
        }
        return new String(id);
    }
}
