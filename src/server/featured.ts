import { randomUUID } from "node:crypto";
import { supabaseHeaders, supabaseOrigin, type Actor } from "./auth";
import { runOnboarding } from "./db";
import { HttpError, isUuid, requiredText, serviceFetch, uuid } from "./http";
import { matchesImageSignature } from "./logo";

const bucket = "dondepido-featured";
const maxImageBytes = 1024 * 1024;
const maxBase64Length = 4 * Math.ceil(maxImageBytes / 3);
export const maxFeaturedRequestBytes = maxBase64Length + 8192;

const imageTypes = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
} as const;
type MimeType = keyof typeof imageTypes;
type Banner = {
  id: string;
  title: string;
  business_id: string;
  business_name: string;
  sector: string;
  has_image: boolean;
};

function isMimeType(value: unknown): value is MimeType {
  return typeof value === "string" && Object.hasOwn(imageTypes, value);
}

function imageUnavailable(): HttpError {
  return new HttpError(404, "NO_ENCONTRADO", "La imagen no está disponible.");
}

function objectUrl(key: string): URL {
  return new URL(`/storage/v1/object/${bucket}/${key}`, supabaseOrigin());
}

export async function publicFeatured() {
  const { banners } = await runOnboarding<{ banners: Banner[] }>(null, "select dondepido.featured_list() as data");
  return {
    banners: banners.map(({ id, title, business_id, business_name, sector, has_image }) => ({
      id, title, business_id, business_name, sector,
      image_url: has_image ? `/api/featured?image=${encodeURIComponent(id)}` : "",
    })),
  };
}

export async function publicFeaturedImage(id: string) {
  const image = await runOnboarding<{ object_key: string; mime_type: string } | null>(
    null, "select dondepido.featured_image($1::uuid) as data", [id],
  );
  if (!image || typeof image.object_key !== "string" || !isMimeType(image.mime_type)) throw imageUnavailable();
  const [owner, file, extra] = image.object_key.split("/");
  const [name, extension, suffix] = file?.split(".") ?? [];
  if (!isUuid(owner) || !isUuid(name) || suffix !== undefined || extra !== undefined ||
      (extension !== imageTypes[image.mime_type] && !(image.mime_type === "image/jpeg" && extension === "jpeg"))) {
    throw imageUnavailable();
  }
  const publicKey = process.env.DONDEP_SUPABASE_PUBLIC_KEY;
  if (!publicKey) throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "Falta configurar el acceso.");

  const url = new URL(`/storage/v1/object/authenticated/${bucket}/${image.object_key}`, supabaseOrigin());
  const response = await serviceFetch(url, { headers: supabaseHeaders(publicKey) });
  const reader = response.body?.getReader();
  if (!reader) throw imageUnavailable();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    if (response.status >= 500) {
      throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos cargar la imagen.");
    }
    const length = response.headers.get("content-length");
    if (!response.ok || response.headers.get("content-type")?.split(";")[0].trim() !== image.mime_type ||
        (length !== null && !(Number(length) > 0 && Number(length) <= maxImageBytes))) {
      throw imageUnavailable();
    }
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > maxImageBytes) throw imageUnavailable();
      chunks.push(chunk.value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    if (error instanceof HttpError) throw error;
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos cargar la imagen.");
  } finally {
    reader.releaseLock();
  }
  const bytes = Buffer.concat(chunks);
  if (!matchesImageSignature(image.mime_type, bytes)) throw imageUnavailable();
  return { bytes: new Uint8Array(bytes), mimeType: image.mime_type };
}

