import { authenticate } from "../../../src/server/auth";
import { runOnboarding } from "../../../src/server/db";
import { HttpError, isRecord, readJsonObject } from "../../../src/server/http";

export const runtime = "nodejs";

const operations = {
  catalog: new Set(["mine", "save", "availability", "discount", "reference", "reception", "delivery"]),
  orders: new Set(["quote", "submit", "mine", "inbox", "decide", "complete", "cancel", "propose", "respond", "consent", "stats"]),
};

function marketError(error: unknown): HttpError {
  if (error instanceof HttpError) return error;
  switch (isRecord(error) ? error.code : undefined) {
    case "42501":
      return new HttpError(403, "SIN_ACCESO", "No tenés permiso para realizar esta acción.");
    case "22023":
    case "22P02":
    case "23502":
    case "23514":
      return new HttpError(400, "VALIDACION", "Revisá los datos ingresados.");
    case "P0002":
      return new HttpError(404, "NO_ENCONTRADO", "El recurso ya no está disponible.");
    case "55000":
    case "23505":
    case "23503":
    case "40001":
      return new HttpError(409, "ESTADO_EN_CONFLICTO", "Hubo un cambio. Actualizá los datos y volvé a intentar.");
    case "40P01":
      return new HttpError(503, "FALLO_TRANSITORIO", "Volvé a intentar en unos instantes.");
    default:
      return new HttpError(500, "ERROR_INTERNO", "No pudimos completar la solicitud.");
  }
}

export async function POST(request: Request): Promise<Response> {
  const headers = { "Cache-Control": "no-store" };
  try {
    const input = await readJsonObject(request);
    const { action, operation, ...values } = input;
    if (action === "browse") {
      if (typeof values.businessId === "string" && values.businessId) {
        const city = typeof values.city === "string" && values.city ? values.city : "dean-funes";
        const data = await runOnboarding(null, "select dondepido.browse_business_catalog($1::uuid, $2) as data", [values.businessId, city]);
        return Response.json({ data }, { headers });
      }
      const data = await runOnboarding(null, "select dondepido.browse_catalog($1::jsonb) as data", [JSON.stringify(values)]);
      return Response.json({ data }, { headers });
    }
    if (action === "admin.businesses") {
      const { actor } = await authenticate(request);
      const data = await runOnboarding(actor, `
        select case when dondepido.actor_is_admin() then jsonb_build_object('businesses', (
          select coalesce(jsonb_agg(items order by name, id), '[]'::jsonb)
          from (
            select id, name, sector_code, publication_status, admin_hidden, relevance, control_version::text
            from dondepido.businesses order by name, id limit 100
          ) items
        )) end as data
      `);
      if (!data) throw new HttpError(403, "SIN_ACCESO", "Se requiere acceso de administración.");
      return Response.json({ data }, { headers });
    }
    if ((action !== "catalog" && action !== "orders") ||
        typeof operation !== "string" || !operations[action].has(operation)) {
      throw new HttpError(400, "VALIDACION", "Elegí una operación válida.");
    }
    const { actor } = await authenticate(request);
    if (action === "orders" && operation === "stats") {
      if (typeof values.businessId !== "string" || !values.businessId) {
        throw new HttpError(400, "VALIDACION", "Elegí un comercio válido.");
      }
      const data = await runOnboarding(actor, "select dondepido.order_stats($1::uuid) as data", [values.businessId]);
      return Response.json({ data }, { headers });
    }
    const query = action === "catalog"
      ? "select dondepido.manage_catalog($1::jsonb) as data"
      : "select dondepido.manage_orders($1::jsonb) as data";
    const data = await runOnboarding(actor, query, [JSON.stringify({ ...values, action: operation })]);
    return Response.json({ data }, { headers });
  } catch (error) {
    const { status, code, message } = marketError(error);
    return Response.json({ error: { code, message } }, { status, headers });
  }
}
