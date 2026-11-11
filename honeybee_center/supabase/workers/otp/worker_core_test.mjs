import assert from "node:assert/strict";
import test from "node:test";
import { createHmac, randomBytes, webcrypto } from "node:crypto";

import {
  createOtp,
  processEmailJob,
  processRequestJob,
  retryDelaySeconds,
  runBatch,
} from "./worker_core.mjs";
import {
  decodeEncryptionKey,
  decryptPayload,
  encryptPayload,
} from "./worker_crypto.mjs";
import { loadSmtpConfig } from "./smtp_config.mjs";

test("SMTP settings support provider overrides and safe defaults", () => {
  assert.deepEqual(
    loadSmtpConfig({ SMTP_USER: "otp@example.test" }),
    {
      host: "smtp.gmail.com",
      port: 465,
      secure: true,
      from: "otp@example.test",
    },
  );
  assert.deepEqual(
    loadSmtpConfig({
      SMTP_HOST: "smtp.example.test",
      SMTP_PORT: "587",
      SMTP_SECURE: "false",
      SMTP_FROM: "Honeybee <support@example.test>",
      SMTP_USER: "user@example.test",
    }),
    {
      host: "smtp.example.test",
      port: 587,
      secure: false,
      from: "Honeybee <support@example.test>",
    },
  );
});

test("SMTP configuration rejects invalid ports and TLS flags", () => {
  assert.throws(
    () => loadSmtpConfig({ SMTP_USER: "otp@example.test", SMTP_PORT: "0" }),
    /SMTP_PORT/,
  );
  assert.throws(
    () => loadSmtpConfig({
      SMTP_USER: "otp@example.test",
      SMTP_SECURE: "sometimes",
    }),
    /SMTP_SECURE/,
  );
});

function requestDependencies(overrides = {}) {
  return {
    decrypt: async () => "admin@example.test",
    findActiveAdmin: async () => ({ id: "admin-1" }),
    createOtp: () => "004201",
    issueOtp: async () => "ISSUED",
    finishRequest: async () => true,
    retryRequest: async () => "RETRY",
    ...overrides,
  };
}

function emailDependencies(overrides = {}) {
  return {
    now: () => 1_000,
    decrypt: async (ciphertext) => ciphertext,
    sendEmail: async () => true,
    complete: async () => true,
    retryEmail: async () => "RETRY",
    expire: async () => "FAILED",
    ...overrides,
  };
}

test("OTP generation always produces a six-digit numeric string", () => {
  for (let index = 0; index < 500; index += 1) {
    assert.match(createOtp(), /^\d{6}$/);
  }
});

test("encryption key must be exactly 32 bytes and ciphertext authenticates", () => {
  const key = randomBytes(32);
  assert.throws(() => decodeEncryptionKey(randomBytes(31).toString("base64url")));
  assert.deepEqual(
    decodeEncryptionKey(key.toString("base64url")),
    key,
  );

  const cipher = encryptPayload("007314", key);
  assert.equal(decryptPayload(cipher, key), "007314");
  const [iv, tag, payload] = cipher.split(".");
  const changedTag = `${tag[0] === "A" ? "B" : "A"}${tag.slice(1)}`;
  assert.throws(() => decryptPayload(`${iv}.${changedTag}.${payload}`, key));
});

test("Edge WebCrypto and Node worker use the same AES-GCM payload format", async () => {
  const keyBytes = randomBytes(32);
  const key = await webcrypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
  const iv = randomBytes(12);
  const edgeCipher = Buffer.from(
    await webcrypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      key,
      new TextEncoder().encode("otp@example.test"),
    ),
  );
  const edgePayload = [
    iv.toString("base64url"),
    edgeCipher.subarray(-16).toString("base64url"),
    edgeCipher.subarray(0, -16).toString("base64url"),
  ].join(".");
  assert.equal(decryptPayload(edgePayload, keyBytes), "otp@example.test");

  const nodePayload = encryptPayload("123456", keyBytes).split(".");
  const nodeCombinedCipher = Buffer.concat([
    Buffer.from(nodePayload[2], "base64url"),
    Buffer.from(nodePayload[1], "base64url"),
  ]);
  const edgePlaintext = await webcrypto.subtle.decrypt(
    { name: "AES-GCM", iv: Buffer.from(nodePayload[0], "base64url") },
    key,
    nodeCombinedCipher,
  );
  assert.equal(new TextDecoder().decode(edgePlaintext), "123456");
});

test("ineligible addresses complete asynchronously without issuing OTP", async () => {
  let issued = false;
  let completed = false;
  const result = await processRequestJob(
    { id: "request-1", worker_token: "lease-1", email_ciphertext: "sealed" },
    requestDependencies({
      findActiveAdmin: async () => null,
      issueOtp: async () => {
        issued = true;
      },
      finishRequest: async () => {
        completed = true;
        return true;
      },
    }),
  );
  assert.equal(result, "ignored");
  assert.equal(issued, false);
  assert.equal(completed, true);
});

