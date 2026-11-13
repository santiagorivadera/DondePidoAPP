const MAX_REQUEST_BYTES = 360 * 1024;

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function readJsonObject(request: Request, maxBytes = MAX_REQUEST_BYTES) {
  const contentType = request.headers.get("content-type")?.split(";")[0].trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new HttpError(415, "TIPO_NO_ADMITIDO", "El cuerpo debe ser JSON.");
  }
  if (Number(request.headers.get("content-length")) > maxBytes) {
    throw new HttpError(413, "CUERPO_DEMASIADO_GRANDE", "La solicitud excede el tamaño permitido.");
  }

  const reader = request.body?.getReader();
  if (!reader) {
    throw new HttpError(400, "VALIDACION", "Ingresá un objeto JSON válido.");
  }
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        throw new HttpError(413, "CUERPO_DEMASIADO_GRANDE", "La solicitud excede el tamaño permitido.");
      }
      chunks.push(chunk.value);
    }
    const json: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(Buffer.concat(chunks)));
    if (isRecord(json)) return json;
  } catch (error) {
    if (error instanceof HttpError) throw error;
  } finally {
    reader.releaseLock();
  }
  throw new HttpError(400, "VALIDACION", "Ingresá un objeto JSON válido.");
}

export function requiredText(value: unknown, field: string, max: number): string {
  const result = typeof value === "string" ? value.trim() : "";
  if (!result || result.length > max || result.includes("\u0000")) {
    throw new HttpError(400, "VALIDACION", `Revisá el campo ${field}.`);
  }
  return result;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value);
}

export function uuid(value: unknown, field: string): string {
  if (!isUuid(value)) {
    throw new HttpError(400, "VALIDACION", `Revisá el identificador de ${field}.`);
  }
  return value.toLowerCase();
}

export function isLoopback(url: URL): boolean {
  return ["127.0.0.1", "[::1]", "localhost"].includes(url.hostname);
}

export function serviceOrigin(value: string | undefined): URL {
  try {
    const url = new URL(value ?? "");
    if (url.username || url.password || url.pathname !== "/" || url.search || url.hash) {
      throw new Error();
    }
    if (url.protocol === "https:" || (url.protocol === "http:" && isLoopback(url))) return url;
  } catch {
    // A malformed origin must never be used as a request destination.
  }
  throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "Falta configurar un servicio.");
}

export async function serviceFetch(url: URL, init: RequestInit): Promise<Response> {
  try {
    return await fetch(url, {
      ...init,
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos conectar con un servicio. Volvé a intentar.");
  }
}
