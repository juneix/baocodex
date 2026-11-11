package local.baocode.mobile;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.util.UUID;

final class ChatClipboardRecord {
    static final int MAX_PAYLOAD_BYTES = 32 * 1024 * 1024;
    static final int MAX_RECORD_BYTES = MAX_PAYLOAD_BYTES + 46;
    private static final int MAGIC = 0x42434c31;

    final String token;
    final byte[] payload;

    private ChatClipboardRecord(String token, byte[] payload) {
        this.token = token;
        this.payload = payload;
    }

    static byte[] encode(String token, byte[] payload) throws IOException {
        requireToken(token);
        if (payload.length == 0 || payload.length > MAX_PAYLOAD_BYTES) {
            throw new IOException("剪贴板数据大小无效");
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(payload.length + 46);
        try (DataOutputStream output = new DataOutputStream(bytes)) {
            output.writeInt(MAGIC);
            output.writeUTF(token);
            output.writeInt(payload.length);
            output.write(payload);
        }
        return bytes.toByteArray();
    }

    static ChatClipboardRecord decode(byte[] encoded) throws IOException {
        if (encoded.length > MAX_RECORD_BYTES) {
            throw new IOException("剪贴板数据大小无效");
        }
        try (DataInputStream input = new DataInputStream(new ByteArrayInputStream(encoded))) {
            if (input.readInt() != MAGIC) throw new IOException("剪贴板记录无效");
            String token = input.readUTF();
            requireToken(token);
            int size = input.readInt();
            if (size <= 0 || size > MAX_PAYLOAD_BYTES || size != input.available()) {
                throw new IOException("剪贴板记录不完整");
            }
            byte[] payload = new byte[size];
            input.readFully(payload);
            return new ChatClipboardRecord(token, payload);
        }
    }

    private static void requireToken(String token) {
        if (token == null || token.length() != 36 ||
                !UUID.fromString(token).toString().equals(token)) {
            throw new IllegalArgumentException("剪贴板标记无效");
        }
    }
}