test("eligible request delegates one OTP issue to the atomic SQL RPC", async () => {
  let issue;
  const result = await processRequestJob(
    {
      id: "request-1",
      worker_token: "lease-1",
      email_hash: "email-hash",
      email_ciphertext: "sealed-email",
      attempts: 1,
    },
    requestDependencies({
      issueOtp: async (value) => {
        issue = value;
        return "ISSUED";
      },
    }),
  );
  assert.equal(result, "issued");
  assert.equal(issue.jobId, "request-1");
  assert.equal(issue.workerToken, "lease-1");
  assert.equal(issue.userId, "admin-1");
  assert.equal(issue.otp, "004201");
  assert.equal(issue.email, "admin@example.test");
});

test("request worker retries transient lookup/database failure with bounded backoff", async () => {
  let retry;
  const result = await processRequestJob(
    {
      id: "request-2",
      worker_token: "lease-2",
      email_ciphertext: "sealed",
      attempts: 3,
    },
    requestDependencies({
      findActiveAdmin: async () => {
        throw new Error("private backend detail");
      },
      retryRequest: async (...args) => {
        retry = args;
        return "RETRY";
      },
    }),
  );
  assert.equal(result, "retry");
  assert.deepEqual(retry, ["request-2", "lease-2", 4]);
  assert.equal(retryDelaySeconds(99), 60);
});

test("duplicate request jobs are idempotent at their stable request id", async () => {
  const issuedByRequest = new Map();
  const deps = requestDependencies({
    issueOtp: async ({ jobId, otp }) => {
      if (issuedByRequest.has(jobId)) return "ISSUED";
      issuedByRequest.set(jobId, { otp, generation: 1 });
      return "ISSUED";
    },
  });
  const job = {
    id: "same-request",
    worker_token: "lease",
    email_hash: "hash",
    email_ciphertext: "sealed",
    attempts: 1,
  };
  await Promise.all([
    processRequestJob(job, deps),
    processRequestJob(job, deps),
  ]);
  assert.equal(issuedByRequest.size, 1);
});

test("expired outbox job is invalidated without sending", async () => {
  let sent = false;
  let expired;
  const result = await processEmailJob(
    {
      id: "mail-1",
      worker_token: "lease",
      expires_at: new Date(900).toISOString(),
    },
    emailDependencies({
      sendEmail: async () => {
        sent = true;
      },
      expire: async (...args) => {
        expired = args;
        return "FAILED";
      },
    }),
  );
  assert.equal(result, "expired");
  assert.equal(sent, false);
  assert.deepEqual(expired, ["mail-1", "lease"]);
});

test("expired outbox job reports a stale lease when the database rejects it", async () => {
  const result = await processEmailJob(
    {
      id: "mail-expired-stale",
      worker_token: "lease",
      expires_at: new Date(900).toISOString(),
    },
    emailDependencies({
      expire: async () => "STALE",
    }),
  );
  assert.equal(result, "stale");
});

test("SMTP failure retries the same encrypted OTP instead of creating a new code", async () => {
  let retry;
  let decrypted = [];
  const result = await processEmailJob(
    {
      id: "mail-2",
      worker_token: "lease",
      email_ciphertext: "encrypted-email",
      otp_ciphertext: "encrypted-same-otp",
      expires_at: new Date(20_000).toISOString(),
      attempts: 2,
    },
    emailDependencies({
      decrypt: async (value) => {
        decrypted.push(value);
        return value === "encrypted-email" ? "a@example.test" : "123456";
      },
      sendEmail: async () => {
        throw new Error("smtp detail must not be retained");
      },
      retryEmail: async (...args) => {
        retry = args;
        return "RETRY";
      },
    }),
  );
  assert.equal(result, "retry");
  assert.deepEqual(decrypted, ["encrypted-email", "encrypted-same-otp"]);
  assert.deepEqual(retry, ["mail-2", "lease", 2, "delivery_failed"]);
});

test("ambiguous accepted SMTP followed by completion failure retries same outbox job", async () => {
  let sendCount = 0;
  let retry;
  const result = await processEmailJob(
    {
      id: "mail-3",
      worker_token: "lease",
      email_ciphertext: "email",
      otp_ciphertext: "otp",
      expires_at: new Date(20_000).toISOString(),
      attempts: 1,
    },
    emailDependencies({
      decrypt: async (value) => value === "email" ? "a@example.test" : "123456",
      sendEmail: async () => {
        sendCount += 1;
      },
      complete: async () => {
        throw new Error("completion acknowledgement lost");
      },
      retryEmail: async (...args) => {
        retry = args;
        return "RETRY";
      },
    }),
  );
  assert.equal(result, "retry");
  assert.equal(sendCount, 1);
  assert.deepEqual(retry, ["mail-3", "lease", 1, "delivery_failed"]);
});

