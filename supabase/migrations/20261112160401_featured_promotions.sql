create role dondepido_featured_owner nologin noinherit nobypassrls;
grant dondepido_featured_owner, dondepido_discovery_owner to current_user;
grant usage, create on schema dondepido to dondepido_featured_owner, dondepido_discovery_owner;

create table dondepido.featured_banners (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references dondepido.businesses (id),
    title text not null check (char_length(title) between 1 and 120 and title ~ '[^[:space:]]'),
    position integer not null default 0 check (position between 0 and 9999),
    enabled boolean not null default true,
    starts_at timestamptz,
    ends_at timestamptz,
    image_key text,
    mime_type text check (mime_type in ('image/png', 'image/jpeg', 'image/webp')),
    created_by uuid not null,
    updated_by uuid not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (starts_at is null or ends_at is null or starts_at < ends_at),
    check ((image_key is null) = (mime_type is null))
);
create index featured_banners_order_idx on dondepido.featured_banners (position, id) where enabled;
create index featured_banners_image_idx on dondepido.featured_banners (image_key) where image_key is not null;
create index featured_banners_business_idx on dondepido.featured_banners (business_id);

alter table dondepido.featured_banners enable row level security;
revoke all on dondepido.featured_banners
    from public, anon, authenticated, service_role, dondepido_backend, dondepido_catalog_reader;
grant select on dondepido.featured_banners to dondepido_discovery_owner;
grant select, insert on dondepido.featured_banners to dondepido_featured_owner;
grant update (business_id, title, position, enabled, starts_at, ends_at, image_key, mime_type, updated_by, updated_at)
    on dondepido.featured_banners to dondepido_featured_owner;
grant select (user_id, revoked_at) on dondepido.admin_roles to dondepido_featured_owner;
grant select (id, name, sector_code) on dondepido.businesses to dondepido_featured_owner;
grant execute on function dondepido.actor_id(), dondepido.actor_has_aal2(), dondepido.actor_is_admin()
    to dondepido_featured_owner;

-- Storage sets request.jwt.claims from the verified token. SQL calls use the B1 actor context.
create function dondepido.featured_storage_is_admin()
returns boolean
language sql stable security definer
set search_path = pg_catalog
as $$
    select coalesce(
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal' = 'aal2'
        and exists (
            select 1 from dondepido.admin_roles a where a.revoked_at is null
                and a.user_id::text = (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
        ), false
    )
$$;

create policy featured_own_admin_role on dondepido.admin_roles for select to dondepido_featured_owner using (
    user_id = (select dondepido.actor_id())
    or user_id::text = (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
);
create policy featured_admin_business_read on dondepido.businesses for select to dondepido_featured_owner
    using ((select dondepido.actor_is_admin()));
create policy featured_admin_read on dondepido.featured_banners for select to dondepido_featured_owner
    using ((select dondepido.actor_is_admin()) or (select dondepido.featured_storage_is_admin()));
create policy featured_admin_insert on dondepido.featured_banners for insert to dondepido_featured_owner
    with check (
        (select dondepido.actor_is_admin())
        and created_by = (select dondepido.actor_id()) and updated_by = (select dondepido.actor_id())
    );
create policy featured_admin_update on dondepido.featured_banners for update to dondepido_featured_owner
    using ((select dondepido.actor_is_admin()))
    with check ((select dondepido.actor_is_admin()) and updated_by = (select dondepido.actor_id()));

-- The discovery role already filters shops to published, non-hidden and in enabled cities.
create policy featured_visible on dondepido.featured_banners for select to dondepido_discovery_owner using (
    enabled and (starts_at is null or starts_at <= statement_timestamp())
    and (ends_at is null or ends_at > statement_timestamp())
    and exists (select 1 from dondepido.businesses b where b.id = featured_banners.business_id)
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dondepido-featured', 'dondepido-featured', false, 1048576,
    array['image/png', 'image/jpeg', 'image/webp']);

grant usage on schema storage to dondepido_featured_owner;
grant select (bucket_id, name, owner_id, metadata) on storage.objects to dondepido_featured_owner;
create policy featured_object_metadata on storage.objects for select to dondepido_featured_owner using (
    bucket_id = 'dondepido-featured' and owner_id = (select dondepido.actor_id())::text
    and (select dondepido.actor_is_admin())
);

create function dondepido.featured_storage_visible(object_key text)
returns boolean
language sql stable security definer
set search_path = pg_catalog
as $$
    select exists (select 1 from dondepido.featured_banners f where f.image_key = object_key)
$$;

create function dondepido.featured_storage_unreferenced(object_key text)
returns boolean
language sql stable security definer
set search_path = pg_catalog
as $$
    select dondepido.featured_storage_is_admin()
        and not exists (select 1 from dondepido.featured_banners f where f.image_key = object_key)
$$;

create policy featured_storage_public_download on storage.objects for select to anon, authenticated using (
    bucket_id = 'dondepido-featured'
    and storage.allow_only_operation('object.get_authenticated')
    and dondepido.featured_storage_visible(name)
);
create policy featured_storage_admin_read_own on storage.objects for select to authenticated using (
    bucket_id = 'dondepido-featured' and owner_id = (select auth.uid())::text
    and (select dondepido.featured_storage_is_admin())
);
create policy featured_storage_admin_upload on storage.objects for insert to authenticated with check (
    bucket_id = 'dondepido-featured'
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$')
    and (select dondepido.featured_storage_is_admin())
);
create policy featured_storage_admin_delete on storage.objects for delete to authenticated using (
    bucket_id = 'dondepido-featured' and owner_id = (select auth.uid())::text
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$')
    and dondepido.featured_storage_unreferenced(name)
);

create function dondepido.featured_list()
returns jsonb
language sql stable security definer
set search_path = pg_catalog
as $$
    select jsonb_build_object('banners', coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id, 'title', f.title, 'business_id', f.business_id, 'business_name', b.name,
        'sector', b.sector_code, 'has_image', f.image_key is not null
    ) order by f.position, f.id), '[]'::jsonb))
    from dondepido.featured_banners f join dondepido.businesses b on b.id = f.business_id
