export function loadSmtpConfig(environment) {
  const host = (environment.SMTP_HOST ?? "smtp.gmail.com").trim();
  const portValue = environment.SMTP_PORT ?? "465";
  const port = Number(portValue);
  const secureValue = environment.SMTP_SECURE?.trim().toLowerCase();
  const from = (environment.SMTP_FROM ?? environment.SMTP_USER ?? "").trim();

  if (!host) throw new Error("SMTP_HOST must not be empty");
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("SMTP_PORT must be an integer from 1 to 65535");
  }
  if (secureValue !== undefined && !["true", "false"].includes(secureValue)) {
    throw new Error("SMTP_SECURE must be true or false");
  }
  if (!from) throw new Error("SMTP_FROM or SMTP_USER must be configured");

  return {
    host,
    port,
    secure: secureValue === undefined ? port === 465 : secureValue === "true",
    from,
  };
}
