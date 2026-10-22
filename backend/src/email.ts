import type { Env } from "./env.ts";

/** Sends through Resend, or logs the message when MAIL_MODE=log (local development only). */
export async function sendEmail(env: Env, to: string, subject: string, text: string): Promise<void> {
  if (env.MAIL_MODE === "log") {
    console.log(`[mail to ${to}] ${subject}: ${text}`);
    return;
  }
  if (!env.RESEND_API_KEY || !env.MAIL_FROM) throw new Error("email is not configured");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ from: env.MAIL_FROM, to: [to], subject, text }),
  });
  if (!res.ok) throw new Error(`email provider returned ${res.status}`);
}
