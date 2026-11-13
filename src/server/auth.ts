import { HttpError, isRecord, isUuid, serviceFetch, serviceOrigin } from "./http";

export type Actor = {
  id: string;
  aal: "aal1" | "aal2";
  email: string;
};

export function supabaseOrigin(): URL {
  return serviceOrigin(process.env.DONDEP_SUPABASE_URL);
}

export function supabaseHeaders(token: string): Record<string, string> {
  const apiKey = process.env.DONDEP_SUPABASE_PUBLIC_KEY;
  if (!apiKey) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "Falta configurar el acceso.");
  }
  return { apikey: apiKey, Authorization: `Bearer ${token}` };
}

function invalidSession(): HttpError {
  return new HttpError(401, "SESION_REQUERIDA", "Ingresá con una sesión válida.");
}

export async function authenticate(request: Request): Promise<{ actor: Actor; token: string }> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.length <= 8192
    ? /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/i.exec(header)?.[1]
    : undefined;
  if (!token) throw invalidSession();

  // Auth verifies this exact token before its claims are used below.
  const response = await serviceFetch(new URL("/auth/v1/user", supabaseOrigin()), {
    headers: supabaseHeaders(token),
  });
  if (response.status === 401 || response.status === 403) throw invalidSession();
  if (response.status === 429) {
    throw new HttpError(429, "LIMITE", "Esperá antes de volver a intentar.");
  }
  if (!response.ok) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "No pudimos verificar la sesión.");
  }

  const user: unknown = await response.json();
  if (!isRecord(user) || !isUuid(user.id) || user.is_anonymous === true) throw invalidSession();
  if (typeof user.email !== "string" || !user.email.trim() ||
      typeof user.email_confirmed_at !== "string" || !user.email_confirmed_at) {
    throw new HttpError(403, "CORREO_SIN_CONFIRMAR", "Confirmá el correo antes de continuar.");
  }

  const [, payload] = token.split(".");
  let claims: unknown;
  try {
    claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  } catch {
    throw invalidSession();
  }
  if (!isRecord(claims) || claims.sub !== user.id || claims.role !== "authenticated" ||
      claims.is_anonymous === true || (claims.aal !== "aal1" && claims.aal !== "aal2")) {
    throw invalidSession();
  }

  return { actor: { id: user.id, email: user.email.trim().toLowerCase(), aal: claims.aal }, token };
}
