import { authenticate, type Actor } from "../../../src/server/auth";
import { runOnboarding } from "../../../src/server/db";
import { normalizeWeeklyHours } from "../../../src/server/hours";
import { HttpError, isRecord, readJsonObject, requiredText, uuid } from "../../../src/server/http";
import { uploadLogo, verifyLogo } from "../../../src/server/logo";
import { issuePhoneChallenge, verifyPhoneChallenge } from "../../../src/server/phone";

export const runtime = "nodejs";

function denied(): HttpError {
  return new HttpError(403, "SIN_ACCESO", "No tenés permiso para realizar esta acción.");
}

function requireMfa(actor: Actor): void {
  if (actor.aal !== "aal2") throw denied();
}

function applicationSector(value: unknown): "gastronomia" | "kioscos" {
  if (value !== "gastronomia" && value !== "kioscos") {
    throw new HttpError(400, "VALIDACION", "Elegí un rubro válido.");
  }
  return value;
}

async function requestApplication(input: Record<string, unknown>): Promise<null> {
  const email = requiredText(input.email, "correo", 254).toLowerCase();
  if (!/^[^@\s]+@[^@\s]+$/.test(email) || email.length > 254) {
    throw new HttpError(400, "VALIDACION", "Ingresá un correo válido.");
  }
  await runOnboarding(null, "select dondepido.request_application($1, $2, $3) as data", [
    email,
    applicationSector(input.sector),
    requiredText(input.observation, "observación", 2000),
  ]);
  return null;
}

function publicReference() {
  return runOnboarding(null, `
    select json_build_object(
      'cities', (
        select coalesce(json_agg(cities order by cities.name, cities.id), '[]'::json)
        from (select id, slug, name from dondepido.cities where enabled) as cities
      ),
      'sectors', (
        select coalesce(json_agg(sectors order by sectors.name, sectors.code), '[]'::json)
        from (select code, name from dondepido.business_sectors) as sectors
      )
    ) as data
  `);
}

function businessControlVersion(value: unknown): string {
  const version = typeof value === "number" && Number.isSafeInteger(value) ? String(value) : value;
  if (typeof version !== "string" || !/^[1-9][0-9]{0,18}$/.test(version) ||
      BigInt(version) > 9_223_372_036_854_775_807n) {
    throw new HttpError(400, "VALIDACION", "Revisá la versión del comercio.");
  }
  return version;
}