$$;

create function dondepido.featured_image(banner_id uuid)
returns jsonb
language sql stable security definer
set search_path = pg_catalog
as $$
    select jsonb_build_object('object_key', f.image_key, 'mime_type', f.mime_type)
    from dondepido.featured_banners f where f.id = banner_id and f.image_key is not null
$$;

create function dondepido.manage_featured(input jsonb)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    action text := input ->> 'action';
    banner_id uuid;
    current_banner dondepido.featured_banners%rowtype;
    selected_business uuid;
    selected_title text;
    selected_position integer;
    selected_enabled boolean;
    selected_start timestamptz;
    selected_end timestamptz;
    selected_key text;
    selected_mime text;
    expected_mime text;
begin
    if not dondepido.actor_is_admin() then
        raise insufficient_privilege using message = 'Administrative access with MFA is required';
    end if;

    if action = 'list' then
        return jsonb_build_object('banners', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', f.id, 'title', f.title, 'business_id', f.business_id, 'business_name', b.name,
                'sector', b.sector_code, 'position', f.position, 'enabled', f.enabled, 'starts_at', f.starts_at,
                'ends_at', f.ends_at, 'has_image', f.image_key is not null
            ) order by f.position, f.id)
            from dondepido.featured_banners f join dondepido.businesses b on b.id = f.business_id
        ), '[]'::jsonb));
    end if;

    if action = 'update' then
        banner_id := nullif(input ->> 'id', '')::uuid;
        select f.* into current_banner from dondepido.featured_banners f where f.id = banner_id for update;
        if not found then raise no_data_found using message = 'Banner not available'; end if;
    elsif action is distinct from 'create' then
        raise invalid_parameter_value using message = 'Invalid banner operation';
    end if;

    if (input ? 'position' and (jsonb_typeof(input -> 'position') is distinct from 'number'
            or input ->> 'position' !~ '^[0-9]{1,4}$'))
        or (input ? 'enabled' and jsonb_typeof(input -> 'enabled') is distinct from 'boolean') then
        raise invalid_parameter_value using message = 'Invalid banner position or state';
    end if;
    selected_business := case when input ? 'businessId' then (input ->> 'businessId')::uuid else current_banner.business_id end;
    selected_title := case when input ? 'title' then btrim(input ->> 'title') else current_banner.title end;
    selected_position := coalesce((input ->> 'position')::integer, current_banner.position, 0);
    selected_enabled := coalesce((input ->> 'enabled')::boolean, current_banner.enabled, true);
    selected_start := case when input ? 'startsAt' then nullif(input ->> 'startsAt', '')::timestamptz else current_banner.starts_at end;
    selected_end := case when input ? 'endsAt' then nullif(input ->> 'endsAt', '')::timestamptz else current_banner.ends_at end;
    if selected_title is null or char_length(selected_title) > 120 or selected_title !~ '[^[:space:]]'
        or not exists (select 1 from dondepido.businesses b where b.id = selected_business)
        or (selected_start is not null and selected_end is not null and selected_start >= selected_end) then
        raise invalid_parameter_value using message = 'Invalid banner title, business or validity';
    end if;

    selected_key := current_banner.image_key;
    selected_mime := current_banner.mime_type;
    if input ? 'imageKey' or input ? 'objectKey' then
        selected_key := case when input ? 'imageKey' then input ->> 'imageKey' else input ->> 'objectKey' end;
        selected_mime := null;
        if selected_key is not null then
            if selected_key !~ ('^' || actor::text || '/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}[.](png|jpg|jpeg|webp)$') then
                raise invalid_parameter_value using message = 'Invalid banner image path';
            end if;
            select o.metadata ->> 'mimetype' into selected_mime from storage.objects o
            where o.bucket_id = 'dondepido-featured' and o.name = selected_key and o.owner_id = actor::text;
            expected_mime := case
                when selected_key ~ '[.]png$' then 'image/png'
                when selected_key ~ '[.]webp$' then 'image/webp'
                else 'image/jpeg' end;
            if selected_mime is null or selected_mime not in ('image/png', 'image/jpeg', 'image/webp')
                or (input ? 'mimeType' and (input ->> 'mimeType') is distinct from selected_mime)
                or selected_mime is distinct from expected_mime then
                raise invalid_parameter_value using message = 'Banner image is missing or has an invalid type';
            end if;
        end if;
    end if;

    if action = 'create' then
        insert into dondepido.featured_banners (business_id, title, position, enabled, starts_at, ends_at,
            image_key, mime_type, created_by, updated_by)
        values (selected_business, selected_title, selected_position, selected_enabled, selected_start, selected_end,
            selected_key, selected_mime, actor, actor) returning id into banner_id;
    else
        update dondepido.featured_banners f set business_id = selected_business, title = selected_title,
            position = selected_position, enabled = selected_enabled, starts_at = selected_start, ends_at = selected_end,
            image_key = selected_key, mime_type = selected_mime, updated_by = actor, updated_at = clock_timestamp()
        where f.id = banner_id;
    end if;
    return jsonb_build_object('id', banner_id);
