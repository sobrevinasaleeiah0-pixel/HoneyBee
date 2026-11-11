import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export function decodeEncryptionKey(value) {
  const key = Buffer.from(value, "base64url");
  if (key.length !== 32) {
    throw new Error("OTP_OUTBOX_ENCRYPTION_KEY must decode to 32 bytes");
  }
  return key;
}

export function encryptPayload(value, key) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(value, "utf8"),
    cipher.final(),
  ]);
  return [
    iv.toString("base64url"),
    cipher.getAuthTag().toString("base64url"),
    ciphertext.toString("base64url"),
  ].join(".");
}

export function decryptPayload(payload, key) {
  const [encodedIv, encodedTag, encodedCiphertext] = payload.split(".");
  if (!encodedIv || !encodedTag || !encodedCiphertext) {
    throw new Error("Malformed encrypted outbox payload");
  }
  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    Buffer.from(encodedIv, "base64url"),
  );
  decipher.setAuthTag(Buffer.from(encodedTag, "base64url"));
  return Buffer.concat([
    decipher.update(Buffer.from(encodedCiphertext, "base64url")),
    decipher.final(),
  ]).toString("utf8");
}
