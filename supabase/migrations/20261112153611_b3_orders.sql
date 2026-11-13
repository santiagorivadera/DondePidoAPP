create role dondepido_orders_owner nologin noinherit nobypassrls;
grant dondepido_orders_owner to current_user;
grant usage, create on schema dondepido to dondepido_orders_owner;

create table dondepido.checkout_attempts (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references dondepido.profiles(user_id),
    city_id uuid not null references dondepido.cities(id),
    items jsonb not null check (jsonb_typeof(items) = 'array'),
    fulfillment jsonb not null check (jsonb_typeof(fulfillment) = 'array'),
    snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null check (expires_at > created_at),
    unique (id, customer_id)
);
create table dondepido.order_groups (
    id uuid primary key default gen_random_uuid(),
    attempt_id uuid not null unique,
    customer_id uuid not null references dondepido.profiles(user_id),
    city_id uuid not null references dondepido.cities(id),
    idempotency_key text not null check (char_length(idempotency_key) between 1 and 100),
    currency text not null check (currency ~ '^[A-Z]{3}$'),
    products_total bigint not null check (products_total > 0),
    created_at timestamptz not null default now(),
    unique (customer_id, idempotency_key),
    unique (id, customer_id),
    foreign key (attempt_id, customer_id) references dondepido.checkout_attempts(id, customer_id)
);
create table dondepido.suborders (
    id uuid primary key default gen_random_uuid(),
    group_id uuid not null,
    customer_id uuid not null,
    business_id uuid not null references dondepido.businesses(id),
    business_name text not null,
    pickup_address text not null,
    currency text not null check (currency ~ '^[A-Z]{3}$'),
    subtotal bigint not null check (subtotal > 0),
    mode text not null check (mode in ('pickup', 'delivery')),
    delivery_fee bigint check (delivery_fee between 0 and 9999999999),
    delivery_window text check (char_length(delivery_window) between 1 and 200),
    status text not null default 'received'
        check (status in ('received', 'confirmed', 'rejected', 'completed', 'cancelled', 'expired')),
    reason text check (char_length(reason) between 1 and 500),
    version integer not null default 1 check (version > 0),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    decided_at timestamptz,
    completed_at timestamptz,
    foreign key (group_id, customer_id) references dondepido.order_groups(id, customer_id),
    unique (group_id, business_id),
    unique (id, business_id),
    check (mode <> 'pickup' or delivery_fee is not distinct from 0)
);
create index suborders_customer_idx on dondepido.suborders (customer_id, created_at desc, id);
create index suborders_business_idx on dondepido.suborders (business_id, created_at desc, id);
create index suborders_received_expiry_idx on dondepido.suborders (expires_at) where status = 'received';

create table dondepido.order_delivery_details (
    order_id uuid primary key references dondepido.suborders(id),
    address text not null check (char_length(btrim(address)) between 1 and 400),
    latitude numeric(9,6) check (latitude between -90 and 90),
    longitude numeric(9,6) check (longitude between -180 and 180),
    check ((latitude is null) = (longitude is null))
);
create table dondepido.order_lines (
    order_id uuid not null,
    business_id uuid not null,
    offer_id uuid not null,
    quantity integer not null check (quantity between 1 and 20),
    price bigint not null check (price > 0),
    snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
    primary key (order_id, offer_id),
    foreign key (order_id, business_id) references dondepido.suborders(id, business_id),
    foreign key (offer_id, business_id) references dondepido.catalog_offers(id, business_id)
);
create table dondepido.order_events (
    order_id uuid not null references dondepido.suborders(id),
    version integer not null check (version > 0),
    action text not null check (action in (
        'received', 'confirmed', 'rejected', 'completed', 'cancelled', 'expired', 'proposed', 'accepted', 'declined'
    )),
    actor_id uuid,
    reason text,
    created_at timestamptz not null default now(),
    primary key (order_id, version)
);
create table dondepido.order_proposals (
    order_id uuid not null references dondepido.suborders(id),
    version integer not null check (version > 0),
    status text not null check (status in ('pending', 'accepted', 'declined', 'replaced')),
    terms jsonb not null check (jsonb_typeof(terms) = 'object'),
    created_at timestamptz not null default now(),
    primary key (order_id, version)
);
create unique index order_proposals_pending_idx on dondepido.order_proposals (order_id) where status = 'pending';

