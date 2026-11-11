import {
  createHmac,
  randomUUID,
} from "node:crypto";
import nodemailer from "nodemailer";

import { createOtp, runBatch } from "./worker_core.mjs";
import { decodeEncryptionKey, decryptPayload, encryptPayload } from "./worker_crypto.mjs";
import { loadSmtpConfig } from "./smtp_config.mjs";

const requiredEnvironment = [
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "OTP_SALT_SECRET",
  "OTP_OUTBOX_ENCRYPTION_KEY",
  "SMTP_USER",
  "SMTP_PASS",
];

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

const config = Object.fromEntries(
  requiredEnvironment.map((name) => [name, requiredEnv(name)]),
);
const smtpConfig = loadSmtpConfig(process.env);
const baseUrl = config.SUPABASE_URL.replace(/\/+$/, "");
const encryptionKey = decodeEncryptionKey(config.OTP_OUTBOX_ENCRYPTION_KEY);

async function request(path, init = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: {
      apikey: config.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${config.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
  if (!response.ok) throw new Error(`Supabase worker request failed (${response.status})`);
  return response.json();
}

async function rpc(name, parameters) {
  return request(`/rest/v1/rpc/${name}`, {
    method: "POST",
    body: JSON.stringify(parameters),
  });
}

async function findActiveAdmin(email) {
  const query = new URLSearchParams({
    select: "id,email,role,status",
    email: `eq.${email}`,
    status: "eq.active",
    limit: "1",
  });
  const rows = await request(`/rest/v1/admins?${query}`);
  if (!Array.isArray(rows) || rows.length !== 1) return null;
  const admin = rows[0];
  if (
    admin.email?.toLowerCase() !== email ||
    !["main_admin", "co_admin"].includes(admin.role)
  ) return null;

  const authResponse = await request(
    `/auth/v1/admin/users/${encodeURIComponent(admin.id)}`,
  );
  const user = authResponse?.user ?? authResponse;
  const bannedUntil = user?.banned_until
    ? Date.parse(user.banned_until)
    : Number.NaN;
  if (
    user?.id !== admin.id ||
    user?.email?.toLowerCase() !== email ||
    user?.deleted_at != null ||
    (Number.isFinite(bannedUntil) && bannedUntil > Date.now())
  ) return null;
  return admin;
}

const transporter = nodemailer.createTransport({
  host: smtpConfig.host,
  port: smtpConfig.port,
  secure: smtpConfig.secure,
  connectionTimeout: 8000,
  greetingTimeout: 8000,
  socketTimeout: 12000,
  auth: { user: config.SMTP_USER, pass: config.SMTP_PASS },
});

async function sendEmail(email, otp) {
  await transporter.sendMail({
    from: `"Honeybee Center" <${smtpConfig.from}>`,
    to: email,
    subject: "Honeybee Center - Password Reset OTP",
    text:
      `Your Honeybee Center password reset code is ${otp}.\n\n` +
      "This code expires in 5 minutes.\n\n" +
      "If you did not request a password reset, you can ignore this email.",
  });
}

async function issueOtp({ jobId, workerToken, userId, email, otp }) {
  const salt = config.OTP_SALT_SECRET;
  const otpHash = createHmac("sha256", salt)
    .update(`${email}:${otp}`)
    .digest("base64url");
  return rpc("issue_otp_email_job", {
    p_job_id: jobId,
    p_worker_token: workerToken,
    p_user_id: userId,
    p_email: email,
    p_otp_hash: otpHash,
    p_otp_ciphertext: encryptPayload(otp, encryptionKey),
  });
}

async function retryRequest(jobId, workerToken, delay) {
  return rpc("retry_otp_request_job", {
    p_job_id: jobId,
    p_worker_token: workerToken,
    p_delay_seconds: delay,
  });
}

async function completeRequest(jobId, workerToken) {
  return rpc("finish_otp_request_job", {
    p_job_id: jobId,
    p_worker_token: workerToken,
  });
}

const dependencies = {
  decrypt: (payload) => decryptPayload(payload, encryptionKey),
  findActiveAdmin,
  createOtp,
  issueOtp,
  finishRequest: completeRequest,
  retryRequest,
  now: Date.now,
  sendEmail,
  complete: (jobId, workerToken) =>
    rpc("complete_otp_email_job", {
      p_job_id: jobId,
      p_worker_token: workerToken,
    }),
  retryEmail: (jobId, workerToken, delay, reason) =>
    rpc("retry_otp_email_job", {
      p_job_id: jobId,
      p_worker_token: workerToken,
      p_delay_seconds: delay,
      p_error: reason,
    }),
  expire: (jobId, workerToken) =>
    rpc("retry_otp_email_job", {
      p_job_id: jobId,
      p_worker_token: workerToken,
      p_delay_seconds: 1,
      p_error: "expired",
    }),
};

async function claim(name, batchSize) {
  return rpc(name, {
    p_worker_token: randomUUID(),
    p_batch_size: batchSize,
  });
}

const store = {
  claimRequests: (batchSize) => claim("claim_otp_request_jobs", batchSize),
  claimEmails: (batchSize) => claim("claim_otp_email_jobs", batchSize),
};

const pollMilliseconds = Number(process.env.OTP_WORKER_POLL_MS ?? 1000);
if (!Number.isFinite(pollMilliseconds) || pollMilliseconds < 250) {
  throw new Error("OTP_WORKER_POLL_MS must be at least 250");
}

console.info("OTP outbox worker started.");
while (true) {
  try {
    const result = await runBatch(store, dependencies);
    if (result.requests.length === 0 && result.emails.length === 0) {
      await new Promise((resolve) => setTimeout(resolve, pollMilliseconds));
    }
  } catch {
    console.error("OTP outbox worker batch failed.");
    await new Promise((resolve) => setTimeout(resolve, pollMilliseconds));
  }
}
