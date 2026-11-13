import { spawnSync } from 'node:child_process';

const email = process.argv[2]?.trim().toLowerCase();
if (process.argv.length !== 3 || !email || email.length > 254 || !/^[^@\s]+@[^@\s]+$/.test(email)) {
  console.error('Uso: npm run local:admin -- correo-de-la-cuenta');
  process.exitCode = 1;
} else {
  const result = spawnSync('docker', [
    'exec', '-i', 'supabase_db_dondepido-local', 'psql', '-U', 'supabase_admin', '-d', 'postgres',
    '-Atq', '-v', 'ON_ERROR_STOP=1', '-v', `admin_email=${email}`,
  ], {
    input: `insert into dondepido.admin_roles (user_id)
      select id from auth.users
      where lower(email) = :'admin_email' and email_confirmed_at is not null
      on conflict (user_id) do update set revoked_at = null
      returning true;`,
    encoding: 'utf8', windowsHide: true,
  });
  if (result.status !== 0 || result.stdout.trim() !== 't') {
    console.error('No se encontró una cuenta confirmada en Supabase local o falló la asignación.');
    process.exitCode = 1;
  } else {
    console.log('Administración local habilitada. Ingresá con MFA para usarla.');
  }
}
