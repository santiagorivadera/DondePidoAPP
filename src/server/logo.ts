import { randomUUID } from "node:crypto";
import { supabaseHeaders, supabaseOrigin, type Actor } from "./auth";
import { HttpError, requiredText, serviceFetch } from "./http";

const LOGO_BUCKET = "dondepido-business-logos";
const MAX_LOGO_BYTES = 256 * 1024;
const LOGO_TYPES = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
} as const;

function invalidLogo(): HttpError {
  return new HttpError(400, "LOGO_INVALIDO", "Elegí un logo PNG, JPEG o WebP de hasta 256 KiB.");
}

export function matchesImageSignature(mimeType: string, data: Buffer): boolean {
  switch (mimeType) {
    case "image/png":
      return data.length >= 33 && data.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex")) &&
        data.subarray(12, 16).toString("ascii") === "IHDR";
    case "image/jpeg":
      return data.length >= 4 && data.subarray(0, 3).equals(Buffer.from("ffd8ff", "hex")) &&
        data.subarray(-2).equals(Buffer.from("ffd9", "hex"));
    case "image/webp":
      return data.length >= 20 && data.subarray(0, 4).toString("ascii") === "RIFF" &&
        data.subarray(8, 12).toString("ascii") === "WEBP" && data.readUInt32LE(4) === data.length - 8 &&
        ["VP8 ", "VP8L", "VP8X"].includes(data.subarray(12, 16).toString("ascii"));
    default:
      return false;
  }
}

function logoUrl(key: string): URL {
  return new URL(`/storage/v1/object/${LOGO_BUCKET}/${key}`, supabaseOrigin());
}

function checkStoredLogo(response: Response, expectedType: string): void {
  if (response.status >= 500) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos verificar el logo.");
  }
  if (!response.ok) throw invalidLogo();
  const contentType = response.headers.get("content-type")?.split(";")[0].trim().toLowerCase();
  const contentLength = response.headers.get("content-length");
  if ((contentType && contentType !== expectedType) ||
      (contentLength !== null && !(Number(contentLength) > 0 && Number(contentLength) <= MAX_LOGO_BYTES))) {
    throw invalidLogo();
  }
}

export async function uploadLogo(actor: Actor, token: string, input: Record<string, unknown>) {
  const mimeType = input.mimeType;
  if (mimeType !== "image/png" && mimeType !== "image/jpeg" && mimeType !== "image/webp") {
    throw invalidLogo();
  }
  const base64 = input.base64;
  if (typeof base64 !== "string" || base64.length > 4 * Math.ceil(MAX_LOGO_BYTES / 3) ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    throw invalidLogo();
  }
  const bytes = Buffer.from(base64, "base64");
  if (bytes.length > MAX_LOGO_BYTES || bytes.toString("base64") !== base64 ||
      !matchesImageSignature(mimeType, bytes)) {
    throw invalidLogo();
  }

  const key = `${actor.id}/${randomUUID()}.${LOGO_TYPES[mimeType]}`;
  const response = await serviceFetch(logoUrl(key), {
    method: "POST",
    headers: { ...supabaseHeaders(token), "Content-Type": mimeType, "Cache-Control": "no-store" },
    body: new Uint8Array(bytes),
  });
  if (!response.ok) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos guardar el logo.");
  }
  return key;
}

export async function verifyLogo(actor: Actor, token: string, value: unknown): Promise<string> {
  const key = requiredText(value, "logo", 90);
  const parts = key.split("/");
  const file = /^([0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\.(png|jpe?g|webp)$/.exec(parts[1] ?? "");
  if (parts.length !== 2 || parts[0] !== actor.id || !file) throw invalidLogo();

  const expectedType = file[2] === "jpg" || file[2] === "jpeg" ? "image/jpeg" : `image/${file[2]}`;
  const url = logoUrl(key);
  const headers = supabaseHeaders(token);
  checkStoredLogo(await serviceFetch(url, { method: "HEAD", headers }), expectedType);

  // Check the bytes again because the owner can upload directly to Storage.
  const response = await serviceFetch(url, { headers });
  const reader = response.body?.getReader();
  if (!reader) throw invalidLogo();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    checkStoredLogo(response, expectedType);
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > MAX_LOGO_BYTES) throw invalidLogo();
      chunks.push(chunk.value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    if (error instanceof HttpError) throw error;
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos verificar el logo.");
  } finally {
    reader.releaseLock();
  }
  if (!matchesImageSignature(expectedType, Buffer.concat(chunks))) throw invalidLogo();
  return key;
}
