const e164 = /^\+[1-9][0-9]{1,14}$/;
const sid = (prefix, value) => typeof value === "string" && new RegExp(`^${prefix}[a-f0-9]{32}$`, "i").test(value);

export function createTwilioTransport(mode, env = process.env, request = fetch) {
  const account = env.DONDEP_TWILIO_ACCOUNT_SID;
  const key = env.DONDEP_TWILIO_API_KEY_SID;
  const secret = env.DONDEP_TWILIO_API_KEY_SECRET;
  const sender = env.DONDEP_TWILIO_WHATSAPP_FROM ?? "";
  const recipient = env.DONDEP_TWILIO_WHATSAPP_TEST_TO ?? "";
  const service = env.DONDEP_TWILIO_WHATSAPP_SERVICE_SID;
  const template = env.DONDEP_TWILIO_WHATSAPP_CONTENT_SID;
  if (!sid("AC", account) || !sid("SK", key) || !secret || !e164.test(sender) || !e164.test(recipient) ||
      (mode === "template" && (!sid("HX", template) || !sid("MG", service)))) {
    throw new Error("Falta configurar Twilio para la prueba de WhatsApp.");
  }

  const messages = new URL(`/2010-04-01/Accounts/${account}/Messages.json`, "https://api.twilio.com");
  const authorization = Buffer.from(`${key}:${secret}`).toString("base64");
  return {
    recipient,
    async send(notice, body) {
      if (notice.recipient !== recipient) throw new Error("El pedido no corresponde al destinatario de prueba.");
      const parameters = new URLSearchParams({ From: `whatsapp:${sender}`, To: `whatsapp:${recipient}` });
      if (mode === "template") {
        const clean = (value) => value.replace(/\s+/g, " ").trim();
        parameters.set("MessagingServiceSid", service);
        parameters.set("ContentSid", template);
        parameters.set("ContentVariables", JSON.stringify({
          1: notice.orderId,
          2: clean(notice.businessName),
          3: clean(notice.items.map((item) => {
            const parts = item.components.map((part) => `${part.quantity} × ${part.name}`);
            return `${item.quantity} × ${item.name}${parts.length ? ` (${parts.join(", ")})` : ""}`;
          }).join(", ")),
          4: clean(`${notice.mode === "delivery" ? "Envío a" : "Retiro en"} ${notice.address}`),
          5: notice.contact ?? "Consultá el detalle en DondePido",
        }));
      } else {
        parameters.set("Body", `Prueba DondePido\n\n${body}`);
      }
      const response = await request(messages, {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
        headers: { Authorization: `Basic ${authorization}`, "Content-Type": "application/x-www-form-urlencoded" },
        body: parameters,
      });
      const result = await response.json().catch(() => null);
      if (!response.ok || !sid("SM", result?.sid) || !["accepted", "queued", "sending", "sent", "delivered", "read"].includes(result.status)) {
        const code = Number.isInteger(result?.code) ? ` (código ${result.code})` : "";
        throw new Error(`Twilio no confirmó la aceptación del envío${code}.`);
      }
      return { sid: result.sid, status: result.status };
    },
  };
}