async function execute(actor: Actor, token: string, input: Record<string, unknown>) {
  switch (input.action) {
    case "profile.mine":
      return runOnboarding(actor, `
        select json_build_object(
          'profile', (select json_build_object('firstName', first_name, 'lastName', last_name)
                      from dondepido.profiles where user_id = $1::uuid),
          'phone', (select phone_e164 from dondepido.verified_phones where user_id = $1::uuid)
        ) as data
      `, [actor.id]);

    case "profile":
      await runOnboarding(actor, "select dondepido.save_profile($1, $2) as data", [
        requiredText(input.firstName, "nombre", 100),
        requiredText(input.lastName, "apellido", 100),
      ]);
      return null;

    case "phone.issue":
      return issuePhoneChallenge(actor, input);

    case "phone.verify":
      return verifyPhoneChallenge(actor, input);

    case "application.submit":
      return runOnboarding<string>(actor, "select dondepido.submit_application($1, $2) as data", [
        applicationSector(input.sector),
        requiredText(input.observation, "observación", 2000),
      ]);

    case "application.mine":
      return runOnboarding<unknown[]>(actor, `
        select coalesce(json_agg(items order by items.created_at desc, items.id desc), '[]'::json) as data
        from (
          select id, sector_code, status, expires_at, created_at
          from dondepido.my_applications()
          order by created_at desc, id desc
          limit 100
        ) as items
      `);

    case "application.inbox": {
      requireMfa(actor);
      const result = await runOnboarding<unknown[] | null>(actor, `
        select case when dondepido.actor_is_admin() then (
          select coalesce(json_agg(items order by items.created_at desc, items.id desc), '[]'::json)
          from (
            select id, email, sector_code, observation, city_id, created_at, expires_at,
                   case when status = 'approved' and expires_at <= statement_timestamp()
                        then 'expired' else status end as status
            from dondepido.business_applications
            order by created_at desc, id desc
            limit 100
          ) as items
        ) end as data
      `);
      if (result === null) throw denied();
      return result;
    }

    case "application.decide": {
      requireMfa(actor);
      const decision = input.decision;
      if (decision !== "approved" && decision !== "rejected" && decision !== "revoked") {
        throw new HttpError(400, "VALIDACION", "Elegí una decisión válida.");
      }
      await runOnboarding(actor, "select dondepido.decide_application($1::uuid, $2, $3::uuid, $4) as data", [
        uuid(input.applicationId, "solicitud"),
        decision,
        decision === "approved" ? uuid(input.cityId, "ciudad") : null,
        requiredText(input.reason, "motivo", 1000),
      ]);
      return null;
    }

    case "logo.upload":
      return uploadLogo(actor, token, input);

    case "application.complete": {
      const applicationId = uuid(input.applicationId, "solicitud");
      const name = requiredText(input.name, "nombre del comercio", 160);
      const address = requiredText(input.address, "dirección", 400);
      const logo = await verifyLogo(actor, token, input.logo);
      return runOnboarding<string>(
        actor,
        "select dondepido.complete_application($1::uuid, $2, $3, $4) as data",
        [applicationId, name, address, logo],
      );
    }

    case "business.mine":
      return runOnboarding<unknown[]>(actor, `
        select coalesce(json_agg(items order by items.created_at desc, items.id desc), '[]'::json) as data
        from (
          select b.id, b.name, b.address, b.sector_code, b.city_id, b.publication_status,
                 b.admin_hidden, b.accepting_orders, b.offers_pickup, b.offers_delivery, b.delivery_fee,
                 b.relevance, b.control_version::text,
                 b.created_at, m.role
          from dondepido.businesses as b
          join dondepido.business_memberships as m on m.business_id = b.id
          where m.user_id = $1::uuid and m.revoked_at is null
          order by b.created_at desc, b.id desc
          limit 100
        ) as items
      `, [actor.id]);

    case "business.publish":
      if (typeof input.pickup !== "boolean" || typeof input.delivery !== "boolean" ||
          (!input.pickup && !input.delivery) || input.confirmPublicContact !== true) {
        throw new HttpError(400, "VALIDACION", "Elegí una modalidad y confirmá el contacto comercial público.");
      }
      await runOnboarding(actor, "select dondepido.publish_business($1::uuid, $2, $3) as data", [
        uuid(input.businessId, "comercio"),
        input.pickup,
        input.delivery,
      ]);
      return null;

    case "business.hours":
      await runOnboarding(actor, "select dondepido.set_business_weekly_hours($1::uuid, $2::jsonb) as data", [
        uuid(input.businessId, "comercio"),
        JSON.stringify(normalizeWeeklyHours(input.hours)),
      ]);
      return null;

    case "business.controls": {
      requireMfa(actor);
      const hidden = input.hidden ?? null;
      const relevance = input.relevance ?? null;
      if ((hidden !== null && typeof hidden !== "boolean") ||
          (relevance !== null && (typeof relevance !== "number" || !Number.isInteger(relevance) ||
            relevance < 1 || relevance > 100)) ||
          (hidden === null && relevance === null)) {
        throw new HttpError(400, "VALIDACION", "Revisá la visibilidad y la relevancia del comercio.");
      }
      return runOnboarding(actor, `
        select row_to_json(controls) as data
        from (
          select id, admin_hidden, relevance, control_version::text
          from dondepido.set_business_controls($1::uuid, $2::bigint, $3, $4, $5)
        ) as controls
      `, [
        uuid(input.businessId, "comercio"),
        businessControlVersion(input.expectedVersion),
        hidden,
        relevance,
        input.note == null ? null : requiredText(input.note, "nota", 1000),
      ]);
    }

    default:
      throw new HttpError(400, "VALIDACION", "Elegí una acción válida.");
  }
}

function errorForResponse(error: unknown): HttpError {
  if (error instanceof HttpError) return error;
  const code = isRecord(error) ? error.code : undefined;
  switch (code) {
    case "42501":
      return denied();
    case "22023":
    case "22P02":
    case "23514":
      return new HttpError(400, "VALIDACION", "Revisá los datos de la solicitud.");
    case "P0002":
      return new HttpError(404, "NO_ENCONTRADO", "No encontramos el recurso.");
    case "55000":
    case "23505":
    case "40001":
      return new HttpError(409, "ESTADO_EN_CONFLICTO", "El estado actual impide completar esta acción.");
    case "54000":
      return new HttpError(429, "LIMITE", "Esperá antes de volver a intentar.");
    case "40P01":
    case "57014":
      return new HttpError(503, "FALLO_TRANSITORIO", "Volvé a intentar en unos instantes.");
    default:
      return new HttpError(500, "ERROR_INTERNO", "No pudimos completar la solicitud.");
  }
}

export async function POST(request: Request): Promise<Response> {
  const headers = { "Cache-Control": "no-store" };
  try {
    const input = await readJsonObject(request);
    if (input.action === "application.request") {
      return Response.json({ data: await requestApplication(input) }, { headers });
    }
    if (input.action === "reference") {
      return Response.json({ data: await publicReference() }, { headers });
    }
    const { actor, token } = await authenticate(request);
    return Response.json({ data: await execute(actor, token, input) }, { headers });
  } catch (error) {
    const { status, code, message } = errorForResponse(error);
    return Response.json({ error: { code, message } }, { status, headers });
  }
}
