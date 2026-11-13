begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

-- The runtime roles use TAP assertions only inside this rolled-back fixture.
grant dondepido_backend, dondepido_catalog_reader to current_user with set true;
grant usage on schema extensions to dondepido_backend, dondepido_catalog_reader;

select plan(19);

insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'operator@example.invalid'),
  ('10000000-0000-0000-0000-000000000002', 'former-operator@example.invalid'),
  ('10000000-0000-0000-0000-000000000003', 'admin@example.invalid');

insert into dondepido.profiles (user_id, first_name, last_name)
select id, 'Persona', 'Ficticia' from auth.users
where id in ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002');

insert into dondepido.verified_phones (user_id, phone_e164, verified_at)
values
  ('10000000-0000-0000-0000-000000000001', '+12025550101', now()),
  ('10000000-0000-0000-0000-000000000002', '+12025550102', now());

insert into dondepido.admin_roles (user_id)
values ('10000000-0000-0000-0000-000000000003');

insert into dondepido.cities (id, slug, name, time_zone, enabled)
values
  ('20000000-0000-0000-0000-000000000001', 'ciudad-activa', 'Ciudad Activa', 'America/Argentina/Buenos_Aires', true),
  ('20000000-0000-0000-0000-000000000002', 'ciudad-desactivada', 'Ciudad Desactivada', 'America/Argentina/Buenos_Aires', false);

insert into dondepido.business_applications (
  id, email, sector_code, observation, status, city_id, decided_by,
  decided_at, decision_reason, expires_at, consumed_by, consumed_at
)
select fixture.id::uuid, fixture.email, 'kioscos', 'Alta ficticia', 'consumed', fixture.city::uuid,
  '10000000-0000-0000-0000-000000000003',
  now() - interval '1 hour', 'Aprobada', now() + interval '1 hour', fixture.user_id::uuid, now()
from (values
  ('30000000-0000-0000-0000-000000000001', 'operator@example.invalid',
    '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002', 'former-operator@example.invalid',
    '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002'),
  ('30000000-0000-0000-0000-000000000003', 'draft@example.invalid',
    '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000004', 'disabled@example.invalid',
    '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002')
) as fixture(id, email, city, user_id);

insert into dondepido.businesses (
  id, application_id, city_id, sector_code, name, address, logo_object_key,
  publication_status, admin_hidden, offers_pickup, contact_phone_e164, contact_verified_at
)
select fixture.id::uuid, applications.id, applications.city_id, applications.sector_code,
  fixture.name, 'Dirección de prueba', 'fixture.webp',
  fixture.status, fixture.hidden, true, '+12025550109', now()
from (values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Local visible', 'published', false),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Local oculto', 'published', true),
  ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', 'Local borrador', 'draft', false),
  ('40000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000004', 'Local en ciudad desactivada', 'published', false)
) as fixture(id, application_id, name, status, hidden)
join dondepido.business_applications as applications on applications.id = fixture.application_id::uuid;

insert into dondepido.business_memberships (business_id, user_id, role, revoked_at)
values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner', null),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'owner', now());

set local role dondepido_catalog_reader;

select results_eq(
  $$select name from dondepido.businesses
    where id between '40000000-0000-0000-0000-000000000001' and '40000000-0000-0000-0000-000000000004'
    order by name$$,
  array['Local visible'],
  'Catalog excludes hidden and draft businesses and businesses in a disabled city'
);

select throws_ok(
  'select contact_phone_e164 from dondepido.businesses',
  '42501', null,
  'The catalog role has no access to private contact columns'
);

set local role dondepido_backend;
set local dondepido.actor_id = '10000000-0000-0000-0000-000000000001';
set local dondepido.actor_aal = 'aal1';

select results_eq(
  $$select profiles.user_id::text, phones.phone_e164
    from dondepido.profiles as profiles
    join dondepido.verified_phones as phones using (user_id)$$,
  $$values ('10000000-0000-0000-0000-000000000001', '+12025550101')$$,
  'A personal session can read its own profile and verified phone only'
);

select is_empty(
  'select id from dondepido.businesses',
  'An operator without a reinforced session cannot read private business rows'
);

set local dondepido.actor_aal = 'aal2';