function imageInput(input: Record<string, unknown>): { mimeType: MimeType; bytes: Uint8Array<ArrayBuffer> } {
  const { mimeType, base64 } = input;
  const invalidImage = () => new HttpError(400, "IMAGEN_INVALIDA", "Elegí una imagen PNG, JPEG o WebP de hasta 1 MiB.");
  if (!isMimeType(mimeType) || typeof base64 !== "string" || base64.length > maxBase64Length ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    throw invalidImage();
  }
  const bytes = Buffer.from(base64, "base64");
  if (bytes.length > maxImageBytes || bytes.toString("base64") !== base64 || !matchesImageSignature(mimeType, bytes)) {
    throw invalidImage();
  }
  return { mimeType, bytes: new Uint8Array(bytes) };
}

function scheduleDate(value: unknown, label: string): string | null | undefined {
  if (value === undefined || value === null) return value;
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
      Number.isFinite(Date.parse(value))) return value;
  throw new HttpError(400, "VALIDACION", `Revisá la fecha de ${label}.`);
}

function adminFields(input: Record<string, unknown>, requireTitle: boolean) {
  const { position, enabled } = input;
  if (position !== undefined && (typeof position !== "number" || !Number.isInteger(position) || position < 0 || position > 9999)) {
    throw new HttpError(400, "VALIDACION", "Revisá la posición.");
  }
  if (enabled !== undefined && typeof enabled !== "boolean") {
    throw new HttpError(400, "VALIDACION", "Revisá el estado de la promoción.");
  }
  const startsAt = scheduleDate(input.startsAt, "inicio");
  const endsAt = scheduleDate(input.endsAt, "fin");
  if (startsAt && endsAt && Date.parse(startsAt) >= Date.parse(endsAt)) {
    throw new HttpError(400, "VALIDACION", "La fecha de fin debe ser posterior al inicio.");
  }
  const title = requireTitle || input.title !== undefined ? requiredText(input.title, "título", 120) : undefined;
  return { title, position, enabled, startsAt, endsAt };
}

function executeAdmin(actor: Actor, input: Record<string, unknown>) {
  return runOnboarding(actor, "select dondepido.manage_featured($1::jsonb) as data", [JSON.stringify(input)]);
}

async function compensateUpload(url: URL, token: string): Promise<void> {
  try {
    const response = await serviceFetch(url, { method: "DELETE", headers: supabaseHeaders(token) });
    await response.body?.cancel();
    if (response.ok || response.status === 404) return;
  } catch {
    // Preserve the original error. Storage only permits deleting this actor's unreferenced object.
  }
  console.warn("No se pudo retirar una imagen pendiente de promoción destacada.");
}

export async function adminFeatured(actor: Actor, token: string, input: Record<string, unknown>) {
  const denied = () => new HttpError(403, "SIN_ACCESO", "Esta acción requiere administración y verificación en dos pasos.");
  if (actor.aal !== "aal2") throw denied();
  switch (input.action) {
    case "admin.list":
      return executeAdmin(actor, { action: "list" });

    case "admin.update":
      return executeAdmin(actor, {
        action: "update", id: uuid(input.id, "promoción"), ...adminFields(input, false),
      });

    case "admin.create": {
      const fields = adminFields(input, true);
      const businessId = uuid(input.businessId, "comercio");
      const { mimeType, bytes } = imageInput(input);
      const authorized = await runOnboarding<boolean>(actor, "select dondepido.actor_is_admin() as data");
      if (!authorized) throw denied();
      const imageKey = `${actor.id}/${randomUUID()}.${imageTypes[mimeType]}`;
      const url = objectUrl(imageKey);
      try {
        const response = await serviceFetch(url, {
          method: "POST",
          headers: { ...supabaseHeaders(token), "Content-Type": mimeType, "Cache-Control": "max-age=0, no-store" },
          body: bytes,
        });
        await response.body?.cancel();
        if (!response.ok) {
          throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos guardar la imagen.");
        }
        return await executeAdmin(actor, { action: "create", ...fields, businessId, imageKey, mimeType });
      } catch (error) {
        await compensateUpload(url, token);
        throw error;
      }
    }

    default:
      throw new HttpError(400, "VALIDACION", "Elegí una acción válida.");
  }
}
