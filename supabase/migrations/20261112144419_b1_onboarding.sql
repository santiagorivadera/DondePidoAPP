-- Only the trusted server role may invoke these operations. Their owner has no login and obeys RLS.
create role dondepido_onboarding_owner nologin noinherit nobypassrls;
grant dondepido_onboarding_owner to current_user;
grant usage, create on schema dondepido to dondepido_onboarding_owner;

create table dondepido.phone_challenges (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references dondepido.profiles (user_id) on delete cascade,
    phone_e164 text not null check (phone_e164 ~ '^[+][1-9][0-9]{1,14}$'),
    code_digest text not null check (code_digest ~ '^[0-9a-f]{64}$'),
    issued_at timestamptz not null,
    expires_at timestamptz not null check (expires_at > issued_at),
    failed_attempts integer not null default 0 check (failed_attempts between 0 and 5),
    closed_at timestamptz check (closed_at >= issued_at)
);

create index phone_challenges_user_recent_idx
    on dondepido.phone_challenges (user_id, issued_at desc);
create unique index phone_challenges_user_open_idx
    on dondepido.phone_challenges (user_id) where closed_at is null;

alter table dondepido.phone_challenges enable row level security;
revoke all on dondepido.phone_challenges from public, anon, authenticated, service_role, dondepido_backend;

grant execute on function dondepido.actor_id(), dondepido.actor_has_aal2(),
    dondepido.actor_is_admin() to dondepido_onboarding_owner;
grant select on dondepido.cities, dondepido.business_sectors, dondepido.admin_roles,
    dondepido.profiles, dondepido.verified_phones, dondepido.phone_challenges,
    dondepido.business_applications, dondepido.businesses, dondepido.business_memberships
    to dondepido_onboarding_owner;
grant insert on dondepido.profiles, dondepido.verified_phones, dondepido.phone_challenges,
    dondepido.business_applications, dondepido.businesses, dondepido.business_memberships
    to dondepido_onboarding_owner;
grant select, insert, delete on dondepido.business_weekly_hours to dondepido_onboarding_owner;
grant update (first_name, last_name, updated_at) on dondepido.profiles to dondepido_onboarding_owner;
grant update (phone_e164, verified_at) on dondepido.verified_phones to dondepido_onboarding_owner;
grant update (closed_at, failed_attempts) on dondepido.phone_challenges to dondepido_onboarding_owner;
grant update (status, city_id, decided_by, decided_at, decision_reason, expires_at, consumed_by, consumed_at)
    on dondepido.business_applications to dondepido_onboarding_owner;
grant update (publication_status, offers_pickup, offers_delivery, contact_phone_e164,
    contact_verified_at, updated_at) on dondepido.businesses to dondepido_onboarding_owner;
grant insert (actor_id, action, entity_type, entity_id, old_values, new_values, note)
    on dondepido.audit_events to dondepido_onboarding_owner;

create function dondepido.onboarding_email()
returns text
language sql stable
set search_path = pg_catalog
as $$
    select nullif(lower(btrim(current_setting('dondepido.actor_email', true))), '')
$$;

revoke all on function dondepido.onboarding_email() from public, anon, authenticated, service_role;
grant execute on function dondepido.onboarding_email() to dondepido_onboarding_owner;

create policy onboarding_city_read on dondepido.cities for select
    to dondepido_onboarding_owner using (enabled);
create policy onboarding_sector_read on dondepido.business_sectors for select
    to dondepido_onboarding_owner using (true);
create policy onboarding_admin_read on dondepido.admin_roles for select
    to dondepido_onboarding_owner using (user_id = (select dondepido.actor_id()));
create policy onboarding_profile on dondepido.profiles for all
    to dondepido_onboarding_owner using (user_id = (select dondepido.actor_id()))
    with check (user_id = (select dondepido.actor_id()));
create policy onboarding_phone on dondepido.verified_phones for all
    to dondepido_onboarding_owner using (user_id = (select dondepido.actor_id()))
    with check (user_id = (select dondepido.actor_id()));
create policy onboarding_challenge on dondepido.phone_challenges for all
    to dondepido_onboarding_owner using (user_id = (select dondepido.actor_id()))
    with check (user_id = (select dondepido.actor_id()));
create policy onboarding_application_read on dondepido.business_applications for select
    to dondepido_onboarding_owner using (
        email = (select dondepido.onboarding_email())
        or consumed_by = (select dondepido.actor_id())
        or (select dondepido.actor_is_admin())
    );
