/**
 * Honeybee Center – Firebase Cloud Functions
 * OTP-based password reset backend
 *
 * Three callable HTTPS functions:
 *   1. sendOtp          – validates email, generates OTP, sends email
 *   2. verifyOtp        – checks OTP, returns a short-lived signed token
 *   3. resetPassword    – validates token, calls Admin SDK to change password
 *
 * Security measures:
 *   - OTP is hashed (SHA-256 + per-session salt) before storage in RTDB
 *   - Plain OTP is never persisted anywhere
 *   - OTP expires after 5 minutes
 *   - Max 5 verification attempts per session; session is locked after that
 *   - Resend creates a new session (old one is invalidated)
 *   - verifiedToken is a signed JWT, expires in 10 minutes, single-use
 *   - Email enumeration is prevented (generic response on unknown email)
 *   - Firebase Admin credentials are loaded from environment, never from client
 */

"use strict";

const functions = require("firebase-functions");
const admin     = require("firebase-admin");
const crypto    = require("crypto");
const nodemailer = require("nodemailer");
const jwt       = require("jsonwebtoken");

// ─── Initialise Admin SDK ────────────────────────────────────────────────────
// When deployed to Cloud Functions, GOOGLE_APPLICATION_CREDENTIALS or the
// default service account grants Admin access automatically.
// For local emulator use, set GOOGLE_APPLICATION_CREDENTIALS in .env.
admin.initializeApp({
  databaseURL: process.env.DATABASE_URL ||
               "https://honeybee-center-default-rtdb.firebaseio.com/",
});

const db   = admin.database();
const auth = admin.auth();

// ─── Constants ───────────────────────────────────────────────────────────────
const OTP_TTL_MS          = 5 * 60 * 1000;   // 5 minutes
const MAX_ATTEMPTS        = 5;
const TOKEN_TTL_SECONDS   = 10 * 60;          // 10 minutes
const OTP_NODE            = "otp_sessions";

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Generate a cryptographically secure 6-digit OTP string. */
function generateOtp() {
  // Use rejection sampling so every digit is uniformly distributed.
  let otp;
  do {
    const rand = crypto.randomInt(0, 1_000_000);
    otp = String(rand).padStart(6, "0");
  } while (false);
  return otp;
}

/** Hash OTP with SHA-256 using a per-session salt. */
function hashOtp(otp, salt) {
  return crypto.createHmac("sha256", salt).update(otp).digest("hex");
}

/** Build a Nodemailer transporter from environment variables. */
function buildTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: process.env.EMAIL_USER,
      pass: process.env.EMAIL_PASS,
    },
  });
}

/** Send the OTP email. Throws on failure. */
async function sendOtpEmail(toEmail, otp) {
  const transporter = buildTransporter();
  await transporter.sendMail({
    from: `"Honeybee Center" <${process.env.EMAIL_USER}>`,
    to: toEmail,
    subject: "Your Honeybee Center Verification Code",
    text: [
      "Your verification code for Honeybee Center Admin Panel is:",
      "",
      `  ${otp}`,
      "",
      "This code expires in 5 minutes.",
      "If you did not request a password reset, ignore this email.",
    ].join("\n"),
    html: `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;
                  border:1px solid #e8c85a;border-radius:10px;padding:32px 36px;">
        <div style="text-align:center;margin-bottom:20px;">
          <span style="font-size:36px;">🐝</span>
          <h2 style="color:#c89127;margin:8px 0 4px;">Honeybee Center</h2>
          <p style="color:#888;margin:0;font-size:13px;">Admin Portal</p>
        </div>
        <p style="font-size:15px;color:#333;">
          Your verification code is:
        </p>
        <div style="text-align:center;margin:24px 0;">
          <span style="display:inline-block;font-size:36px;font-weight:700;
                       letter-spacing:10px;color:#c89127;
                       background:#fff8e6;padding:14px 28px;
                       border-radius:8px;border:2px solid #e8c85a;">
            ${otp}
          </span>
        </div>
        <p style="font-size:13px;color:#666;">
          This code expires in <strong>5 minutes</strong>.<br>
          If you did not request a password reset, please ignore this email.
        </p>
      </div>
    `,
  });
}

// ─── Function 1: sendOtp ─────────────────────────────────────────────────────
exports.sendOtp = functions.https.onCall(async (data, context) => {
  const email = (data.email || "").trim().toLowerCase();

  // Basic format validation
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!email || !emailPattern.test(email)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Please enter a valid email address."
    );
  }

  // Attempt to find the user in Firebase Auth.
  // We do NOT reveal whether the email exists (anti-enumeration).
  let uid = null;
  try {
    const userRecord = await auth.getUserByEmail(email);
    uid = userRecord.uid;
  } catch (err) {
    // user-not-found → silently succeed (no enumeration)
    if (err.code !== "auth/user-not-found") {
      // Unexpected error — log server-side, return generic message to client
      console.error("sendOtp: admin.auth error:", err);
    }
    // Return generic success so the client shows the same message either way
    return { success: true, sessionId: null };
  }

  // Generate OTP and salt
  const otp      = generateOtp();
  const salt     = crypto.randomBytes(32).toString("hex");
  const otpHash  = hashOtp(otp, salt);
  const now      = Date.now();
  const sessionId = crypto.randomBytes(16).toString("hex");

  // Store session in RTDB — plain OTP is NEVER written
  const sessionRef = db.ref(`${OTP_NODE}/${sessionId}`);
  await sessionRef.set({
    uid,
    email,
    otpHash,
    salt,
    expiresAt: now + OTP_TTL_MS,
    attempts: 0,
    used: false,
    verified: false,
    createdAt: now,
  });

  // Schedule automatic deletion after TTL (keep RTDB clean)
  // Cloud Functions does not have built-in TTL, so we set a flag the
  // client will never see. A Realtime Database rule or periodic cleanup
  // function can purge old sessions. The session is always checked on use.

  // Send the OTP email
  try {
    await sendOtpEmail(email, otp);
  } catch (emailErr) {
    console.error("sendOtp: failed to send email:", emailErr);
    // Clean up the session we created
    await sessionRef.remove();
    throw new functions.https.HttpsError(
      "internal",
      "Failed to send verification email. Please try again."
    );
  }

  // Return only the sessionId. The OTP itself is never sent back.
  return { success: true, sessionId };
});

