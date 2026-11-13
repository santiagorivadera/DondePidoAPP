import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, writeFileSync } from 'node:fs';

const dbContainer = 'supabase_db_dondepido-local';
const supabaseUrl = 'http://127.0.0.1:55421';
const mailpitUrl = 'http://127.0.0.1:55424';

function run(command, args, input) {
  const result = spawnSync(command, args, { input, encoding: 'utf8', windowsHide: true });
  if (result.status !== 0) {
    throw new Error(`Falló ${command}. Comprobá que Supabase local esté iniciado.`);
  }
  return result.stdout;
}

try {
  if (existsSync('.env.local')) {
    console.log('La configuración .env.local ya existe.');
    process.exit(0);
  }

  const status = JSON.parse(run('supabase', ['status', '--output', 'json']));
  const apiUrl = new URL(status.API_URL);
  if (!['127.0.0.1', 'localhost'].includes(apiUrl.hostname) || apiUrl.port !== '55421') {
    throw new Error('La configuración activa no corresponde a Supabase local de DondePido.');
  }
  const publicKey = status.PUBLISHABLE_KEY || status.ANON_KEY;
  if (typeof publicKey !== 'string' || !/^[A-Za-z0-9._-]+$/.test(publicKey)) {
    throw new Error('Supabase local no devolvió una clave pública válida.');
  }

  const password = randomBytes(32).toString('hex');
  const hmacKey = randomBytes(32).toString('hex');
  run('docker', ['exec', '-i', dbContainer, 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-q'], `
    begin;
    do $$ begin
      if not exists (select 1 from pg_roles where rolname = 'dondepido_local_app') then
        create role dondepido_local_app login noinherit nobypassrls;
      end if;
    end $$;
    alter role dondepido_local_app password '${password}';
    grant dondepido_backend to dondepido_local_app with inherit false, set true;
    commit;
  `);

  writeFileSync('.env.local', [
    `DONDEP_DB_URL=postgresql://dondepido_local_app:${password}@127.0.0.1:55422/postgres`,
    `DONDEP_SUPABASE_URL=${supabaseUrl}`,
    `DONDEP_SUPABASE_PUBLIC_KEY=${publicKey}`,
    `DONDEP_PHONE_HMAC_KEY=${hmacKey}`,
    `DONDEP_LOCAL_MAILPIT_URL=${mailpitUrl}`,
    '',
  ].join('\n'), { flag: 'wx' });
  console.log('Configuración local creada en .env.local.');
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Falló la configuración local.');
  process.exitCode = 1;
}
