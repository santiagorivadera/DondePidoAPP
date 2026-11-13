import { createHmac, randomInt } from "node:crypto";
import { supabaseOrigin, type Actor } from "./auth";
import { runOnboarding } from "./db";
import { HttpError, isLoopback, requiredText, serviceFetch, serviceOrigin, uuid } from "./http";

export function normalizePhone(value: unknown): string {
  const phone = requiredText(value, "teléfono", 40).replace(/[\s().-]/g, "");
  if (!/^\+[1-9][0-9]{1,14}$/.test(phone)) {
    throw new HttpError(400, "VALIDACION", "Ingresá el teléfono con código de país.");
  }
  return phone;
}

function mailpitOrigin(): URL {
  if (process.env.NODE_ENV !== "development" || !isLoopback(supabaseOrigin())) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "La verificación local no está habilitada.");
  }
  const url = serviceOrigin(process.env.DONDEP_LOCAL_MAILPIT_URL);
  if (!isLoopback(url)) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "La verificación local no está habilitada.");
  }
  return url;
}

function digest(actor: Actor, phone: string, code: string): string {
  const key = process.env.DONDEP_PHONE_HMAC_KEY;
  if (!key || Buffer.byteLength(key) < 32) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "Falta configurar la verificación de teléfono.");
  }
  return createHmac("sha256", key).update(`${actor.id}\n${phone}\n${code}`).digest("hex");
}

function smsTransport() {
  if (process.env.DONDEP_SMS_PROVIDER !== "twilio") {
    const origin = mailpitOrigin();
    return (_phone: string, code: string, challengeId: string) =>
      serviceFetch(new URL("/api/v1/send", origin), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          From: { Email: "dondepido-local@example.invalid" },
          To: [{ Email: "sms-local@example.invalid" }],
          Subject: `DondePido SMS local ${challengeId}`,
          Text: `Código: ${code}`,
        }),
      });
  }

  const account = process.env.DONDEP_TWILIO_ACCOUNT_SID;
  const key = process.env.DONDEP_TWILIO_API_KEY_SID;
  const secret = process.env.DONDEP_TWILIO_API_KEY_SECRET;
  const sender = process.env.DONDEP_TWILIO_SMS_SERVICE_SID;
  if (!account || !/^AC[a-f0-9]{32}$/i.test(account) || !key || !/^SK[a-f0-9]{32}$/i.test(key) ||
      !secret || !sender || !/^MG[a-f0-9]{32}$/i.test(sender)) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "La verificación por SMS no está configurada.");
  }
  const url = new URL(`/2010-04-01/Accounts/${account}/Messages.json`, "https://api.twilio.com");
  const authorization = Buffer.from(`${key}:${secret}`).toString("base64");
  return (phone: string, code: string) => serviceFetch(url, {
    method: "POST",
    headers: { Authorization: `Basic ${authorization}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      MessagingServiceSid: sender, To: phone, Body: `Tu código de DondePido es ${code}. Vence en 10 minutos.`,
    }),
  });
}

export async function issuePhoneChallenge(actor: Actor, input: Record<string, unknown>) {
  const phone = normalizePhone(input.phone);
  const send = smsTransport();
  if (process.env.DONDEP_SMS_PROVIDER === "twilio" && !/^\+549[0-9]{10}$/.test(phone)) {
    throw new HttpError(400, "VALIDACION", "Ingresá un celular argentino con el prefijo +54 9.");
  }
  const code = randomInt(1_000_000).toString().padStart(6, "0");
  const challengeId = await runOnboarding<string>(
    actor,
    "select dondepido.issue_phone_challenge($1, $2) as data",
    [phone, digest(actor, phone, code)],
  );
  const response = await send(phone, code, challengeId);
  await response.body?.cancel().catch(() => undefined);
  if (!response.ok) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos enviar el código. Volvé a intentar más tarde.");
  }
  return challengeId;
}

export async function verifyPhoneChallenge(actor: Actor, input: Record<string, unknown>) {
  const phone = normalizePhone(input.phone);
  const challengeId = uuid(input.challengeId, "desafío");
  const code = input.code;
  if (typeof code !== "string" || !/^[0-9]{6}$/.test(code)) {
    throw new HttpError(400, "VALIDACION", "Ingresá el código de seis dígitos.");
  }
  const result = await runOnboarding<string>(
    actor,
    "select dondepido.verify_phone_challenge($1::uuid, $2) as data",
    [challengeId, digest(actor, phone, code)],
  );
  switch (result) {
    case "verified":
      return result;
    case "invalid":
      throw new HttpError(400, "CODIGO_INVALIDO", "El código no es válido.");
    case "expired":
      throw new HttpError(410, "CODIGO_VENCIDO", "El código venció. Pedí uno nuevo.");
    case "conflict":
      throw new HttpError(409, "TELEFONO_NO_DISPONIBLE", "No pudimos vincular ese número.");
    default:
      throw new Error("Unexpected phone verification result");
  }
}