create table dondepido.order_notice_consent (
    user_id uuid primary key references dondepido.profiles(user_id) on delete cascade,
    phone_e164 text not null,
    enabled boolean not null,
    updated_at timestamptz not null default now()
);
-- The order reference and verified recipient are queued, without dispatching a provider call.
create table dondepido.order_notice_outbox (
    order_id uuid primary key references dondepido.suborders(id),
    recipient_phone text not null check (recipient_phone ~ '^[+][1-9][0-9]{1,14}$'),
    status text not null default 'queued' check (status in ('queued', 'sent', 'failed', 'cancelled')),
    created_at timestamptz not null default now()
);

alter table dondepido.checkout_attempts enable row level security;
alter table dondepido.order_groups enable row level security;
alter table dondepido.suborders enable row level security;
alter table dondepido.order_delivery_details enable row level security;
alter table dondepido.order_lines enable row level security;
alter table dondepido.order_events enable row level security;
alter table dondepido.order_proposals enable row level security;
alter table dondepido.order_notice_consent enable row level security;
alter table dondepido.order_notice_outbox enable row level security;
revoke all on dondepido.checkout_attempts, dondepido.order_groups, dondepido.suborders, dondepido.order_delivery_details,
    dondepido.order_lines, dondepido.order_events, dondepido.order_proposals, dondepido.order_notice_consent,
    dondepido.order_notice_outbox from public, anon, authenticated, service_role, dondepido_backend, dondepido_catalog_reader;

grant execute on function dondepido.actor_id(), dondepido.actor_has_aal2(),
    dondepido.catalog_effective_price(bigint, integer, bigint), dondepido.catalog_effective(timestamptz, uuid[]),
    dondepido.catalog_search_text(text) to dondepido_orders_owner;
grant select on dondepido.cities, dondepido.businesses, dondepido.business_memberships,
    dondepido.verified_phones, dondepido.catalog_offers, dondepido.catalog_components, dondepido.catalog_discounts
    to dondepido_orders_owner;
-- Row locks require an update grant. A false WITH CHECK policy below prevents direct updates.
grant update (updated_at) on dondepido.businesses to dondepido_orders_owner;
grant select, insert on dondepido.checkout_attempts, dondepido.order_groups, dondepido.suborders,
    dondepido.order_delivery_details, dondepido.order_lines, dondepido.order_events,
    dondepido.order_proposals, dondepido.order_notice_consent to dondepido_orders_owner;
grant update (expires_at) on dondepido.checkout_attempts to dondepido_orders_owner;
grant update (mode, delivery_fee, delivery_window, status, reason, version, decided_at, completed_at)
    on dondepido.suborders to dondepido_orders_owner;
grant update (status) on dondepido.order_proposals to dondepido_orders_owner;
grant update (address, latitude, longitude), delete on dondepido.order_delivery_details to dondepido_orders_owner;
grant update (phone_e164, enabled, updated_at) on dondepido.order_notice_consent to dondepido_orders_owner;
grant insert on dondepido.order_notice_outbox to dondepido_orders_owner;

create policy orders_enabled_city on dondepido.cities for select to dondepido_orders_owner using (enabled);
create policy orders_own_membership on dondepido.business_memberships for select to dondepido_orders_owner
    using (user_id = (select dondepido.actor_id()) and revoked_at is null and (select dondepido.actor_has_aal2()));

create function dondepido.orders_has_membership(candidate uuid)
returns boolean
language sql stable
set search_path = pg_catalog
as $$
    select exists (
        select 1 from dondepido.business_memberships m where m.business_id = candidate
            and m.user_id = (select dondepido.actor_id()) and m.revoked_at is null
    )
$$;
revoke execute on function dondepido.orders_has_membership(uuid) from public, anon, authenticated, service_role;
grant execute on function dondepido.orders_has_membership(uuid) to dondepido_orders_owner;

create policy orders_business_read on dondepido.businesses for select to dondepido_orders_owner using (
    (publication_status = 'published' and not admin_hidden) or dondepido.orders_has_membership(id)
);
create policy orders_business_lock on dondepido.businesses for update to dondepido_orders_owner
    using (publication_status = 'published' and not admin_hidden and accepting_orders) with check (false);
create policy orders_catalog_offer on dondepido.catalog_offers for select to dondepido_orders_owner
    using (exists (select 1 from dondepido.businesses b where b.id = catalog_offers.business_id));
create policy orders_catalog_component on dondepido.catalog_components for select to dondepido_orders_owner
    using (exists (select 1 from dondepido.businesses b where b.id = catalog_components.business_id));
create policy orders_catalog_discount on dondepido.catalog_discounts for select to dondepido_orders_owner
    using (exists (select 1 from dondepido.businesses b where b.id = catalog_discounts.business_id));
create policy orders_own_attempt on dondepido.checkout_attempts for all to dondepido_orders_owner
    using (customer_id = (select dondepido.actor_id()));