create policy onboarding_application_insert on dondepido.business_applications for insert
    to dondepido_onboarding_owner with check (
        (select dondepido.actor_id()) is not null and status = 'pending'
        and email = (select dondepido.onboarding_email())
    );
create policy onboarding_application_update on dondepido.business_applications for update
    to dondepido_onboarding_owner using (
        email = (select dondepido.onboarding_email()) or (select dondepido.actor_is_admin())
        or (status = 'consumed' and consumed_by = (select dondepido.actor_id()))
    ) with check (
        email = (select dondepido.onboarding_email()) or (select dondepido.actor_is_admin())
    );
create policy onboarding_own_membership_read on dondepido.business_memberships for select
    to dondepido_onboarding_owner using (user_id = (select dondepido.actor_id()));
create policy onboarding_own_membership_insert on dondepido.business_memberships for insert
    to dondepido_onboarding_owner with check (
        user_id = (select dondepido.actor_id()) and role = 'owner' and revoked_at is null
    );
create policy onboarding_business_read on dondepido.businesses for select
    to dondepido_onboarding_owner using (
        exists (
            select 1 from dondepido.business_memberships m where m.business_id = businesses.id
                and m.user_id = (select dondepido.actor_id()) and m.role = 'owner' and m.revoked_at is null
        ) or exists (
            select 1 from dondepido.business_applications a where a.id = businesses.application_id
                and a.consumed_by = (select dondepido.actor_id())
        )
    );
create policy onboarding_business_insert on dondepido.businesses for insert
    to dondepido_onboarding_owner with check (
        publication_status = 'draft' and not admin_hidden and not accepting_orders
        and exists (
            select 1 from dondepido.business_applications a where a.id = businesses.application_id
                and a.email = (select dondepido.onboarding_email()) and a.status = 'approved'
        )
    );
create policy onboarding_publish on dondepido.businesses for update
    to dondepido_onboarding_owner using (
        (select dondepido.actor_has_aal2()) and not admin_hidden
        and exists (
            select 1 from dondepido.business_memberships m where m.business_id = businesses.id
                and m.user_id = (select dondepido.actor_id()) and m.role = 'owner' and m.revoked_at is null
        )
    ) with check (publication_status = 'published' and not admin_hidden);
create policy onboarding_weekly_hours on dondepido.business_weekly_hours for all
    to dondepido_onboarding_owner using (
        (select dondepido.actor_has_aal2()) and exists (
            select 1 from dondepido.business_memberships m
            where m.business_id = business_weekly_hours.business_id
                and m.user_id = (select dondepido.actor_id()) and m.role = 'owner' and m.revoked_at is null
        )
    );
create policy onboarding_application_audit on dondepido.audit_events for insert
    to dondepido_onboarding_owner with check (
        (select dondepido.actor_is_admin()) and actor_id = (select dondepido.actor_id())
        and action = 'business_application_decided' and entity_type = 'business_application'
    );

create function dondepido.save_profile(first_name text, last_name text)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
begin
    if actor is null or dondepido.onboarding_email() is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;
    if first_name is null or first_name !~ '[^[:space:]]' or char_length(btrim(first_name)) > 100
        or last_name is null or last_name !~ '[^[:space:]]' or char_length(btrim(last_name)) > 100 then
        raise invalid_parameter_value using message = 'Invalid profile names';
    end if;

    insert into dondepido.profiles (user_id, first_name, last_name)
    values (actor, btrim(first_name), btrim(last_name))
    on conflict (user_id) do update set first_name = excluded.first_name,
        last_name = excluded.last_name, updated_at = clock_timestamp();
end;
$$;

create function dondepido.issue_phone_challenge(phone text, digest text)
returns uuid
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    issued timestamptz;
    latest timestamptz;
    recent_count bigint;
    challenge_id uuid;
