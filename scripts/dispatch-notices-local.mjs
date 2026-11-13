import { spawnSync } from "node:child_process";
import { platform } from "node:os";
import { parseArgs } from "node:util";
import { createTwilioTransport } from "./twilio-order-notice.mjs";

const dbContainer = "supabase_db_dondepido-local";
const mailpitSend = "http://127.0.0.1:55424/api/v1/send";
const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

function docker(args, input) {
  const result = spawnSync("docker", args, {
    input,
    encoding: "utf8",
    windowsHide: true,
    timeout: 10_000,
  });
  if (result.status !== 0) {
    throw new Error("Falló la consulta al contenedor local de DondePido.");
  }
  return result.stdout.trim();
}

function localDockerHost() {
  const host = (process.env.DOCKER_CONTEXT ? undefined : process.env.DOCKER_HOST) || docker([
    "context", "inspect", "--format", "{{.Endpoints.docker.Host}}",
  ]);
  const allowed = platform() === "win32"
    ? /^npipe:\/\/\/\/\.\/pipe\/(?:docker_engine|dockerDesktopLinuxEngine)$/i
    : /^unix:\/\/\/(?:var\/run\/docker\.sock|run\/user\/\d+\/docker\.sock)$/;
  if (!allowed.test(host)) throw new Error("La simulación requiere el Docker local.");
  return host;
}

function database(host, statement, values = {}) {
  return docker([
    "--host", host, "exec", "-i", dbContainer, "psql", "-X", "-U", "supabase_admin", "-d", "postgres", "-Atq",
    "-v", "ON_ERROR_STOP=1",
    ...Object.entries(values).flatMap(([name, value]) => ["-v", name + "=" + value]),
  ], "set role dondepido_notice_dispatcher;\n" + statement);
}

function message(notice) {
  const items = notice.items.map((item) => {
    const parts = item.components.map((part) => part.quantity + " × " + part.name);
    return "• " + item.quantity + " × " + item.name + (parts.length ? " (" + parts.join(", ") + ")" : "");
  });
  const address = (notice.mode === "delivery" ? "Envío a " : "Retiro en ") + notice.address;
  const contact = notice.contact
    ? "Para coordinar, contactá al comercio al " + notice.contact + "."
    : "Consultá los datos de coordinación en el detalle del pedido.";
  return [
    "Tu pedido #" + notice.orderId + " en " + notice.businessName + " está confirmado.",
    address,
    "",
    ...items,
    "",
    contact,
  ].join("\n");
}

async function send(notice) {
  const response = await fetch(mailpitSend, {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(5_000),
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      From: { Email: "dondepido-local@example.invalid" },
      To: [{ Email: "whatsapp-local@example.invalid" }],
      Subject: "DondePido WhatsApp local " + notice.orderId,
      Text: "Simulación local de WhatsApp para " + notice.recipient + "\n\n" + message(notice),
    }),
  });
  await response.body?.cancel();
  if (!response.ok) throw new Error("Mailpit no confirmó la captura.");
}

async function main() {
  const { values } = parseArgs({
    options: { limit: { type: "string", default: "10" }, order: { type: "string" }, twilio: { type: "string" } },
  });
  if (!/^(?:[1-9]|[1-4][0-9]|50)$/.test(values.limit)
    || (values.order !== undefined && !uuidPattern.test(values.order))
    || (values.twilio !== undefined && (!["sandbox", "template"].includes(values.twilio) || !values.order))) {
    throw new Error("Uso: node scripts/dispatch-notices-local.mjs [--limit 1-50] [--order UUID] [--twilio sandbox|template]");
  }
  const transport = values.twilio ? createTwilioTransport(values.twilio) : null;
  const host = localDockerHost();

  const counts = { sent: 0, cancelled: 0, uncertain: 0 };
  for (let index = 0; index < Number(values.limit); index++) {
    const notice = JSON.parse(database(host,
      transport
        ? "select dondepido.claim_test_notice(:'order_id'::uuid, :'recipient');"
        : "select dondepido.claim_local_notice(nullif(:'order_id', '')::uuid);",
      { order_id: values.order ?? "", ...(transport ? { recipient: transport.recipient } : {}) },
    ));
    if (notice.status === "empty") break;
    if (notice.status === "cancelled") {
      counts.cancelled++;
      continue;
    }

    let outcome = "sent";
    let accepted;
    try {
      if (transport) accepted = await transport.send(notice, message(notice));
      else await send(notice);
    } catch {
      outcome = "uncertain";
      if (transport) console.error("No se pudo confirmar la aceptación en Twilio. Revisá Messaging Logs antes de reintentar.");
    }
    const resolved = database(host, "select dondepido.finish_local_notice(:'order_id'::uuid, :'claim'::uuid, :'outcome');", {
      order_id: notice.orderId, claim: notice.claimToken, outcome,
    });
    if (resolved !== "t") throw new Error("No se pudo registrar el resultado de la simulación.");
    if (accepted) console.log(`Twilio aceptó el mensaje ${accepted.sid} con estado ${accepted.status}. Verificá su entrega en Messaging Logs.`);
    counts[outcome]++;
    if (outcome === "uncertain") break;
  }
  console.log((transport ? "Prueba de WhatsApp. Aceptados: " : "Simulación local en Mailpit. Capturados: ") + counts.sent
    + ", cancelados: " + counts.cancelled + ", resultado incierto: " + counts.uncertain + ".");
  if (counts.uncertain) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
