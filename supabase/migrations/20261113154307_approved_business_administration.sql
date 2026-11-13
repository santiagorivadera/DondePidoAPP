alter table dondepido.business_applications
    add column admin_suspended boolean not null default false;

alter table dondepido.businesses drop constraint businesses_application_id_city_id_sector_code_fkey;
alter table dondepido.businesses add constraint businesses_application_id_city_id_sector_code_fkey
    foreign key (application_id, city_id, sector_code)
    references dondepido.business_applications (id, city_id, sector_code) on update cascade;

grant update (email, sector_code, observation, city_id, admin_suspended)
    on dondepido.business_applications to dondepido_backend;
grant update (name, address) on dondepido.businesses to dondepido_backend;
grant select (business_id) on dondepido.catalog_offers, dondepido.suborders to dondepido_backend;

create policy admin_approved_application_update on dondepido.business_applications for update
    to dondepido_backend using ((select dondepido.actor_is_admin()) and status in ('approved', 'consumed'))
    with check ((select dondepido.actor_is_admin()) and status in ('approved', 'consumed'));
create policy admin_approved_offer_exists on dondepido.catalog_offers for select
    to dondepido_backend using ((select dondepido.actor_is_admin()));
create policy admin_approved_order_exists on dondepido.suborders for select
    to dondepido_backend using ((select dondepido.actor_is_admin()));
create policy admin_approved_application_audit on dondepido.audit_events for insert
    to dondepido_backend with check (
        (select dondepido.actor_is_admin()) and actor_id = (select dondepido.actor_id())
        and entity_type = 'business_application' and action in ('application_corrected', 'application_suspension_changed')
    );

create function dondepido.edit_approved_application(
    application_id_arg uuid, email_arg text, sector_arg text, observation_arg text,
    city_arg uuid, name_arg text, address_arg text
) returns void
language plpgsql security invoker
set search_path = pg_catalog
as $$
declare
    previous dondepido.business_applications%rowtype;
    shop dondepido.businesses%rowtype;
begin
    if not dondepido.actor_is_admin() then
        raise insufficient_privilege;
    end if;
    select a.* into previous from dondepido.business_applications a
    where a.id = application_id_arg for update;
    if not found then raise no_data_found; end if;
    if previous.status not in ('approved', 'consumed')
        or (previous.status = 'approved' and previous.expires_at <= clock_timestamp()) then
        raise object_not_in_prerequisite_state;
    end if;
    if not exists (select 1 from dondepido.cities c where c.id = city_arg and c.enabled)
        or not exists (select 1 from dondepido.business_sectors s where s.code = sector_arg) then
        raise invalid_parameter_value;
    end if;

    if previous.status = 'consumed' then
        select b.* into strict shop from dondepido.businesses b where b.application_id = previous.id for update;
        if email_arg is distinct from previous.email then raise invalid_parameter_value; end if;
        if (sector_arg <> previous.sector_code and exists (
                select 1 from dondepido.catalog_offers o where o.business_id = shop.id
            )) or (city_arg <> previous.city_id and exists (
                select 1 from dondepido.suborders o where o.business_id = shop.id
            )) then
            raise object_not_in_prerequisite_state using message = 'business_classification_in_use';
        end if;
        update dondepido.businesses b
        set name = btrim(name_arg), address = btrim(address_arg), updated_at = now()
        where b.id = shop.id;
    end if;

    update dondepido.business_applications a
    set email = email_arg, sector_code = sector_arg, observation = observation_arg, city_id = city_arg
    where a.id = previous.id;

    insert into dondepido.audit_events (actor_id, action, entity_type, entity_id, old_values, new_values)
    values (dondepido.actor_id(), 'application_corrected', 'business_application', previous.id,
        jsonb_build_object('email', previous.email, 'sector_code', previous.sector_code,
            'city_id', previous.city_id, 'observation', previous.observation, 'name', shop.name, 'address', shop.address),
        jsonb_build_object('email', email_arg, 'sector_code', sector_arg,
            'city_id', city_arg, 'observation', observation_arg, 'name', name_arg, 'address', address_arg));