create policy orders_own_group on dondepido.order_groups for all to dondepido_orders_owner
    using (customer_id = (select dondepido.actor_id()));
create policy orders_scoped_suborder_read on dondepido.suborders for select to dondepido_orders_owner
    using (customer_id = (select dondepido.actor_id()) or dondepido.orders_has_membership(business_id));
create policy orders_own_suborder_insert on dondepido.suborders for insert to dondepido_orders_owner
    with check (customer_id = (select dondepido.actor_id()) and status = 'received');
create policy orders_scoped_suborder_update on dondepido.suborders for update to dondepido_orders_owner
    using (customer_id = (select dondepido.actor_id()) or dondepido.orders_has_membership(business_id));
create policy orders_scoped_delivery on dondepido.order_delivery_details for all to dondepido_orders_owner
    using (exists (select 1 from dondepido.suborders s where s.id = order_delivery_details.order_id));
create policy orders_scoped_lines on dondepido.order_lines for all to dondepido_orders_owner
    using (exists (select 1 from dondepido.suborders s where s.id = order_lines.order_id));
create policy orders_scoped_events on dondepido.order_events for all to dondepido_orders_owner
    using (exists (select 1 from dondepido.suborders s where s.id = order_events.order_id));
create policy orders_scoped_proposals on dondepido.order_proposals for all to dondepido_orders_owner
    using (exists (select 1 from dondepido.suborders s where s.id = order_proposals.order_id));
create policy orders_verified_phone_read on dondepido.verified_phones for select to dondepido_orders_owner using (
    user_id = (select dondepido.actor_id()) or exists (
        select 1 from dondepido.suborders s where s.customer_id = verified_phones.user_id
            and s.status = 'confirmed' and dondepido.orders_has_membership(s.business_id)
    )
);
create policy orders_notice_consent_read on dondepido.order_notice_consent for select to dondepido_orders_owner using (
    user_id = (select dondepido.actor_id()) or exists (
        select 1 from dondepido.suborders s where s.customer_id = order_notice_consent.user_id
            and s.status = 'confirmed' and dondepido.orders_has_membership(s.business_id)
    )
);
create policy orders_own_consent_insert on dondepido.order_notice_consent for insert to dondepido_orders_owner
    with check (user_id = (select dondepido.actor_id()));
create policy orders_own_consent_update on dondepido.order_notice_consent for update to dondepido_orders_owner
    using (user_id = (select dondepido.actor_id())) with check (user_id = (select dondepido.actor_id()));
create policy orders_eligible_outbox_insert on dondepido.order_notice_outbox for insert to dondepido_orders_owner
    with check (exists (
        select 1 from dondepido.suborders s where s.id = order_notice_outbox.order_id
            and s.status = 'confirmed' and dondepido.orders_has_membership(s.business_id)
    ));

-- Resolve all prices and fulfillment under the same ordered shop locks and clock.
create function dondepido.order_quote_snapshot(selected_city uuid, selected_items jsonb, selected_fulfillment jsonb)
returns jsonb
language plpgsql
set search_path = pg_catalog
as $$
declare
    quote_at timestamptz;
    quote_currency text;
    valid_items integer;
    matched_shops integer;
    product_total bigint;
    grand_total bigint;
    order_rows jsonb;