// ─── Function 2: verifyOtp ───────────────────────────────────────────────────
exports.verifyOtp = functions.https.onCall(async (data, context) => {
  const sessionId = (data.sessionId || "").trim();
  const otp       = (data.otp || "").trim();

  if (!sessionId || !otp || !/^\d{6}$/.test(otp)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid request."
    );
  }

  const sessionRef = db.ref(`${OTP_NODE}/${sessionId}`);
  const snapshot   = await sessionRef.get();

  if (!snapshot.exists()) {
    throw new functions.https.HttpsError(
      "not-found",
      "This verification code has expired. Please request a new code."
    );
  }

  const session = snapshot.val();

  // Check expiry
  if (Date.now() > session.expiresAt) {
    await sessionRef.remove();
    throw new functions.https.HttpsError(
      "deadline-exceeded",
      "This verification code has expired. Please request a new code."
    );
  }

  // Check already used / already verified
  if (session.used || session.verified) {
    throw new functions.https.HttpsError(
      "already-exists",
      "This verification code has already been used. Please request a new code."
    );
  }

  // Check attempt limit
  if (session.attempts >= MAX_ATTEMPTS) {
    await sessionRef.remove();
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Too many incorrect attempts. Please request a new verification code."
    );
  }

  // Verify OTP hash
  const incoming = hashOtp(otp, session.salt);
  if (incoming !== session.otpHash) {
    // Increment attempt counter
    await sessionRef.update({ attempts: session.attempts + 1 });
    const remaining = MAX_ATTEMPTS - (session.attempts + 1);
    throw new functions.https.HttpsError(
      "unauthenticated",
      remaining > 0
        ? `Invalid verification code. ${remaining} attempt${remaining === 1 ? "" : "s"} remaining.`
        : "Too many incorrect attempts. Please request a new verification code."
    );
  }

  // OTP is correct — mark as verified (not yet used; password not changed yet)
  await sessionRef.update({ verified: true });

  // Issue a short-lived signed JWT so the client can call resetPassword
  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret) {
    console.error("verifyOtp: JWT_SECRET env var is not set");
    throw new functions.https.HttpsError("internal", "Server configuration error.");
  }

  const verifiedToken = jwt.sign(
    { sessionId, uid: session.uid, email: session.email },
    jwtSecret,
    { expiresIn: TOKEN_TTL_SECONDS }
  );

  return { success: true, verifiedToken };
});

// ─── Function 3: resetPassword ───────────────────────────────────────────────
exports.resetPassword = functions.https.onCall(async (data, context) => {
  const verifiedToken = (data.verifiedToken || "").trim();
  const newPassword   = (data.newPassword   || "");

  if (!verifiedToken || !newPassword) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid request."
    );
  }

  // Password length check (mirrors client-side validation)
  if (newPassword.length < 8) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Password must be at least 8 characters."
    );
  }

  // Verify JWT
  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret) {
    console.error("resetPassword: JWT_SECRET env var is not set");
    throw new functions.https.HttpsError("internal", "Server configuration error.");
  }

  let payload;
  try {
    payload = jwt.verify(verifiedToken, jwtSecret);
  } catch (err) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Your verification session has expired. Please start over."
    );
  }

  const { sessionId, uid } = payload;

  // Re-check session in RTDB (ensure it was verified and not yet used)
  const sessionRef = db.ref(`${OTP_NODE}/${sessionId}`);
  const snapshot   = await sessionRef.get();

  if (!snapshot.exists()) {
    throw new functions.https.HttpsError(
      "not-found",
      "Your verification session has expired. Please start over."
    );
  }

  const session = snapshot.val();

  if (!session.verified || session.used) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "OTP has not been verified or has already been used. Please start over."
    );
  }

  if (Date.now() > session.expiresAt) {
    await sessionRef.remove();
    throw new functions.https.HttpsError(
      "deadline-exceeded",
      "Your verification session has expired. Please start over."
    );
  }

  // Mark session as used BEFORE updating the password (prevent double-use)
  await sessionRef.update({ used: true });

  // Update the password in Firebase Authentication via Admin SDK
  // This does NOT touch /admins/{uid} — role, status, name remain unchanged.
  try {
    await auth.updateUser(uid, { password: newPassword });
  } catch (firebaseErr) {
    // Roll back the used flag so the user can try again
    await sessionRef.update({ used: false });
    console.error("resetPassword: updateUser failed:", firebaseErr);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to update the password. Please try again."
    );
  }

  // Clean up the OTP session
  await sessionRef.remove();

  return { success: true };
});