end;
$$;

revoke execute on function dondepido.featured_storage_is_admin(), dondepido.featured_storage_visible(text),
    dondepido.featured_storage_unreferenced(text), dondepido.featured_list(),
    dondepido.featured_image(uuid), dondepido.manage_featured(jsonb) from public, anon, authenticated, service_role;
grant execute on function dondepido.featured_storage_is_admin(), dondepido.featured_storage_unreferenced(text)
    to authenticated;
grant execute on function dondepido.featured_storage_visible(text) to anon, authenticated;
grant execute on function dondepido.featured_list(), dondepido.featured_image(uuid) to dondepido_backend, dondepido_catalog_reader;
grant execute on function dondepido.manage_featured(jsonb) to dondepido_backend;

alter function dondepido.featured_storage_is_admin() owner to dondepido_featured_owner;
alter function dondepido.featured_storage_unreferenced(text) owner to dondepido_featured_owner;
alter function dondepido.manage_featured(jsonb) owner to dondepido_featured_owner;
alter function dondepido.featured_storage_visible(text) owner to dondepido_discovery_owner;
alter function dondepido.featured_list() owner to dondepido_discovery_owner;
alter function dondepido.featured_image(uuid) owner to dondepido_discovery_owner;
revoke create on schema dondepido from dondepido_featured_owner, dondepido_discovery_owner;
revoke dondepido_featured_owner, dondepido_discovery_owner from current_user;