begin
    select c.currency_code into quote_currency from dondepido.cities c where c.id = selected_city;
    if not found then
        raise object_not_in_prerequisite_state using message = 'The selected city is unavailable';
    end if;
    perform b.id from dondepido.businesses b
    where b.city_id = selected_city and b.publication_status = 'published' and not b.admin_hidden
        and b.accepting_orders and exists (
            select 1 from dondepido.catalog_offers o
            join jsonb_array_elements(selected_items) as i on o.id = (i ->> 'offerId')::uuid
            where o.business_id = b.id
        )
    order by b.id for share of b;
    quote_at := clock_timestamp();

    with selections as (
        select (i ->> 'offerId')::uuid as offer_id, (i ->> 'quantity')::integer as quantity
        from jsonb_array_elements(selected_items) as i
    ), details as (
        select (f ->> 'businessId')::uuid as business_id, f ->> 'mode' as mode
        from jsonb_array_elements(selected_fulfillment) as f
    ), quoted_items as (
        select e.*, i.quantity, i.quantity * e.price as total
        from dondepido.catalog_effective(quote_at, array(select s.offer_id from selections s)) e
        join selections i on i.offer_id = e.id
    ), by_business as (
        select b.id as business_id, b.name, b.address as pickup_address, f.mode,
            case when f.mode = 'delivery' then b.delivery_fee else 0 end as delivery_fee,
            sum(q.total)::bigint as subtotal, count(*) as item_count,
            jsonb_agg((to_jsonb(q) - 'id' - 'business_id') || jsonb_build_object('offer_id', q.id)
                order by q.id) as items
        from quoted_items q
        join dondepido.businesses b on b.id = q.business_id
        join details f on f.business_id = b.id
        where b.city_id = selected_city and b.publication_status = 'published' and not b.admin_hidden
            and b.accepting_orders and ((f.mode = 'pickup' and b.offers_pickup) or
                (f.mode = 'delivery' and b.offers_delivery))
        group by b.id, b.name, b.address, f.mode, b.delivery_fee
    )
    select coalesce(sum(o.item_count), 0)::integer, count(*)::integer, sum(o.subtotal)::bigint,
        case when bool_and(o.delivery_fee is not null) then sum(o.subtotal + o.delivery_fee)::bigint end,
        jsonb_agg((to_jsonb(o) - 'item_count') || jsonb_build_object('total', o.subtotal + o.delivery_fee)
            order by o.business_id)
    into valid_items, matched_shops, product_total, grand_total, order_rows
    from by_business o;

    if valid_items <> jsonb_array_length(selected_items)
        or matched_shops <> jsonb_array_length(selected_fulfillment) then
        raise object_not_in_prerequisite_state using message = 'One or more items or fulfillment options are unavailable';
    end if;
    return jsonb_build_object('currency', quote_currency, 'productsTotal', product_total, 'total', grand_total,
        'orders', order_rows);
end;
$$;

create function dondepido.order_expire(target_order uuid, target_business uuid)
returns void
language sql
set search_path = pg_catalog
as $$
    with expired as (
        update dondepido.suborders s set status = 'expired', version = s.version + 1
        where s.status = 'received' and s.expires_at <= clock_timestamp()
            and (target_order is null or s.id = target_order)
            and (target_business is null or s.business_id = target_business)
            and (target_order is not null or target_business is not null or s.customer_id = dondepido.actor_id())
        returning s.id, s.version
    )
    insert into dondepido.order_events (order_id, version, action)
    select id, version, 'expired' from expired
$$;

create function dondepido.order_rows(target_order uuid, target_business uuid, target_group uuid)
returns jsonb
language sql stable
set search_path = pg_catalog
as $$
    select coalesce(jsonb_agg(row_data order by sort_date desc, sort_id), '[]'::jsonb)
    from (
        select s.created_at as sort_date, s.id as sort_id,
            jsonb_build_object('id', s.id,
                'group_id', case when target_business is null and s.customer_id = dondepido.actor_id() then s.group_id end,
                'business_id', s.business_id, 'business_name', s.business_name,
                'pickup_address', s.pickup_address, 'currency', s.currency, 'mode', s.mode,
                'address', d.address, 'latitude', d.latitude, 'longitude', d.longitude,
                'subtotal', s.subtotal, 'delivery_fee', s.delivery_fee, 'total', s.subtotal + s.delivery_fee,
                'window', s.delivery_window, 'status', s.status, 'reason', s.reason, 'version', s.version,
                'created_at', s.created_at, 'expires_at', s.expires_at, 'decided_at', s.decided_at,
                'completed_at', s.completed_at,
                'proposal', (select p.terms || jsonb_build_object('version', p.version, 'status', p.status)
                    from dondepido.order_proposals p where p.order_id = s.id and p.status = 'pending'
                        and s.status = 'received'),
                'items', (select jsonb_agg(l.snapshot - 'revision' order by l.offer_id)
                    from dondepido.order_lines l where l.order_id = s.id)) as row_data
        from dondepido.suborders s
        left join dondepido.order_delivery_details d on d.order_id = s.id
        where (target_order is null or s.id = target_order)
            and (target_business is null or s.business_id = target_business)
            and (target_group is null or s.group_id = target_group)
            and (target_order is not null or target_business is not null or s.customer_id = dondepido.actor_id())
        order by s.created_at desc, s.id limit 100
    ) rows
$$;

