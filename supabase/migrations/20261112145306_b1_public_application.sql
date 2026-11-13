create role dondepido_application_intake_owner nologin noinherit nobypassrls;
grant dondepido_application_intake_owner to current_user;
grant usage, create on schema dondepido to dondepido_application_intake_owner;

-- Only timestamps are kept for the rolling limit. Old entries are removed on intake.
create table dondepido.application_intake_events (
    accepted_at timestamptz not null
);

alter table dondepido.application_intake_events enable row level security;
revoke all on dondepido.application_intake_events
    from public, anon, authenticated, service_role, dondepido_backend;

grant select (code) on dondepido.business_sectors to dondepido_application_intake_owner;
grant select (email, status, expires_at), insert (email, sector_code, observation), update (status)
    on dondepido.business_applications to dondepido_application_intake_owner;
grant select, insert, delete on dondepido.application_intake_events to dondepido_application_intake_owner;

create policy public_application_sector_read on dondepido.business_sectors for select
    to dondepido_application_intake_owner using (true);
create policy public_application_email_read on dondepido.business_applications for select
    to dondepido_application_intake_owner using (email = current_setting('dondepido.request_email', true));
create policy public_application_insert on dondepido.business_applications for insert
    to dondepido_application_intake_owner with check (
        status = 'pending' and email = current_setting('dondepido.request_email', true)
    );
create policy public_application_expire on dondepido.business_applications for update
    to dondepido_application_intake_owner using (
        email = current_setting('dondepido.request_email', true)
        and status = 'approved' and expires_at <= clock_timestamp()
    ) with check (status = 'expired' and email = current_setting('dondepido.request_email', true));

create policy public_application_rate_read on dondepido.application_intake_events for select
    to dondepido_application_intake_owner using (true);
create policy public_application_rate_record on dondepido.application_intake_events for insert
    to dondepido_application_intake_owner with check (true);
create policy public_application_rate_cleanup on dondepido.application_intake_events for delete
    to dondepido_application_intake_owner using (accepted_at <= clock_timestamp() - interval '1 hour');

create function dondepido.request_application(email text, sector text, observation text)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    normalized_email text := lower(btrim(email));
    previous_email text := current_setting('dondepido.request_email', true);
    requested_at timestamptz;
begin
    if normalized_email is null or char_length(normalized_email) > 254
        or normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+$'
        or observation is null or observation !~ '[^[:space:]]' or char_length(btrim(observation)) > 2000
        or not exists (select 1 from dondepido.business_sectors s where s.code = sector) then
        raise invalid_parameter_value using message = 'Invalid business application';
    end if;

    -- Check capacity before inspecting email state so throttling does not reveal whether it exists.
    perform pg_advisory_xact_lock(1807, 1);
    requested_at := clock_timestamp();
    delete from dondepido.application_intake_events e where e.accepted_at <= requested_at - interval '1 hour';
    if (select count(*) from dondepido.application_intake_events) >= 30 then
        raise program_limit_exceeded using message = 'Public application intake rate limit reached';
    end if;

    perform set_config('dondepido.request_email', normalized_email, true);
    -- Share the email lock with the authenticated submission operation.
    perform pg_advisory_xact_lock(hashtextextended(normalized_email, 1807));
    update dondepido.business_applications a set status = 'expired'
    where a.email = normalized_email and a.status = 'approved' and a.expires_at <= clock_timestamp();

    if not exists (
        select 1 from dondepido.business_applications a
        where a.email = normalized_email and a.status in ('pending', 'approved')
    ) then
        insert into dondepido.business_applications (email, sector_code, observation)
        values (normalized_email, sector, btrim(observation));
        insert into dondepido.application_intake_events (accepted_at) values (clock_timestamp());
    end if;

    perform set_config('dondepido.request_email', coalesce(previous_email, ''), true);
end;
$$;

revoke execute on function dondepido.request_application(text, text, text)
    from public, anon, authenticated, service_role;
grant execute on function dondepido.request_application(text, text, text) to dondepido_backend;

alter function dondepido.request_application(text, text, text) owner to dondepido_application_intake_owner;
revoke create on schema dondepido from dondepido_application_intake_owner;
revoke dondepido_application_intake_owner from current_user;
