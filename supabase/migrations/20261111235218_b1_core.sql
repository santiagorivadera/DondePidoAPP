create schema dondepido;

revoke all on schema dondepido from public, anon, authenticated, service_role;

create table dondepido.cities (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    name text not null check (char_length(btrim(name)) between 1 and 120),
    time_zone text not null check (char_length(btrim(time_zone)) between 1 and 100),
    currency_code text not null default 'ARS' check (currency_code ~ '^[A-Z]{3}$'),
    enabled boolean not null default true
);

create table dondepido.business_sectors (
    code text primary key check (code ~ '^[a-z]+(-[a-z]+)*$'),
    name text not null check (char_length(btrim(name)) between 1 and 80)
);

insert into dondepido.business_sectors (code, name)
values ('gastronomia', 'Gastronomía'), ('kioscos', 'Kioscos');

create table dondepido.profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    first_name text not null check (char_length(btrim(first_name)) between 1 and 100),
    last_name text not null check (char_length(btrim(last_name)) between 1 and 100),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table dondepido.admin_roles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    granted_at timestamptz not null default now(),
    revoked_at timestamptz check (revoked_at >= granted_at)
);

create table dondepido.verified_phones (
    user_id uuid primary key references dondepido.profiles (user_id) on delete cascade,
    phone_e164 text not null unique check (phone_e164 ~ '^\+[1-9][0-9]{1,14}$'),
    verified_at timestamptz not null
);

create table dondepido.business_applications (
    id uuid primary key default gen_random_uuid(),
    email text not null check (
        email = lower(btrim(email))
        and char_length(email) <= 254
        and email ~ '^[^@[:space:]]+@[^@[:space:]]+$'
    ),
    sector_code text not null references dondepido.business_sectors (code),
    observation text not null check (char_length(btrim(observation)) between 1 and 2000),
    status text not null default 'pending'
        check (status in ('pending', 'approved', 'rejected', 'revoked', 'expired', 'consumed')),
    city_id uuid references dondepido.cities (id),
    decided_by uuid,
    decided_at timestamptz,
    decision_reason text check (char_length(btrim(decision_reason)) between 1 and 1000),
    expires_at timestamptz,
    consumed_by uuid,
    consumed_at timestamptz,
    created_at timestamptz not null default now(),
    unique (id, city_id, sector_code),
    constraint application_decision_shape check (
        (
            status = 'pending'
            and decided_by is null and decided_at is null and decision_reason is null
        ) or (
            status <> 'pending'
            and decided_by is not null and decided_at is not null and decision_reason is not null
        )
    ),
    constraint application_approval_shape check (
        (
            status in ('pending', 'rejected') and city_id is null and expires_at is null
        ) or (
            status in ('approved', 'revoked', 'expired', 'consumed')
            and city_id is not null and expires_at is not null and expires_at > decided_at
        )
    ),
    constraint application_consumption_shape check (
        (
            status = 'consumed' and consumed_by is not null and consumed_at is not null
            and consumed_at >= decided_at and consumed_at < expires_at
        ) or (
            status <> 'consumed' and consumed_by is null and consumed_at is null
        )
    )
);

-- Expiration is materialized by the server before creating a new application for that email.
create unique index business_applications_open_email_idx
    on dondepido.business_applications (email) where status in ('pending', 'approved');

create index business_applications_inbox_idx
    on dondepido.business_applications (status, created_at, id);

create table dondepido.businesses (
    id uuid primary key default gen_random_uuid(),
    application_id uuid not null unique,
    city_id uuid not null references dondepido.cities (id),
    sector_code text not null references dondepido.business_sectors (code),
    name text not null check (char_length(btrim(name)) between 1 and 160),
    address text not null check (char_length(btrim(address)) between 1 and 400),
    logo_object_key text not null check (char_length(btrim(logo_object_key)) between 1 and 512),
    publication_status text not null default 'draft' check (publication_status in ('draft', 'published')),
    admin_hidden boolean not null default false,
    accepting_orders boolean not null default false,
    relevance smallint not null default 50 check (relevance between 1 and 100),
    control_version bigint not null default 1 check (control_version > 0),
    offers_pickup boolean not null default false,
    offers_delivery boolean not null default false,
    contact_phone_e164 text check (contact_phone_e164 ~ '^\+[1-9][0-9]{1,14}$'),
    contact_verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    foreign key (application_id, city_id, sector_code)
        references dondepido.business_applications (id, city_id, sector_code),
    check (contact_verified_at is null or contact_phone_e164 is not null),
    constraint business_publication_requirements check (
        publication_status <> 'published'
        or ((offers_pickup or offers_delivery) and contact_verified_at is not null)
    )
);

create index businesses_public_listing_idx
    on dondepido.businesses (city_id, sector_code, id)
    where publication_status = 'published' and not admin_hidden;

create table dondepido.business_memberships (
    business_id uuid not null references dondepido.businesses (id) on delete cascade,
    user_id uuid not null references dondepido.profiles (user_id) on delete cascade,
    role text not null check (role in ('owner', 'operator')),
    granted_at timestamptz not null default now(),
    revoked_at timestamptz check (revoked_at >= granted_at),
    primary key (business_id, user_id)
);

create index business_memberships_by_user_idx
    on dondepido.business_memberships (user_id, business_id);

-- Each local day stores normalized minute ranges. Split overnight input at midnight.
create table dondepido.business_weekly_hours (
    business_id uuid not null references dondepido.businesses (id) on delete cascade,
    weekday smallint not null check (weekday between 1 and 7),
    opening_minutes int4multirange not null,
    primary key (business_id, weekday),
    check (opening_minutes <@ '{[0,1440)}'::int4multirange)
);

create table dondepido.business_hours_exceptions (
    business_id uuid not null references dondepido.businesses (id) on delete cascade,
    local_date date not null,
    opening_minutes int4multirange not null,
    primary key (business_id, local_date),
    check (opening_minutes <@ '{[0,1440)}'::int4multirange)
);

create table dondepido.audit_events (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid,
    action text not null check (char_length(btrim(action)) between 1 and 100),
    entity_type text not null check (char_length(btrim(entity_type)) between 1 and 100),
    entity_id uuid not null,
    old_values jsonb check (jsonb_typeof(old_values) = 'object'),
    new_values jsonb check (jsonb_typeof(new_values) = 'object'),
    note text check (char_length(btrim(note)) between 1 and 1000),
    created_at timestamptz not null default now()
);

create index audit_events_entity_idx
    on dondepido.audit_events (entity_type, entity_id, created_at desc, id);

alter table dondepido.cities enable row level security;
alter table dondepido.business_sectors enable row level security;
alter table dondepido.profiles enable row level security;
alter table dondepido.admin_roles enable row level security;
alter table dondepido.verified_phones enable row level security;
alter table dondepido.business_applications enable row level security;
alter table dondepido.businesses enable row level security;
alter table dondepido.business_memberships enable row level security;
alter table dondepido.business_weekly_hours enable row level security;
alter table dondepido.business_hours_exceptions enable row level security;
alter table dondepido.audit_events enable row level security;

revoke all on all tables in schema dondepido from public, anon, authenticated, service_role;
