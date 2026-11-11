import { randomInt } from "node:crypto";

export function createOtp() {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

export function retryDelaySeconds(attempt) {
  return Math.min(2 ** Math.max(0, attempt - 1), 60);
}

function requestRetryOutcome(result) {
  if (result === "RETRY") return "retry";
  if (result === "FAILED") return "failed";
  if (result === "STALE") return "stale";
  throw new Error("Unexpected request retry result");
}

function emailRetryOutcome(result) {
  if (result === "RETRY") return "retry";
  if (result === "FAILED") return "failed";
  if (result === "STALE") return "stale";
  throw new Error("Unexpected email retry result");
}

function emailExpireOutcome(result) {
  const outcome = emailRetryOutcome(result);
  return outcome === "failed" ? "expired" : outcome;
}

export async function processRequestJob(job, dependencies) {
  let result;
  try {
    const email = await dependencies.decrypt(job.email_ciphertext);
    const admin = await dependencies.findActiveAdmin(email);
    if (!admin) {
      const finished = await dependencies.finishRequest(job.id, job.worker_token);
      if (finished === true) return "ignored";
      if (finished === false) return "stale";
      throw new Error("Unexpected request finish result");
    }

    const otp = dependencies.createOtp();
    result = await dependencies.issueOtp({
      jobId: job.id,
      workerToken: job.worker_token,
      userId: admin.id,
      emailHash: job.email_hash,
      email,
      emailCiphertext: job.email_ciphertext,
      otp,
    });
  } catch {
    return requestRetryOutcome(await dependencies.retryRequest(
      job.id,
      job.worker_token,
      retryDelaySeconds(job.attempts),
    ));
  }

  if (result === "RETRY") {
    return requestRetryOutcome(await dependencies.retryRequest(
      job.id,
      job.worker_token,
      retryDelaySeconds(job.attempts),
    ));
  }

  const outcomes = {
    ISSUED: "issued",
    INELIGIBLE: "ignored",
    COOLDOWN: "cooldown",
    RATE_LIMITED: "rate_limited",
    DELIVERY_PENDING: "delivery_pending",
    STALE: "stale",
  };
  if (typeof result !== "string" || !outcomes[result]) {
    throw new Error("Unexpected OTP issue result");
  }
  return outcomes[result];
}

export async function processEmailJob(job, dependencies) {
  if (Date.parse(job.expires_at) <= dependencies.now()) {
    return emailExpireOutcome(
      await dependencies.expire(job.id, job.worker_token),
    );
  }

  let email;
  let otp;
  try {
    [email, otp] = await Promise.all([
      dependencies.decrypt(job.email_ciphertext),
      dependencies.decrypt(job.otp_ciphertext),
    ]);
    if (!/^\d{6}$/.test(otp)) throw new Error("Invalid encrypted OTP payload");
  } catch {
    return emailRetryOutcome(await dependencies.retryEmail(
      job.id,
      job.worker_token,
      retryDelaySeconds(job.attempts),
      "delivery_failed",
    ));
  }

  if (Date.parse(job.expires_at) <= dependencies.now()) {
    return emailExpireOutcome(
      await dependencies.expire(job.id, job.worker_token),
    );
  }

  try {
    await dependencies.sendEmail(email, otp);
    const completed = await dependencies.complete(job.id, job.worker_token);
    if (completed !== true) {
      throw new Error("Email job completion was rejected");
    }
    return "sent";
  } catch {
    return emailRetryOutcome(await dependencies.retryEmail(
      job.id,
      job.worker_token,
      retryDelaySeconds(job.attempts),
      "delivery_failed",
    ));
  }
}

export async function runBatch(store, dependencies, batchSize = 10) {
  const [requestJobs, emailJobs] = await Promise.all([
    store.claimRequests(batchSize),
    store.claimEmails(batchSize),
  ]);
  const requestResults = await Promise.all(
    requestJobs.map((job) => processRequestJob(job, dependencies)),
  );
  const emailResults = await Promise.all(
    emailJobs.map((job) => processEmailJob(job, dependencies)),
  );
  return {
    requests: requestResults,
    emails: emailResults,
  };
}