select results_eq(
  'select name from dondepido.businesses order by name',
  array['Local visible'],
  'A reinforced operator session can read the business covered by its active membership'
);

select throws_ok(
  $$select * from dondepido.set_business_controls('40000000-0000-0000-0000-000000000001', 1, true, null, null)$$,
  '42501', null,
  'An operator cannot change administrative controls even for its own business'
);

select is_empty(
  'select id from dondepido.business_applications',
  'A commercial membership does not grant access to the administrative application inbox'
);

set local dondepido.actor_id = '10000000-0000-0000-0000-000000000002';

select is_empty(
  'select id from dondepido.businesses',
  'A revoked operator loses private business access with the same level of session'
);

set local dondepido.actor_id = '10000000-0000-0000-0000-000000000003';
set local dondepido.actor_aal = 'aal1';

select throws_ok(
  $$select * from dondepido.set_business_controls('40000000-0000-0000-0000-000000000001', 1, true, null, null)$$,
  '42501', null,
  'An administrator without MFA cannot change business controls'
);

set local dondepido.actor_aal = 'aal2';

select results_eq(
  $$select email from dondepido.business_applications
    where id = '30000000-0000-0000-0000-000000000001'$$,
  array['operator@example.invalid'],
  'A reinforced administrator can read the application inbox'
);

select throws_ok(
  $$select * from dondepido.set_business_controls('40000000-0000-0000-0000-000000000001', 1, null, 101, null)$$,
  '22023', null,
  'An out-of-range relevance is rejected'
);

select results_eq(
  $$select admin_hidden, relevance, control_version from dondepido.set_business_controls(
      '40000000-0000-0000-0000-000000000001', 1, true, 80, 'Nota interna de prueba'
    )$$,
  $$values (true, 80, 2::bigint)$$,
  'An administrator can hide a business and change relevance in one versioned operation'
);

select results_eq(
  $$select admin_hidden, relevance, control_version from dondepido.set_business_controls(
      '40000000-0000-0000-0000-000000000001', 1, true, 80, 'Nota interna de prueba'
    )$$,
  $$values (true, 80, 2::bigint)$$,
  'Replaying the same requested state preserves the control version'
);

select throws_ok(
  $$select * from dondepido.set_business_controls('40000000-0000-0000-0000-000000000001', 1, false, null, null)$$,
  '40001', null,
  'A stale operation that changes the requested state conflicts'
);

set local role dondepido_catalog_reader;

select is_empty(
  $$select id from dondepido.businesses where id = '40000000-0000-0000-0000-000000000001'$$,
  'A previously published business stops resolving by ID in the catalog when hidden'
);

set local role dondepido_backend;

select results_eq(
  $$select admin_hidden, relevance, control_version from dondepido.set_business_controls(
      '40000000-0000-0000-0000-000000000001', 2, false, null, null
    )$$,
  $$values (false, 80, 3::bigint)$$,
  'Restoring visibility retains relevance and advances the control version'
);

set local role dondepido_catalog_reader;

select results_eq(
  $$select name from dondepido.businesses
    where id between '40000000-0000-0000-0000-000000000001' and '40000000-0000-0000-0000-000000000004'
    order by name$$,
  array['Local visible'],
  'The restored published business is visible again'
);

reset role;

select results_eq(
  $$select actor_id::text, old_values->>'admin_hidden', new_values->>'admin_hidden', note
    from dondepido.audit_events
    where entity_id = '40000000-0000-0000-0000-000000000001'
      and action = 'business_controls_updated'
    order by (new_values->>'admin_hidden')::boolean desc$$,
  $$values
    ('10000000-0000-0000-0000-000000000003', 'false', 'true', 'Nota interna de prueba'),
    ('10000000-0000-0000-0000-000000000003', 'true', 'false', null)$$,
  'Only the two actual changes create audit records with actor, previous value and new value'
);

update dondepido.admin_roles set revoked_at = now()
where user_id = '10000000-0000-0000-0000-000000000003';

set local role dondepido_backend;

select throws_ok(
  $$select * from dondepido.set_business_controls('40000000-0000-0000-0000-000000000001', 3, true, null, null)$$,
  '42501', null,
  'Revoking an administrator blocks the next operation with the same reinforced session'
);

reset role;
select * from finish();
rollback;