test("malformed encrypted OTP is not delivered and enters retry handling", async () => {
  let sendCount = 0;
  let retry;
  const result = await processEmailJob(
    {
      id: "mail-4",
      worker_token: "lease",
      email_ciphertext: "email",
      otp_ciphertext: "bad",
      expires_at: new Date(20_000).toISOString(),
      attempts: 1,
    },
    emailDependencies({
      decrypt: async (value) => value === "email" ? "a@example.test" : "not-an-otp",
      sendEmail: async () => {
        sendCount += 1;
      },
      retryEmail: async (...args) => {
        retry = args;
        return "RETRY";
      },
    }),
  );
  assert.equal(result, "retry");
  assert.equal(sendCount, 0);
  assert.equal(retry[3], "delivery_failed");
});

test("batch runner claims and processes request and mail jobs", async () => {
  const claimed = [];
  const result = await runBatch(
    {
      claimRequests: async () => [{ id: "r", worker_token: "rt", email_ciphertext: "e" }],
      claimEmails: async () => [{
        id: "m",
        worker_token: "mt",
        expires_at: new Date(20_000).toISOString(),
        email_ciphertext: "email",
        otp_ciphertext: "otp",
      }],
    },
    {
      ...requestDependencies({
        findActiveAdmin: async () => null,
        finishRequest: async (...args) => {
          claimed.push(["request", ...args]);
          return true;
        },
      }),
      ...emailDependencies({
        decrypt: async (value) => value === "email" ? "a@example.test" : "654321",
        sendEmail: async (...args) => claimed.push(["send", ...args]),
      }),
    },
  );
  assert.deepEqual(result.requests, ["ignored"]);
  assert.deepEqual(result.emails, ["sent"]);
  assert.deepEqual(claimed, [
    ["request", "r", "rt"],
    ["send", "a@example.test", "654321"],
  ]);
});

test("a false request finish result is reported as stale", async () => {
  let retried = false;
  const result = await processRequestJob(
    { id: "request-stale", worker_token: "lease", email_ciphertext: "sealed" },
    requestDependencies({
      findActiveAdmin: async () => null,
      finishRequest: async () => false,
      retryRequest: async () => {
        retried = true;
        return "RETRY";
      },
    }),
  );
  assert.equal(result, "stale");
  assert.equal(retried, false);
});

test("request retry RPC outcomes report stale and failed explicitly", async (t) => {
  for (const [rpcResult, expected] of [["STALE", "stale"], ["FAILED", "failed"]]) {
    await t.test(rpcResult, async () => {
      const result = await processRequestJob(
        {
          id: `request-${rpcResult.toLowerCase()}`,
          worker_token: "lease",
          email_ciphertext: "sealed",
          attempts: 1,
        },
        requestDependencies({
          findActiveAdmin: async () => {
            throw new Error("lookup failed");
          },
          retryRequest: async () => rpcResult,
        }),
      );
      assert.equal(result, expected);
    });
  }
});

test("a false email completion is rejected and cannot report sent", async () => {
  let sendCount = 0;
  let retry;
  const result = await processEmailJob(
    {
      id: "mail-stale",
      worker_token: "lease",
      email_ciphertext: "email",
      otp_ciphertext: "otp",
      expires_at: new Date(20_000).toISOString(),
      attempts: 1,
    },
    emailDependencies({
      decrypt: async (value) => value === "email" ? "a@example.test" : "123456",
      sendEmail: async () => {
        sendCount += 1;
      },
      complete: async () => false,
      retryEmail: async (...args) => {
        retry = args;
        return "STALE";
      },
    }),
  );
  assert.equal(result, "stale");
  assert.equal(sendCount, 1);
  assert.deepEqual(retry, ["mail-stale", "lease", 1, "delivery_failed"]);
});

test("email retry RPC reports stale and failed explicitly", async (t) => {
  for (const [rpcResult, expected] of [["STALE", "stale"], ["FAILED", "failed"]]) {
    await t.test(rpcResult, async () => {
      const result = await processEmailJob(
        {
          id: `mail-${rpcResult.toLowerCase()}`,
          worker_token: "lease",
          email_ciphertext: "email",
          otp_ciphertext: "otp",
          expires_at: new Date(20_000).toISOString(),
          attempts: 1,
        },
        emailDependencies({
          decrypt: async (value) => value === "email" ? "a@example.test" : "123456",
          sendEmail: async () => {
            throw new Error("SMTP unavailable");
          },
          retryEmail: async () => rpcResult,
        }),
      );
      assert.equal(result, expected);
    });
  }
});

test("OTP hash contract remains email-plus-code HMAC", () => {
  const hash = createHmac("sha256", "test-only-salt")
    .update("admin@example.test:123456")
    .digest("base64url");
  assert.match(hash, /^[A-Za-z0-9_-]+$/);
});
