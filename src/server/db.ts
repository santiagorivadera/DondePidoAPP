import { Pool } from "pg";
import type { Actor } from "./auth";
import { HttpError } from "./http";

let pool: Pool | undefined;

function getPool(): Pool {
  const connectionString = process.env.DONDEP_DB_URL;
  if (!connectionString) {
    throw new HttpError(503, "SERVICIO_NO_DISPONIBLE", "Falta configurar la base de datos.");
  }
  if (!pool) {
    pool = new Pool({ connectionString, connectionTimeoutMillis: 5000, statement_timeout: 10_000, max: 5 });
    pool.on("error", () => console.warn("Se descartó una conexión inactiva de PostgreSQL."));
  }
  return pool;
}

type Parameter = string | number | boolean | null;

export async function runOnboarding<T>(
  actor: Actor | null,
  sql: string,
  params: Parameter[] = [],
): Promise<T> {
  const client = await getPool().connect();
  let failedRollback = false;
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE dondepido_backend");
    await client.query(
      `select set_config('dondepido.actor_id', $1, true),
              set_config('dondepido.actor_aal', $2, true),
              set_config('dondepido.actor_email', $3, true)`,
      [actor?.id ?? "", actor?.aal ?? "", actor?.email ?? ""],
    );
    const result = await client.query<{ data: T }>(sql, params);
    await client.query("COMMIT");
    return result.rows[0].data;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch {
      failedRollback = true;
    }
    throw error;
  } finally {
    client.release(failedRollback);
  }
}
