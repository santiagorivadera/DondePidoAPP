-- Runtime identities are deliberately provisioned separately in each environment.
create role dondepido_backend nologin noinherit nobypassrls;
create role dondepido_catalog_reader nologin noinherit nobypassrls;

grant usage on schema dondepido to dondepido_backend, dondepido_catalog_reader;

-- Only the trusted server may set this context, transaction-locally, after Auth verification.
create function dondepido.actor_id()
returns uuid
language sql stable
set search_path = pg_catalog
as $$
  select nullif(current_setting('dondepido.actor_id', true), '')::uuid
$$;

create function dondepido.actor_has_aal2()
returns boolean
language sql stable
set search_path = pg_catalog
as $$
  select coalesce(current_setting('dondepido.actor_aal', true) = 'aal2', false)
$$;

create function dondepido.actor_is_admin()
returns boolean
language sql stable
set search_path = pg_catalog
as $$
  select dondepido.actor_has_aal2() and exists (
    select 1 from dondepido.admin_roles
    where user_id = dondepido.actor_id() and revoked_at is null
  )
$$;

revoke execute on function dondepido.actor_id(), dondepido.actor_has_aal2(),
  dondepido.actor_is_admin() from public, anon, authenticated, service_role;
grant execute on function dondepido.actor_id(), dondepido.actor_has_aal2(),
  dondepido.actor_is_admin() to dondepido_backend;

grant select on dondepido.cities, dondepido.business_sectors
  to dondepido_backend, dondepido_catalog_reader;
grant select on dondepido.profiles, dondepido.admin_roles, dondepido.verified_phones,
  dondepido.business_applications, dondepido.business_memberships, dondepido.businesses
  to dondepido_backend;
grant update (admin_hidden, relevance, control_version, updated_at) on dondepido.businesses
  to dondepido_backend;
grant insert (actor_id, action, entity_type, entity_id, old_values, new_values, note)
  on dondepido.audit_events to dondepido_backend;

grant select (id, city_id, sector_code, name, address, logo_object_key, accepting_orders,
  relevance, offers_pickup, offers_delivery) on dondepido.businesses to dondepido_catalog_reader;

create policy enabled_city_read on dondepido.cities for select
  to dondepido_backend, dondepido_catalog_reader using (enabled);
create policy sector_read on dondepido.business_sectors for select
  to dondepido_backend, dondepido_catalog_reader using (true);
create policy own_profile_read on dondepido.profiles for select
  to dondepido_backend using (user_id = (select dondepido.actor_id()));
create policy own_admin_role_read on dondepido.admin_roles for select
  to dondepido_backend using (user_id = (select dondepido.actor_id()));
create policy own_verified_phone_read on dondepido.verified_phones for select
  to dondepido_backend using (user_id = (select dondepido.actor_id()));
create policy admin_applications_read on dondepido.business_applications for select
  to dondepido_backend using ((select dondepido.actor_is_admin()));
create policy own_membership_read on dondepido.business_memberships for select
  to dondepido_backend using (
    user_id = (select dondepido.actor_id()) and (select dondepido.actor_has_aal2())
  );

create policy public_business_read on dondepido.businesses for select
  to dondepido_catalog_reader using (
    publication_status = 'published' and not admin_hidden
    and exists (select 1 from dondepido.cities where id = businesses.city_id and enabled)
  );
create policy scoped_business_read on dondepido.businesses for select
  to dondepido_backend using (
    (select dondepido.actor_is_admin()) or exists (
      select 1 from dondepido.business_memberships
      where business_id = businesses.id and user_id = (select dondepido.actor_id())
        and revoked_at is null and (select dondepido.actor_has_aal2())
    )
  );
create policy admin_business_controls_update on dondepido.businesses for update
  to dondepido_backend using ((select dondepido.actor_is_admin()))
  with check ((select dondepido.actor_is_admin()));
create policy admin_business_control_audit on dondepido.audit_events for insert
  to dondepido_backend with check (
    (select dondepido.actor_is_admin()) and actor_id = (select dondepido.actor_id())
    and action = 'business_controls_updated' and entity_type = 'business'
  );

create function dondepido.set_business_controls(
  business_id_arg uuid,
  expected_version bigint,
  hidden_arg boolean,
  relevance_arg integer,
  note_arg text
)
returns table (id uuid, admin_hidden boolean, relevance integer, control_version bigint)
language plpgsql security invoker
set search_path = pg_catalog
as $$
declare
  previous dondepido.businesses%rowtype;
  changed dondepido.businesses%rowtype;
  next_hidden boolean;
  next_relevance integer;
begin
  if not dondepido.actor_is_admin() then
    raise insufficient_privilege using message = 'Administrative access with MFA is required';
  end if;

  if expected_version is null or expected_version < 1 or relevance_arg not between 1 and 100 then
    raise invalid_parameter_value using message = 'Invalid control version or relevance';
  end if;

  select b.* into previous from dondepido.businesses as b
    where b.id = business_id_arg for update;
  if not found then
    raise no_data_found using message = 'Business not found';
  end if;

  next_hidden := coalesce(hidden_arg, previous.admin_hidden);
  next_relevance := coalesce(relevance_arg, previous.relevance);
  if next_hidden = previous.admin_hidden and next_relevance = previous.relevance then
    return query select previous.id, previous.admin_hidden, previous.relevance::integer,
      previous.control_version;
    return;
  end if;

  if previous.control_version <> expected_version then
    raise serialization_failure using message = 'Business controls have changed';
  end if;

  update dondepido.businesses as b
    set admin_hidden = next_hidden, relevance = next_relevance,
        control_version = b.control_version + 1, updated_at = now()
    where b.id = business_id_arg returning b.* into changed;

  insert into dondepido.audit_events
    (actor_id, action, entity_type, entity_id, old_values, new_values, note)
  values (
    dondepido.actor_id(), 'business_controls_updated', 'business', changed.id,
    jsonb_build_object('admin_hidden', previous.admin_hidden, 'relevance', previous.relevance),
    jsonb_build_object('admin_hidden', changed.admin_hidden, 'relevance', changed.relevance),
    nullif(btrim(note_arg), '')
  );

  return query select changed.id, changed.admin_hidden, changed.relevance::integer,
    changed.control_version;
end;
$$;

revoke execute on function dondepido.set_business_controls(uuid, bigint, boolean, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function dondepido.set_business_controls(uuid, bigint, boolean, integer, text)
  to dondepido_backend;