revoke execute on function dondepido.order_quote_snapshot(uuid, jsonb, jsonb), dondepido.order_expire(uuid, uuid),
    dondepido.order_rows(uuid, uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function dondepido.order_quote_snapshot(uuid, jsonb, jsonb), dondepido.order_expire(uuid, uuid),
    dondepido.order_rows(uuid, uuid, uuid) to dondepido_orders_owner;

create function dondepido.manage_orders(input jsonb)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    requested_action text := input ->> 'action';
    selected_city uuid;
    items jsonb;
    fulfillment jsonb;
    row_item jsonb;
    selected_quote jsonb;
    refreshed_quote jsonb;
    quote_id uuid;
    quote_until timestamptz;
    attempt dondepido.checkout_attempts%rowtype;
    group_row dondepido.order_groups%rowtype;
    order_row dondepido.suborders%rowtype;
    delivery_row dondepido.order_delivery_details%rowtype;
    proposal_row dondepido.order_proposals%rowtype;
    command_key text;
    shop_id uuid;
    order_id_value uuid;
    expected integer;
    current_version integer;
    as_staff boolean;
    fulfillment_row jsonb;
    order_item jsonb;
    requested_status text;
    action_record text;
    requested_mode text;
    requested_address text;
    requested_latitude numeric;
    requested_longitude numeric;
    requested_fee bigint;
    requested_window text;
    requested_reason text;
    terms jsonb;
    contact_phone text;
    consent_enabled boolean;
begin
    if actor is null or nullif(current_setting('dondepido.actor_email', true), '') is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
    end if;

    if requested_action = 'consent' then
        if jsonb_typeof(input -> 'enabled') is distinct from 'boolean' then
            raise invalid_parameter_value using message = 'Invalid notice consent';
        end if;
        select p.phone_e164 into contact_phone from dondepido.verified_phones p where p.user_id = actor;
        if not found then raise object_not_in_prerequisite_state using message = 'Verified phone is required'; end if;
        consent_enabled := (input ->> 'enabled')::boolean;
        insert into dondepido.order_notice_consent (user_id, phone_e164, enabled)
            values (actor, contact_phone, consent_enabled)
        on conflict (user_id) do update set phone_e164 = excluded.phone_e164, enabled = excluded.enabled,
            updated_at = clock_timestamp();
        return jsonb_build_object('enabled', consent_enabled);
    end if;

    if requested_action = 'mine' then
        perform dondepido.order_expire(null, null);
        return jsonb_build_object('orders', dondepido.order_rows(null, null, null));
    end if;

    if requested_action = 'inbox' then
        shop_id := nullif(input ->> 'businessId', '')::uuid;
        if not dondepido.orders_has_membership(shop_id) then
            raise insufficient_privilege using message = 'Business access with MFA is required';
        end if;
        perform dondepido.order_expire(null, shop_id);
        return jsonb_build_object('orders', dondepido.order_rows(null, shop_id, null));
    end if;

    if requested_action = 'quote' then
        if not exists (select 1 from dondepido.verified_phones p where p.user_id = actor) then
            raise object_not_in_prerequisite_state using message = 'Verified phone is required';
        end if;
        items := input -> 'items';
        fulfillment := input -> 'fulfillment';
        if jsonb_typeof(items) is distinct from 'array' or jsonb_typeof(fulfillment) is distinct from 'array' then
            raise invalid_parameter_value using message = 'Items and fulfillment are required';
        end if;
        if jsonb_array_length(items) not between 1 and 30 or jsonb_array_length(fulfillment) not between 1 and 5 then
            raise invalid_parameter_value using message = 'Invalid cart size';
        end if;
        for row_item in select value from jsonb_array_elements(items) loop
            if nullif(row_item ->> 'offerId', '') is null
                or jsonb_typeof(row_item -> 'quantity') is distinct from 'number'
                or row_item ->> 'quantity' !~ '^([1-9]|1[0-9]|20)$' then
                raise invalid_parameter_value using message = 'Invalid cart item or quantity';
            end if;
        end loop;
        for row_item in select value from jsonb_array_elements(fulfillment) loop
            requested_mode := row_item ->> 'mode';
            requested_address := btrim(row_item ->> 'address');
            if nullif(row_item ->> 'businessId', '') is null or requested_mode is null
                or requested_mode not in ('pickup', 'delivery') then
                raise invalid_parameter_value using message = 'Invalid fulfillment method';
            end if;
            if requested_mode = 'delivery' then
                if requested_address is null or requested_address !~ '[^[:space:]]' or char_length(requested_address) > 400 then
                    raise invalid_parameter_value using message = 'Delivery address is required';
                end if;
                requested_latitude := nullif(row_item ->> 'latitude', '')::numeric;
                requested_longitude := nullif(row_item ->> 'longitude', '')::numeric;
                if (requested_latitude is null) <> (requested_longitude is null)
                    or requested_latitude not between -90 and 90 or requested_longitude not between -180 and 180 then
                    raise invalid_parameter_value using message = 'Invalid location';
                end if;
            end if;
        end loop;
        if (select count(distinct (i ->> 'offerId')::uuid) from jsonb_array_elements(items) as i)
                <> jsonb_array_length(items)
            or (select count(distinct (f ->> 'businessId')::uuid) from jsonb_array_elements(fulfillment) as f)
                <> jsonb_array_length(fulfillment) then
            raise invalid_parameter_value using message = 'Repeated offer or business';
        end if;
        -- Persist only accepted fields, never the original client payload.
        select jsonb_agg(jsonb_build_object('offerId', (i ->> 'offerId')::uuid, 'quantity', (i ->> 'quantity')::integer))
        into items from jsonb_array_elements(items) as i;
        select jsonb_agg(jsonb_build_object('businessId', (f ->> 'businessId')::uuid, 'mode', f ->> 'mode',
            'address', case when f ->> 'mode' = 'delivery' then btrim(f ->> 'address') end,
            'latitude', case when f ->> 'mode' = 'delivery' then nullif(f ->> 'latitude', '')::numeric end,
            'longitude', case when f ->> 'mode' = 'delivery' then nullif(f ->> 'longitude', '')::numeric end))
        into fulfillment from jsonb_array_elements(fulfillment) as f;

        select c.id into selected_city from dondepido.cities c
        where c.slug = coalesce(nullif(input ->> 'city', ''), 'dean-funes');
        if not found then raise object_not_in_prerequisite_state using message = 'City unavailable'; end if;
        selected_quote := dondepido.order_quote_snapshot(selected_city, items, fulfillment);
        quote_until := clock_timestamp() + interval '24 hours';
        insert into dondepido.checkout_attempts (customer_id, city_id, items, fulfillment, snapshot, expires_at)
        values (actor, selected_city, items, fulfillment, selected_quote, quote_until) returning id into quote_id;
        return selected_quote || jsonb_build_object('quoteToken', quote_id, 'expiresAt', quote_until);
    end if;

    if requested_action = 'submit' then
        quote_id := nullif(input ->> 'quoteToken', '')::uuid;
        command_key := btrim(input ->> 'idempotencyKey');
        if quote_id is null or command_key is null or command_key !~ '^[A-Za-z0-9_-]{1,100}$' then
            raise invalid_parameter_value using message = 'Quote and idempotency key are required';
        end if;

        perform pg_advisory_xact_lock(hashtextextended(actor::text, 2863));
        select a.* into attempt from dondepido.checkout_attempts a where a.id = quote_id and a.customer_id = actor for update;
        if not found then raise no_data_found using message = 'Quote not available'; end if;
        select g.* into group_row from dondepido.order_groups g where g.customer_id = actor and g.idempotency_key = command_key;
        if found and group_row.attempt_id <> quote_id then
            raise unique_violation using message = 'Idempotency key already used for another quote';
        end if;
        select g.* into group_row from dondepido.order_groups g where g.attempt_id = quote_id;
        if found then
            return jsonb_build_object('groupId', group_row.id, 'orders', dondepido.order_rows(null, null, group_row.id));
        end if;
        if attempt.expires_at <= clock_timestamp() then
            raise object_not_in_prerequisite_state using message = 'Quote expired';
        end if;
        if not exists (select 1 from dondepido.verified_phones p where p.user_id = actor) then
            raise object_not_in_prerequisite_state using message = 'Verified phone is required';
        end if;
        begin
            refreshed_quote := dondepido.order_quote_snapshot(attempt.city_id, attempt.items, attempt.fulfillment);
        exception when object_not_in_prerequisite_state then
            raise serialization_failure using message = 'Quote changed, review the updated cart';
        end;
        if refreshed_quote <> attempt.snapshot then
            raise serialization_failure using message = 'Quote changed, review the updated cart';
        end if;

        insert into dondepido.order_groups (attempt_id, customer_id, city_id, idempotency_key, currency, products_total)
        values (quote_id, actor, attempt.city_id, command_key, refreshed_quote ->> 'currency',
            (refreshed_quote ->> 'productsTotal')::bigint) returning * into group_row;
        for row_item in select value from jsonb_array_elements(refreshed_quote -> 'orders') loop
            shop_id := (row_item ->> 'business_id')::uuid;
            select f into fulfillment_row from jsonb_array_elements(attempt.fulfillment) as f
            where (f ->> 'businessId')::uuid = shop_id;
            insert into dondepido.suborders (group_id, customer_id, business_id, business_name, pickup_address,
                currency, subtotal, mode, delivery_fee, expires_at)
            values (group_row.id, actor, shop_id, row_item ->> 'name', row_item ->> 'pickup_address', group_row.currency,
                (row_item ->> 'subtotal')::bigint, row_item ->> 'mode', (row_item ->> 'delivery_fee')::bigint,
                clock_timestamp() + interval '60 minutes') returning id into order_id_value;
            if row_item ->> 'mode' = 'delivery' then
                insert into dondepido.order_delivery_details (order_id, address, latitude, longitude)
                values (order_id_value, fulfillment_row ->> 'address', (fulfillment_row ->> 'latitude')::numeric,
                    (fulfillment_row ->> 'longitude')::numeric);
            end if;
            for order_item in select value from jsonb_array_elements(row_item -> 'items') loop
                insert into dondepido.order_lines (order_id, business_id, offer_id, quantity, price, snapshot)
                values (order_id_value, shop_id, (order_item ->> 'offer_id')::uuid,
                    (order_item ->> 'quantity')::integer, (order_item ->> 'price')::bigint, order_item);
            end loop;
            insert into dondepido.order_events (order_id, version, action, actor_id) values (order_id_value, 1, 'received', actor);
        end loop;
        return jsonb_build_object('groupId', group_row.id, 'orders', dondepido.order_rows(null, null, group_row.id));
    end if;

    if requested_action is null or requested_action not in ('decide', 'complete', 'cancel', 'propose', 'respond') then
        raise invalid_parameter_value using message = 'Invalid order operation';
    end if;
    order_id_value := nullif(input ->> 'orderId', '')::uuid;
    expected := nullif(input ->> 'expectedVersion', '')::integer;
    if order_id_value is null or expected is null or expected < 1 then
        raise invalid_parameter_value using message = 'Order and expected version are required';
    end if;
    select s.* into order_row from dondepido.suborders s where s.id = order_id_value for update;
    if not found then raise no_data_found using message = 'Order not available'; end if;
    as_staff := dondepido.orders_has_membership(order_row.business_id);
    if (requested_action in ('decide', 'complete', 'propose') and not as_staff)
        or (requested_action = 'respond' and order_row.customer_id <> actor)
        or (requested_action = 'cancel' and order_row.customer_id <> actor and not as_staff) then
        raise insufficient_privilege using message = 'Order action is unavailable';
    end if;

    if order_row.status = 'received' and order_row.expires_at <= clock_timestamp() then
        perform dondepido.order_expire(order_id_value, null);
        return jsonb_build_object('orders', dondepido.order_rows(order_id_value, null, null), 'expired', true);
    end if;
    if order_row.version <> expected then
        raise serialization_failure using message = 'Order has changed';
    end if;
    current_version := order_row.version + 1;
    requested_reason := nullif(btrim(input ->> 'reason'), '');
    if char_length(requested_reason) > 500 then
        raise invalid_parameter_value using message = 'Reason is too long';
    end if;

    if requested_action in ('propose', 'respond') then
        if order_row.status <> 'received' then
            raise object_not_in_prerequisite_state using message = 'Order is no longer awaiting confirmation';
        end if;
        select p.* into proposal_row from dondepido.order_proposals p
        where p.order_id = order_id_value and p.status = 'pending';

        if requested_action = 'propose' then
            select d.* into delivery_row from dondepido.order_delivery_details d where d.order_id = order_id_value;
            requested_mode := coalesce(input ->> 'mode', order_row.mode);
            if not exists (select 1 from dondepido.businesses b where b.id = order_row.business_id and (
                (requested_mode = 'pickup' and b.offers_pickup) or (requested_mode = 'delivery' and b.offers_delivery))) then
                raise invalid_parameter_value using message = 'Unsupported fulfillment method';
            end if;

            requested_address := case when requested_mode = 'delivery'
                then coalesce(nullif(btrim(input ->> 'address'), ''), delivery_row.address) end;
            requested_fee := case when requested_mode = 'pickup' then 0
                when input ? 'deliveryFee' then (input ->> 'deliveryFee')::bigint
                when order_row.mode = 'delivery' then order_row.delivery_fee end;
            requested_window := case when input ? 'window' then nullif(btrim(input ->> 'window'), '') else order_row.delivery_window end;
            if (requested_mode = 'delivery' and (requested_address is null or requested_address !~ '[^[:space:]]'
                    or char_length(requested_address) > 400 or requested_fee is null))
                or requested_fee not between 0 and 9999999999 or char_length(requested_window) > 200 then
                raise invalid_parameter_value using message = 'Invalid fulfillment proposal';
            end if;

            terms := jsonb_build_object('mode', requested_mode, 'address', requested_address,
                'latitude', case when requested_address = delivery_row.address then delivery_row.latitude end,
                'longitude', case when requested_address = delivery_row.address then delivery_row.longitude end,
                'delivery_fee', requested_fee, 'window', requested_window);
            update dondepido.order_proposals p set status = 'replaced'
                where p.order_id = order_id_value and p.status = 'pending';
            insert into dondepido.order_proposals (order_id, version, status, terms)
                values (order_id_value, current_version, 'pending', terms);
            action_record := 'proposed';
        else
            if proposal_row.order_id is null or jsonb_typeof(input -> 'accept') is distinct from 'boolean' then
                raise object_not_in_prerequisite_state using message = 'No proposal to respond to';
            end if;
            if (input ->> 'accept')::boolean then
                terms := proposal_row.terms;
                update dondepido.suborders s set mode = terms ->> 'mode',
                    delivery_fee = (terms ->> 'delivery_fee')::bigint, delivery_window = terms ->> 'window'
                where s.id = order_id_value;
                if terms ->> 'mode' = 'delivery' then
                    insert into dondepido.order_delivery_details (order_id, address, latitude, longitude)
                    values (order_id_value, terms ->> 'address', (terms ->> 'latitude')::numeric, (terms ->> 'longitude')::numeric)
                    on conflict (order_id) do update set address = excluded.address, latitude = excluded.latitude,
                        longitude = excluded.longitude;
                else
                    delete from dondepido.order_delivery_details d where d.order_id = order_id_value;
                end if;
                action_record := 'accepted';
            else
                action_record := 'declined';
            end if;
            update dondepido.order_proposals p set status = action_record
            where p.order_id = order_id_value and p.version = proposal_row.version;
        end if;
        update dondepido.suborders s set version = current_version where s.id = order_id_value;
    else
        if requested_action = 'decide' then
            requested_status := input ->> 'decision';
            if requested_status is null or requested_status not in ('confirmed', 'rejected')
                or (requested_status = 'rejected' and (requested_reason is null or requested_reason !~ '[^[:space:]]')) then
                raise invalid_parameter_value using message = 'Invalid order decision';
            end if;
            if order_row.status <> 'received' or (requested_status = 'confirmed' and (
                order_row.delivery_fee is null or exists (select 1 from dondepido.order_proposals p
                    where p.order_id = order_id_value and p.status = 'pending')
            )) then
                raise object_not_in_prerequisite_state using message = 'Order is not ready for this decision';
            end if;
        elsif requested_action = 'complete' then
            requested_status := 'completed';
            if order_row.status <> 'confirmed' then
                raise object_not_in_prerequisite_state using message = 'Only confirmed orders may be completed';
            end if;
        else
            requested_status := 'cancelled';
            if not (
                (order_row.status = 'received' and order_row.customer_id = actor) or
                (order_row.status = 'confirmed' and as_staff and coalesce(requested_reason ~ '[^[:space:]]', false))
            ) then
                raise object_not_in_prerequisite_state using message = 'Order cannot be cancelled';
            end if;
        end if;

        update dondepido.suborders s set status = requested_status, version = current_version, reason = requested_reason,
            decided_at = case when requested_action = 'decide' then clock_timestamp() else s.decided_at end,
            completed_at = case when requested_status = 'completed' then clock_timestamp() else s.completed_at end
        where s.id = order_id_value;
        action_record := requested_status;

        if requested_status = 'confirmed' then
            insert into dondepido.order_notice_outbox (order_id, recipient_phone)
            select order_id_value, p.phone_e164 from dondepido.verified_phones p
            join dondepido.order_notice_consent c on c.user_id = p.user_id and c.phone_e164 = p.phone_e164
            where p.user_id = order_row.customer_id and c.enabled
                -- Real delivery requires an independent provider eligibility check in B4.
                and not exists (select 1 from dondepido.order_lines l where l.order_id = order_id_value
                    and dondepido.catalog_search_text(l.snapshot::text) ~
                        '(^| )(fernet|cerveza|vino|sidra|vodka|whisky|whiskey|ron|gin|tequila|alcohol)( |$)');
        end if;
    end if;

    insert into dondepido.order_events (order_id, version, action, actor_id, reason)
    values (order_id_value, current_version, action_record, actor, requested_reason);
    return jsonb_build_object('orders', dondepido.order_rows(order_id_value, null, null));
end;
$$;

revoke execute on function dondepido.manage_orders(jsonb) from public, anon, authenticated, service_role;
grant execute on function dondepido.manage_orders(jsonb) to dondepido_backend;
alter function dondepido.manage_orders(jsonb) owner to dondepido_orders_owner;
revoke create on schema dondepido from dondepido_orders_owner;
revoke dondepido_orders_owner from current_user;