begin
    if actor is null or dondepido.onboarding_email() is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;
    if phone is null or phone !~ '^[+][1-9][0-9]{1,14}$'
        or digest is null or digest !~ '^[0-9a-f]{64}$' then
        raise invalid_parameter_value using message = 'Invalid phone challenge';
    end if;

    -- Lock the profile before inspecting or changing challenge state for this account.
    perform 1 from dondepido.profiles p where p.user_id = actor for update;
    if not found then
        raise object_not_in_prerequisite_state using message = 'Complete the profile first';
    end if;
    issued := clock_timestamp();

    select max(c.issued_at), count(*) into latest, recent_count
    from dondepido.phone_challenges c
    where c.user_id = actor and c.issued_at > issued - interval '1 hour';

    if latest > issued - interval '60 seconds' or recent_count >= 5 then
        raise program_limit_exceeded using message = 'Phone verification rate limit reached';
    end if;

    update dondepido.phone_challenges c set closed_at = issued
    where c.user_id = actor and c.closed_at is null;

    insert into dondepido.phone_challenges (user_id, phone_e164, code_digest, issued_at, expires_at)
    values (actor, phone, digest, issued, issued + interval '10 minutes')
    returning id into challenge_id;
    return challenge_id;
end;
$$;

create function dondepido.verify_phone_challenge(challenge uuid, digest text)
returns text
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    pending dondepido.phone_challenges%rowtype;
    checked_at timestamptz;
begin
    if actor is null or dondepido.onboarding_email() is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;

    perform 1 from dondepido.profiles p where p.user_id = actor for update;
    if not found then
        return 'invalid';
    end if;

    select c.* into pending from dondepido.phone_challenges c
    where c.id = challenge and c.user_id = actor for update;
    if not found or pending.failed_attempts >= 5 then
        return 'invalid';
    end if;

    checked_at := clock_timestamp();
    if pending.closed_at is not null or pending.expires_at <= checked_at then
        return 'expired';
    end if;

    if digest is distinct from pending.code_digest then
        update dondepido.phone_challenges c
        set failed_attempts = pending.failed_attempts + 1,
            closed_at = case when pending.failed_attempts = 4 then checked_at end
        where c.id = challenge;
        return 'invalid';
    end if;

    begin
        insert into dondepido.verified_phones (user_id, phone_e164, verified_at)
        values (actor, pending.phone_e164, checked_at)
        on conflict (user_id) do update set phone_e164 = excluded.phone_e164,
            verified_at = excluded.verified_at;
    exception when unique_violation then
        update dondepido.phone_challenges c set closed_at = checked_at where c.id = challenge;
        return 'conflict';
    end;

    update dondepido.phone_challenges c set closed_at = checked_at where c.id = challenge;
    return 'verified';
end;
$$;

create function dondepido.submit_application(sector text, observation text)
returns uuid
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    email_verified text := dondepido.onboarding_email();
    application_id uuid;
begin
    if dondepido.actor_id() is null or email_verified is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;
    if observation is null or observation !~ '[^[:space:]]' or char_length(btrim(observation)) > 2000
        or not exists (select 1 from dondepido.business_sectors s where s.code = sector) then
        raise invalid_parameter_value using message = 'Invalid business application';
    end if;

    -- Serialize submissions for the same normalized email, including the first submission.
    perform pg_advisory_xact_lock(hashtextextended(email_verified, 1807));

    update dondepido.business_applications a set status = 'expired'
    where a.email = email_verified and a.status = 'approved' and a.expires_at <= clock_timestamp();

    select a.id into application_id from dondepido.business_applications a
    where a.email = email_verified and a.status in ('pending', 'approved');
    if found then
        return application_id;
    end if;

    insert into dondepido.business_applications (email, sector_code, observation)
    values (email_verified, sector, btrim(observation)) returning id into application_id;
    return application_id;
end;
$$;

