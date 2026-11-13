import { supabaseOrigin } from "../../../src/server/auth";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function isPublicKey(key: string): boolean {
  if (/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) return true;
  const parts = key.split(".");
  if (parts.length !== 3) return false;
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"))?.role === "anon";
  } catch {
    return false;
  }
}

export function GET(): Response {
  const headers = { "Cache-Control": "no-store" };
  const publicKey = process.env.DONDEP_SUPABASE_PUBLIC_KEY ?? "";
  try {
    const url = supabaseOrigin().origin;
    if (isPublicKey(publicKey)) return Response.json({ url, publicKey }, { headers });
  } catch {
    // Serve the same error for missing and invalid configuration.
  }
  return Response.json({ error: { message: "Falta configurar el acceso." } }, { status: 503, headers });
}
