import { authenticate } from "../../../src/server/auth";
import { adminFeatured, maxFeaturedRequestBytes, publicFeatured, publicFeaturedImage } from "../../../src/server/featured";
import { HttpError, isRecord, readJsonObject, uuid } from "../../../src/server/http";

export const runtime = "nodejs";

const headers = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };

function errorResponse(error: unknown) {
  if (error instanceof HttpError) {
    return Response.json({ error: { code: error.code, message: error.message } }, { status: error.status, headers });
  }
  const code = isRecord(error) ? error.code : undefined;
  switch (code) {
    case "42501":
      return errorResponse(new HttpError(403, "SIN_ACCESO", "No tenés permiso para realizar esta acción."));
    case "22007":
    case "22008":
    case "22023":
    case "22P02":
    case "23514":
      return errorResponse(new HttpError(400, "VALIDACION", "Revisá los datos ingresados."));
    case "P0002":
      return errorResponse(new HttpError(404, "NO_ENCONTRADO", "La promoción o el comercio no está disponible."));
    case "23505":
    case "23503":
    case "55000":
      return errorResponse(new HttpError(409, "ESTADO_EN_CONFLICTO", "Hubo un cambio. Actualizá los datos y volvé a intentar."));
    default:
      console.warn("Error en promociones destacadas", error instanceof Error ? error.name : typeof error, code);
      return errorResponse(new HttpError(500, "ERROR_INTERNO", "No pudimos completar la solicitud."));
  }
}

export async function GET(request: Request): Promise<Response> {
  try {
    const image = new URL(request.url).searchParams.get("image");
    if (image === null) return Response.json({ data: await publicFeatured() }, { headers });
    const { bytes, mimeType } = await publicFeaturedImage(uuid(image, "imagen"));
    return new Response(bytes, {
      headers: { ...headers, "Content-Type": mimeType, "Content-Length": String(bytes.byteLength) },
    });
  } catch (error) {
    return errorResponse(error);
  }
}

export async function POST(request: Request): Promise<Response> {
  try {
    const { actor, token } = await authenticate(request);
    const input = await readJsonObject(request, maxFeaturedRequestBytes);
    return Response.json({ data: await adminFeatured(actor, token, input) }, { headers });
  } catch (error) {
    return errorResponse(error);
  }
}