create function dondepido.my_applications()
returns table (id uuid, sector_code text, status text, expires_at timestamptz, created_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    email_verified text := dondepido.onboarding_email();
begin
    if actor is null or email_verified is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;

    return query select a.id, a.sector_code,
        case when a.status = 'approved' and a.expires_at <= statement_timestamp()
            then 'expired' else a.status end,
        a.expires_at, a.created_at
    from dondepido.business_applications a
    where a.email = email_verified or a.consumed_by = actor
    order by a.created_at desc, a.id;
end;
$$;

create function dondepido.decide_application(id uuid, decision text, city uuid, reason text)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    previous dondepido.business_applications%rowtype;
    decided timestamptz;
begin
    if not dondepido.actor_is_admin() or dondepido.onboarding_email() is null then
        raise insufficient_privilege using message = 'Administrative access with MFA is required';
    end if;
    if decision is null or decision not in ('approved', 'rejected', 'revoked')
        or reason is null or reason !~ '[^[:space:]]' or char_length(btrim(reason)) > 1000
        or ((decision = 'approved') <> (city is not null)) then
        raise invalid_parameter_value using message = 'Invalid application decision';
    end if;
    if decision = 'approved' and not exists (select 1 from dondepido.cities c where c.id = city) then
        raise invalid_parameter_value using message = 'Select an enabled city';
    end if;

    select a.* into previous from dondepido.business_applications a
    where a.id = decide_application.id for update;
    if not found then
        raise no_data_found using message = 'Application not found';
    end if;

    decided := clock_timestamp();
    if decision = 'revoked' then
        if previous.status <> 'approved' or previous.expires_at <= decided then
            raise object_not_in_prerequisite_state using message = 'Only an active approval can be revoked';
        end if;
        update dondepido.business_applications a set status = 'revoked' where a.id = previous.id;
    else
        if previous.status <> 'pending' then
            raise object_not_in_prerequisite_state using message = 'Application is not pending';
        end if;
        update dondepido.business_applications a set status = decision, city_id = city,
            decided_by = actor, decided_at = decided, decision_reason = btrim(reason),
            expires_at = case when decision = 'approved' then decided + interval '7 days' end
        where a.id = previous.id;
    end if;

    insert into dondepido.audit_events (actor_id, action, entity_type, entity_id, old_values, new_values, note)
    values (actor, 'business_application_decided', 'business_application', previous.id,
        jsonb_build_object('status', previous.status), jsonb_build_object('status', decision), btrim(reason));
end;
$$;

create function dondepido.complete_application(id uuid, name text, address text, logo text)
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
        or application.expires_at <= completed then
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

create function dondepido.publish_business(id uuid, pickup boolean, delivery boolean)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    contact dondepido.verified_phones%rowtype;
begin
    if actor is null or dondepido.onboarding_email() is null or not dondepido.actor_has_aal2()
        or not exists (
            select 1 from dondepido.business_memberships m where m.business_id = publish_business.id
                and m.user_id = actor and m.role = 'owner' and m.revoked_at is null
        ) then
        raise insufficient_privilege using message = 'Owner access with MFA is required';
    end if;
    if pickup is null or delivery is null or not (pickup or delivery) then
        raise invalid_parameter_value using message = 'Select at least one fulfillment method';
    end if;

    -- Serialize publication with schedule replacement for the same business.
    perform pg_advisory_xact_lock(hashtextextended(publish_business.id::text, 1808));
    if not exists (
        select 1 from dondepido.business_weekly_hours h
        where h.business_id = publish_business.id and h.opening_minutes <> '{}'::int4multirange
    ) then
        raise object_not_in_prerequisite_state using message = 'At least one opening interval is required';
    end if;

    select p.* into contact from dondepido.verified_phones p where p.user_id = actor for share;
    if not found then
        raise object_not_in_prerequisite_state using message = 'Verified phone is required';
    end if;

    update dondepido.businesses b set publication_status = 'published', offers_pickup = pickup,
        offers_delivery = delivery, contact_phone_e164 = contact.phone_e164,
        contact_verified_at = contact.verified_at, updated_at = clock_timestamp()
    where b.id = publish_business.id and not b.admin_hidden
        and exists (select 1 from dondepido.cities c where c.id = b.city_id);
    if not found then
        raise object_not_in_prerequisite_state using message = 'Business is not eligible to publish';
    end if;
end;
$$;

create function dondepido.set_business_weekly_hours(business_id uuid, hours jsonb)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    day_config jsonb;
    interval_config jsonb;
    day_number smallint;
    used_days smallint[] := '{}'::smallint[];
    opening_minutes int4multirange;
    next_interval int4multirange;
    start_minute integer;
    end_minute integer;
    has_opening boolean := false;
begin
    if actor is null or dondepido.onboarding_email() is null or not dondepido.actor_has_aal2()
        or not exists (
            select 1 from dondepido.business_memberships m
            where m.business_id = set_business_weekly_hours.business_id
                and m.user_id = actor and m.role = 'owner' and m.revoked_at is null
        ) then
        raise insufficient_privilege using message = 'Owner access with MFA is required';
    end if;
    if jsonb_typeof(hours) is distinct from 'array' then
        raise invalid_parameter_value using message = 'Invalid weekly schedule';
    end if;
    if jsonb_array_length(hours) > 7 then
        raise invalid_parameter_value using message = 'A week has at most seven configured days';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(set_business_weekly_hours.business_id::text, 1808));
    delete from dondepido.business_weekly_hours h where h.business_id = set_business_weekly_hours.business_id;

    for day_config in select value from jsonb_array_elements(hours) loop
        if jsonb_typeof(day_config -> 'weekday') is distinct from 'number'
            or day_config ->> 'weekday' !~ '^[1-7]$'
            or jsonb_typeof(day_config -> 'intervals') is distinct from 'array' then
            raise invalid_parameter_value using message = 'Invalid weekday or interval list';
        end if;
        day_number := (day_config ->> 'weekday')::smallint;
        if day_number = any (used_days) then
            raise invalid_parameter_value using message = 'A weekday is configured more than once';
        end if;
        used_days := array_append(used_days, day_number);
        opening_minutes := '{}'::int4multirange;

        for interval_config in select value from jsonb_array_elements(day_config -> 'intervals') loop
            if jsonb_typeof(interval_config) is distinct from 'array' then
                raise invalid_parameter_value using message = 'An interval must contain start and end minutes';
            end if;
            if jsonb_array_length(interval_config) <> 2
                or jsonb_typeof(interval_config -> 0) is distinct from 'number'
                or jsonb_typeof(interval_config -> 1) is distinct from 'number'
                or interval_config ->> 0 !~ '^[0-9]{1,4}$'
                or interval_config ->> 1 !~ '^[0-9]{1,4}$' then
                raise invalid_parameter_value using message = 'An interval must contain two integer minutes';
            end if;
            start_minute := (interval_config ->> 0)::integer;
            end_minute := (interval_config ->> 1)::integer;
            if start_minute >= end_minute or end_minute > 1440 then
                raise invalid_parameter_value using message = 'Intervals must fit within one day';
            end if;
            next_interval := int4multirange(int4range(start_minute, end_minute, '[)'));
            if opening_minutes && next_interval then
                raise invalid_parameter_value using message = 'Opening intervals overlap';
            end if;
            opening_minutes := opening_minutes + next_interval;
            has_opening := true;
        end loop;

        insert into dondepido.business_weekly_hours (business_id, weekday, opening_minutes)
        values (set_business_weekly_hours.business_id, day_number, opening_minutes);
    end loop;

    if not has_opening and exists (
        select 1 from dondepido.businesses b where b.id = set_business_weekly_hours.business_id
            and b.publication_status = 'published'
    ) then
        raise object_not_in_prerequisite_state using message = 'A published business needs an opening interval';
    end if;