end;
$$;

create function dondepido.set_application_suspension(application_id_arg uuid, suspended_arg boolean)
returns void
language plpgsql security invoker
set search_path = pg_catalog
as $$
declare
    previous dondepido.business_applications%rowtype;
    shop dondepido.businesses%rowtype;
begin
    if not dondepido.actor_is_admin() then raise insufficient_privilege; end if;
    if suspended_arg is null then raise invalid_parameter_value; end if;

    select a.* into previous from dondepido.business_applications a
    where a.id = application_id_arg for update;
    if not found then raise no_data_found; end if;
    if previous.status = 'consumed' then
        select b.* into strict shop from dondepido.businesses b where b.application_id = previous.id for update;
        perform dondepido.set_business_controls(shop.id, shop.control_version, suspended_arg, null,
            case when suspended_arg then 'Suspensión administrativa' else 'Reactivación administrativa' end);
        return;
    end if;
    if previous.status <> 'approved' or previous.expires_at <= clock_timestamp() then
        raise object_not_in_prerequisite_state;
    end if;
    if previous.admin_suspended = suspended_arg then return; end if;

    update dondepido.business_applications a set admin_suspended = suspended_arg where a.id = previous.id;
    insert into dondepido.audit_events (actor_id, action, entity_type, entity_id, old_values, new_values)
    values (dondepido.actor_id(), 'application_suspension_changed', 'business_application', previous.id,
        jsonb_build_object('suspended', previous.admin_suspended), jsonb_build_object('suspended', suspended_arg));
end;
$$;

revoke execute on function dondepido.edit_approved_application(uuid, text, text, text, uuid, text, text),
    dondepido.set_application_suspension(uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function dondepido.edit_approved_application(uuid, text, text, text, uuid, text, text),
    dondepido.set_application_suspension(uuid, boolean) to dondepido_backend;

grant dondepido_onboarding_owner to current_user;
create or replace function dondepido.complete_application(id uuid, name text, address text, logo text)
returns uuid
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    email_verified text := dondepido.onboarding_email();
    application dondepido.business_applications%rowtype;
    new_business_id uuid;
    completed timestamptz;
begin
    if actor is null or email_verified is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;

    select a.* into application from dondepido.business_applications a
    where a.id = complete_application.id and (a.email = email_verified or a.consumed_by = actor) for update;
    if not found then
        raise no_data_found using message = 'Application not available';
    end if;

    if application.status = 'consumed' and application.consumed_by = actor then
        select b.id into strict new_business_id from dondepido.businesses b where b.application_id = application.id;
        return new_business_id;
    end if;

    completed := clock_timestamp();
    if application.status <> 'approved' or application.email <> email_verified
        or application.expires_at <= completed or application.admin_suspended then
        raise object_not_in_prerequisite_state using message = 'Application has no active approval';
    end if;
    if not exists (select 1 from dondepido.cities c where c.id = application.city_id)
        or not exists (select 1 from dondepido.verified_phones p where p.user_id = actor) then
        raise object_not_in_prerequisite_state using message = 'Enabled city and verified phone are required';
    end if;
    if name is null or name !~ '[^[:space:]]' or char_length(btrim(name)) > 160
        or address is null or address !~ '[^[:space:]]' or char_length(btrim(address)) > 400
        or logo is null or logo !~ ('^' || actor::text || '/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$') then
        raise invalid_parameter_value using message = 'Invalid business name, address, or logo path';
    end if;

    new_business_id := gen_random_uuid();
    insert into dondepido.businesses (id, application_id, city_id, sector_code, name, address, logo_object_key)
    values (new_business_id, application.id, application.city_id, application.sector_code,
        btrim(name), btrim(address), logo);

    insert into dondepido.business_memberships (business_id, user_id, role)
    values (new_business_id, actor, 'owner');

    update dondepido.business_applications a
    set status = 'consumed', consumed_by = actor, consumed_at = completed where a.id = application.id;
    return new_business_id;
end;
$$;

revoke dondepido_onboarding_owner from current_user;
