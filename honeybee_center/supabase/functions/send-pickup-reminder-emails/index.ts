import { createClient } from "npm:@supabase/supabase-js@2";

type PickupReminderEmail = {
  email_id: string;
  recipient_email: string;
  customer_name: string;
  order_reference: string | null;
  claim_token: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const resendApiKey = Deno.env.get("RESEND_API_KEY");
const fromEmail = Deno.env.get("RESEND_FROM_EMAIL");

if (!supabaseUrl || !serviceRoleKey || !resendApiKey || !fromEmail) {
  throw new Error(
    "SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY, and " +
      "RESEND_FROM_EMAIL must be configured",
  );
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    switch (character) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case '"':
        return "&quot;";
      default:
        return "&#39;";
    }
  });
}

function emailContent(job: PickupReminderEmail) {
  const name = job.customer_name || "Customer";
  const reference = job.order_reference || `order ${job.email_id}`;
  const htmlName = escapeHtml(name);
  const htmlReference = escapeHtml(reference);

  return {
    subject: `Your order ${reference} is ready for store pickup`,
    text: [
      `Hi ${name},`,
      "",
      `This is a friendly reminder that your order ${reference} has been ready for store pickup for more than 24 hours.`,
      "",
      "You can pick it up at the Honeybee Center Store during our store hours: 9:00 AM–6:00 PM, Monday to Saturday. Please bring your order reference.",
      "",
      "If you have already picked up your order, please ignore this email. If you need help, contact Honeybee Center through your account.",
      "",
      "Thank you,",
      "Honeybee Center",
    ].join("\n"),
    html: `
      <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;
                  color:#28231a;line-height:1.6">
        <h2 style="color:#c89127">Honeybee Center</h2>
        <p>Hi ${htmlName},</p>
        <p>This is a friendly reminder that your order
          <strong>${htmlReference}</strong> has been ready for
          <strong>store pickup</strong> for more than 24 hours.</p>
        <p>You can pick it up at the Honeybee Center Store during our store
          hours: <strong>9:00 AM–6:00 PM, Monday to Saturday</strong>.
          Please bring your order reference.</p>
        <p>If you have already picked up your order, please ignore this email.
          If you need help, contact Honeybee Center through your account.</p>
        <p>Thank you,<br>Honeybee Center</p>
      </div>`,
  };
}

async function sendEmail(job: PickupReminderEmail): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `pickup-reminder-${job.email_id}`,
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [job.recipient_email],
      ...emailContent(job),
    }),
  });

  if (!response.ok) {
    throw new Error(`Resend rejected email (${response.status})`);
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const { data, error } = await supabase.rpc("claim_pickup_reminder_emails");
  if (error) {
    console.error("Could not claim pickup reminder emails:", error.message);
    return Response.json({ error: "Could not claim email jobs" }, {
      status: 500,
    });
  }
  if (!Array.isArray(data)) {
    console.error("Supabase returned an invalid pickup reminder email batch");
    return Response.json({ error: "Invalid email batch" }, { status: 500 });
  }
  const jobs = data as PickupReminderEmail[];

  let sent = 0;
  let failed = 0;
  for (const job of jobs) {
    let delivered = false;
    let deliveryError: unknown;
    try {
      await sendEmail(job);
      delivered = true;
      sent++;
    } catch (error) {
      deliveryError = error;
      failed++;
      console.error(`Pickup reminder email ${job.email_id} failed:`, error);
    }

    const { error: finishError } = await supabase.rpc(
      "finish_pickup_reminder_email",
      {
        p_email_id: job.email_id,
        p_claim_token: job.claim_token,
        p_success: delivered,
        p_error: deliveryError instanceof Error
          ? deliveryError.message
          : deliveryError == null
          ? null
          : String(deliveryError),
      },
    );
    if (finishError) {
      console.error(
        `Could not finalize pickup reminder email ${job.email_id}:`,
        finishError.message,
      );
      return Response.json({ error: "Could not finalize email job" }, {
        status: 500,
      });
    }
  }

  return Response.json({ claimed: jobs.length, sent, failed });
});
