import { createClient } from "npm:@supabase/supabase-js@2";

type PushJob = {
  push_id: string;
  notification_id: string;
  device_id: string;
  fcm_token: string;
  title: string;
  body: string;
  claim_token: string;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type OAuthToken = {
  accessToken: string;
  expiresAt: number;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const fcmProjectId = Deno.env.get("FCM_PROJECT_ID");
const serviceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");

if (!supabaseUrl || !serviceRoleKey || !fcmProjectId || !serviceAccountJson) {
  throw new Error(
    "SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FCM_PROJECT_ID, and " +
      "FCM_SERVICE_ACCOUNT_JSON must be configured",
  );
}

let serviceAccount: ServiceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountJson) as ServiceAccount;
} catch {
  throw new Error("FCM_SERVICE_ACCOUNT_JSON must contain valid JSON");
}

if (!serviceAccount.client_email || !serviceAccount.private_key) {
  throw new Error(
    "FCM_SERVICE_ACCOUNT_JSON must include client_email and private_key",
  );
}

const tokenUri = serviceAccount.token_uri ??
  "https://oauth2.googleapis.com/token";
if (tokenUri !== "https://oauth2.googleapis.com/token") {
  throw new Error("FCM_SERVICE_ACCOUNT_JSON has an unsupported token_uri");
}
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const encoder = new TextEncoder();
let cachedOAuthToken: OAuthToken | null = null;

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64UrlText(value: string): string {
  return base64Url(encoder.encode(value));
}

function decodePrivateKey(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedOAuthToken && cachedOAuthToken.expiresAt > now + 60) {
    return cachedOAuthToken.accessToken;
  }

  const issuedAt = now;
  const header = base64UrlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlText(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: issuedAt,
    exp: issuedAt + 3600,
  }));
  const unsignedAssertion = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePrivateKey(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      encoder.encode(unsignedAssertion),
    ),
  );
  const assertion = `${unsignedAssertion}.${base64Url(signature)}`;

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`Google OAuth token request failed (${response.status})`);
  }

  const result = await response.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!result.access_token || !result.expires_in) {
    throw new Error("Google OAuth returned an invalid access token response");
  }

  cachedOAuthToken = {
    accessToken: result.access_token,
    expiresAt: now + result.expires_in,
  };
  return cachedOAuthToken.accessToken;
}

function isUnregisteredToken(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }
  const details = (error as { details?: unknown }).details;
  return Array.isArray(details) && details.some((detail) => {
    return Boolean(
      detail &&
        typeof detail === "object" &&
        (detail as { errorCode?: string }).errorCode === "UNREGISTERED",
    );
  });
}

async function sendPush(
  job: PushJob,
  accessToken: string,
): Promise<void> {
  let response: Response;
  try {
    response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${
        encodeURIComponent(fcmProjectId)
      }/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: job.fcm_token,
            notification: { title: job.title, body: job.body },
            data: {
              notification_id: job.notification_id,
              type: "PICKUP_READY_REMINDER",
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: "pickup_reminders",
                tag: `customer-notification-${job.notification_id}`,
              },
            },
          },
        }),
      },
    );
  } catch {
    throw new FcmDeliveryError(0, false);
  }

  if (response.ok) {
    return;
  }

  let error: unknown;
  try {
    const result = await response.json() as { error?: unknown };
    error = result.error;
  } catch {
    error = null;
  }
  throw new FcmDeliveryError(response.status, isUnregisteredToken(error));
}

class FcmDeliveryError extends Error {
  constructor(
    readonly status: number,
    readonly invalidToken: boolean,
  ) {
    super(`FCM delivery failed (${status})`);
  }

  get retryable(): boolean {
    return this.status === 0 || this.status === 408 || this.status === 429 ||
      this.status === 401 || this.status === 403 || this.status >= 500;
  }
}

async function finalize(
  job: PushJob,
  result: {
    success: boolean;
    permanent?: boolean;
    invalidToken?: boolean;
    error?: string;
  },
): Promise<void> {
  const { error } = await supabase.rpc(
    "finish_customer_push_notification",
    {
      p_push_id: job.push_id,
      p_claim_token: job.claim_token,
      p_success: result.success,
      p_permanent: result.permanent ?? false,
      p_invalid_token: result.invalidToken ?? false,
      p_error: result.error ?? null,
    },
  );
  if (error) {
    throw new Error("Could not finalize customer push delivery");
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (request.headers.get("Authorization") !== `Bearer ${serviceRoleKey}`) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken();
  } catch {
    console.error("Could not obtain an FCM access token");
    return Response.json({ error: "FCM authentication unavailable" }, {
      status: 503,
    });
  }

  const { data, error } = await supabase.rpc(
    "claim_customer_push_notifications",
  );
  if (error) {
    console.error("Could not claim customer push notifications:", error.message);
    return Response.json({ error: "Could not claim push jobs" }, {
      status: 500,
    });
  }
  if (!Array.isArray(data)) {
    console.error("Supabase returned an invalid customer push batch");
    return Response.json({ error: "Invalid push batch" }, { status: 500 });
  }

  const jobs = data as PushJob[];
  let sent = 0;
  let failed = 0;
  let stale = 0;
  for (const job of jobs) {
    const {
      data: currentData,
      error: validationError,
    } = await supabase.rpc("validate_customer_push_notification_claim", {
      p_push_id: job.push_id,
      p_claim_token: job.claim_token,
    });
    if (validationError) {
      console.error("Could not validate a customer push claim:", validationError.message);
      return Response.json({ error: "Could not validate push claim" }, {
        status: 500,
      });
    }
    if (!Array.isArray(currentData)) {
      console.error("Supabase returned an invalid customer push claim");
      return Response.json({ error: "Invalid push claim" }, { status: 500 });
    }
    if (currentData.length === 0) {
      stale++;
      continue;
    }

    const currentJob = currentData[0] as PushJob;
    try {
      // Eligibility can change after validation; an issued FCM request cannot be recalled.
      await sendPush(currentJob, accessToken);
      await finalize(currentJob, { success: true });
      sent++;
    } catch (error) {
      if (!(error instanceof FcmDeliveryError)) {
        console.error("Customer push delivery failed unexpectedly");
        return Response.json({ error: "Could not finalize push job" }, {
          status: 500,
        });
      }

      const permanent = error.invalidToken || !error.retryable;
      try {
        await finalize(currentJob, {
          success: false,
          permanent,
          invalidToken: error.invalidToken,
          error: error.invalidToken
            ? "FCM token is invalid or unregistered"
            : error.status === 0
            ? "FCM request failed before a response was received"
            : `FCM returned HTTP ${error.status}`,
        });
      } catch {
        console.error("Could not finalize a failed customer push job");
        return Response.json({ error: "Could not finalize push job" }, {
          status: 500,
        });
      }
      failed++;
    }
  }

  return Response.json({ claimed: jobs.length, sent, failed, stale });
});