end;
$$;

-- Set execution privileges while the migration role still owns the functions.
revoke execute on function
    dondepido.save_profile(text, text), dondepido.issue_phone_challenge(text, text),
    dondepido.verify_phone_challenge(uuid, text), dondepido.submit_application(text, text),
    dondepido.my_applications(), dondepido.decide_application(uuid, text, uuid, text),
    dondepido.complete_application(uuid, text, text, text), dondepido.publish_business(uuid, boolean, boolean),
    dondepido.set_business_weekly_hours(uuid, jsonb)
from public, anon, authenticated, service_role;

grant execute on function
    dondepido.save_profile(text, text), dondepido.issue_phone_challenge(text, text),
    dondepido.verify_phone_challenge(uuid, text), dondepido.submit_application(text, text),
    dondepido.my_applications(), dondepido.decide_application(uuid, text, uuid, text),
    dondepido.complete_application(uuid, text, text, text), dondepido.publish_business(uuid, boolean, boolean),
    dondepido.set_business_weekly_hours(uuid, jsonb)
to dondepido_backend;

alter function dondepido.save_profile(text, text) owner to dondepido_onboarding_owner;
alter function dondepido.issue_phone_challenge(text, text) owner to dondepido_onboarding_owner;
alter function dondepido.verify_phone_challenge(uuid, text) owner to dondepido_onboarding_owner;
alter function dondepido.submit_application(text, text) owner to dondepido_onboarding_owner;
alter function dondepido.my_applications() owner to dondepido_onboarding_owner;
alter function dondepido.decide_application(uuid, text, uuid, text) owner to dondepido_onboarding_owner;
alter function dondepido.complete_application(uuid, text, text, text) owner to dondepido_onboarding_owner;
alter function dondepido.publish_business(uuid, boolean, boolean) owner to dondepido_onboarding_owner;
alter function dondepido.set_business_weekly_hours(uuid, jsonb) owner to dondepido_onboarding_owner;

revoke create on schema dondepido from dondepido_onboarding_owner;
revoke dondepido_onboarding_owner from current_user;
