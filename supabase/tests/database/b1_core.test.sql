begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(10);

insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'client-one@example.invalid'),
  ('10000000-0000-0000-0000-000000000002', 'client-two@example.invalid');

insert into dondepido.profiles (user_id, first_name, last_name)
values
  ('10000000-0000-0000-0000-000000000001', 'Cliente', 'Uno'),
  ('10000000-0000-0000-0000-000000000002', 'Cliente', 'Dos');

insert into dondepido.verified_phones (user_id, phone_e164, verified_at)
values ('10000000-0000-0000-0000-000000000001', '+12025550197', now());

select throws_ok(
  $$insert into dondepido.verified_phones (user_id, phone_e164, verified_at)
    values ('10000000-0000-0000-0000-000000000002', '+12025550197', now())$$,
  '23505', null,
  'A verified number cannot belong to two profiles'
);

select throws_ok(
  $$insert into dondepido.verified_phones (user_id, phone_e164, verified_at)
    values ('10000000-0000-0000-0000-000000000002', '+1 202 555 0102', now())$$,
  '23514', null,
  'The persisted number must be in canonical E.164 form'
);

insert into dondepido.cities (id, slug, name, time_zone)
values
  ('20000000-0000-0000-0000-000000000001', 'ciudad-uno', 'Ciudad Uno', 'America/Argentina/Buenos_Aires'),
  ('20000000-0000-0000-0000-000000000002', 'ciudad-dos', 'Ciudad Dos', 'America/Argentina/Buenos_Aires');

insert into dondepido.business_applications (email, sector_code, observation)
values ('pending@example.invalid', 'kioscos', 'Solicitud ficticia');

select throws_ok(
  $$insert into dondepido.business_applications (email, sector_code, observation)
    values ('pending@example.invalid', 'gastronomia', 'Segunda solicitud ficticia')$$,
  '23505', null,
  'A normalized email can have only one open commercial application'
);

select throws_ok(
  $$insert into dondepido.business_applications (email, sector_code, observation, status)
    values ('invalid-approval@example.invalid', 'kioscos', 'Sin decisión', 'approved')$$,
  '23514', null,
  'Approval requires decision metadata, city and a valid expiry'
);

select throws_ok(
  $$insert into dondepido.business_applications (
      email, sector_code, observation, status, city_id, decided_by,
      decided_at, decision_reason, expires_at, consumed_by, consumed_at
    ) values (
      'expired-approval@example.invalid', 'kioscos', 'Consumo vencido', 'consumed',
      '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
      now() - interval '2 hours', 'Aprobada', now() - interval '1 hour',
      '10000000-0000-0000-0000-000000000001', now()
    )$$,
  '23514', null,
  'An approval cannot be consumed after its expiry'
);

insert into dondepido.business_applications (
  id, email, sector_code, observation, status, city_id, decided_by,
  decided_at, decision_reason, expires_at, consumed_by, consumed_at
) values (
  '30000000-0000-0000-0000-000000000001', 'client-one@example.invalid', 'kioscos', 'Alta ficticia',
  'consumed', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
  now() - interval '1 hour', 'Aprobada', now() + interval '1 hour',
  '10000000-0000-0000-0000-000000000001', now()
);

select throws_ok(
  $$insert into dondepido.businesses (application_id, city_id, sector_code, name, address, logo_object_key)
    values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002',
      'kioscos', 'Local ficticio', 'Dirección de prueba', 'fixture.webp')$$,
  '23503', null,
  'A business must use the city and sector of its application'
);

select throws_ok(
  $$insert into dondepido.businesses (
      application_id, city_id, sector_code, name, address, logo_object_key, publication_status
    ) values (
      '30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
      'kioscos', 'Local ficticio', 'Dirección de prueba', 'fixture.webp', 'published'
    )$$,
  '23514', null,
  'Publication requires a fulfillment method and verified contact'
);

insert into dondepido.businesses (id, application_id, city_id, sector_code, name, address, logo_object_key)
values ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001', 'kioscos', 'Local ficticio', 'Dirección de prueba', 'fixture.webp');

select results_eq(
  $$select publication_status, accepting_orders, relevance::integer
    from dondepido.businesses where id = '40000000-0000-0000-0000-000000000001'$$,
  $$values ('draft', false, 50)$$,
  'A newly registered business defaults to a draft that does not accept orders'
);

select throws_ok(
  $$insert into dondepido.businesses (application_id, city_id, sector_code, name, address, logo_object_key)
    values ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
      'kioscos', 'Duplicado ficticio', 'Dirección de prueba', 'fixture.webp')$$,
  '23505', null,
  'One consumed application cannot create a second business'
);

select throws_ok(
  $$insert into dondepido.business_weekly_hours (business_id, weekday, opening_minutes)
    values ('40000000-0000-0000-0000-000000000001', 1, '{[1380,1500)}')$$,
  '23514', null,
  'A weekly hours interval may not extend beyond its local day'
);

select * from finish();
rollback;
