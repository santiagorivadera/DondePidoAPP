create role dondepido_catalog_owner nologin noinherit nobypassrls;
create role dondepido_discovery_owner nologin noinherit nobypassrls;
grant dondepido_catalog_owner, dondepido_discovery_owner to current_user;
grant usage, create on schema dondepido to dondepido_catalog_owner, dondepido_discovery_owner;

alter table dondepido.businesses add column delivery_fee bigint check (delivery_fee between 0 and 9999999999);

create table dondepido.catalog_references (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(btrim(name)) between 1 and 160),
    category text not null check (char_length(btrim(category)) between 1 and 100),
    brand text check (char_length(btrim(brand)) between 1 and 100),
    presentation text check (char_length(btrim(presentation)) between 1 and 160),
    aliases text[] not null default '{}'::text[],
    created_at timestamptz not null default now()
);
create unique index catalog_references_identity_idx on dondepido.catalog_references (
    lower(name), lower(category), lower(coalesce(brand, '')), lower(coalesce(presentation, ''))
);

create table dondepido.catalog_offers (
    id uuid primary key default gen_random_uuid(),
    business_id uuid not null references dondepido.businesses(id),
    variant_id uuid references dondepido.catalog_references(id),
    name text not null check (char_length(btrim(name)) between 1 and 160),
    category text not null check (char_length(btrim(category)) between 1 and 100),
    brand text check (char_length(btrim(brand)) between 1 and 100),
    price bigint not null check (price between 1 and 9999999999),
    kind text not null check (kind in ('individual', 'combo')),
    available boolean not null default true,
    starts_at timestamptz,
    ends_at timestamptz,
    revision bigint not null default 1 check (revision > 0),
    updated_at timestamptz not null default now(),
    unique (id, business_id),
    check (ends_at is null or starts_at is null or ends_at > starts_at),
    check (kind = 'combo' or (starts_at is null and ends_at is null)),
    check (kind = 'individual' or variant_id is null)
);
create index catalog_offers_business_idx on dondepido.catalog_offers (business_id, name, id);

create table dondepido.catalog_components (
    combo_id uuid not null,
    component_id uuid not null,
    business_id uuid not null,
    quantity integer not null check (quantity between 1 and 20),
    primary key (combo_id, component_id),
    foreign key (combo_id, business_id) references dondepido.catalog_offers(id, business_id) on delete cascade,
    foreign key (component_id, business_id) references dondepido.catalog_offers(id, business_id),
    check (combo_id <> component_id)
);
create index catalog_components_offer_idx on dondepido.catalog_components (component_id);

create table dondepido.catalog_discounts (
    id uuid primary key default gen_random_uuid(),
    offer_id uuid not null,
    business_id uuid not null,
    percent integer check (percent between 1 and 99),
    fixed_price bigint check (fixed_price between 1 and 9999999999),
    starts_at timestamptz not null,
    ends_at timestamptz,
    foreign key (offer_id, business_id) references dondepido.catalog_offers(id, business_id) on delete cascade,
    check ((percent is null) <> (fixed_price is null)),
    check (ends_at is null or ends_at > starts_at)
);
create index catalog_discounts_offer_idx on dondepido.catalog_discounts (offer_id, starts_at desc);

alter table dondepido.catalog_references enable row level security;
alter table dondepido.catalog_offers enable row level security;
alter table dondepido.catalog_components enable row level security;
alter table dondepido.catalog_discounts enable row level security;
revoke all on dondepido.catalog_references, dondepido.catalog_offers, dondepido.catalog_components, dondepido.catalog_discounts
    from public, anon, authenticated, service_role, dondepido_backend, dondepido_catalog_reader;

grant execute on function dondepido.actor_id(), dondepido.actor_has_aal2(), dondepido.actor_is_admin()
    to dondepido_catalog_owner;
grant select on dondepido.admin_roles, dondepido.business_memberships, dondepido.businesses
    to dondepido_catalog_owner;
grant update (accepting_orders, delivery_fee, updated_at) on dondepido.businesses to dondepido_catalog_owner;
grant select, insert, update on dondepido.catalog_references, dondepido.catalog_offers to dondepido_catalog_owner;
grant select, insert, delete on dondepido.catalog_components, dondepido.catalog_discounts to dondepido_catalog_owner;
grant select on dondepido.catalog_references, dondepido.catalog_offers, dondepido.catalog_components,
    dondepido.catalog_discounts, dondepido.cities to dondepido_discovery_owner;
grant select (id, city_id, sector_code, name, address, offers_pickup, offers_delivery, accepting_orders, relevance, delivery_fee)
    on dondepido.businesses to dondepido_discovery_owner;

create policy catalog_own_admin_role on dondepido.admin_roles for select to dondepido_catalog_owner
    using (user_id = (select dondepido.actor_id()));
create policy catalog_own_membership on dondepido.business_memberships for select to dondepido_catalog_owner
    using (user_id = (select dondepido.actor_id()) and revoked_at is null and (select dondepido.actor_has_aal2()));

create function dondepido.catalog_has_membership(candidate uuid)
returns boolean
language sql stable
set search_path = pg_catalog
as $$
    select exists (
        select 1 from dondepido.business_memberships m
        where m.business_id = candidate and m.user_id = (select dondepido.actor_id()) and m.revoked_at is null
    )
$$;

revoke execute on function dondepido.catalog_has_membership(uuid) from public, anon, authenticated, service_role;
grant execute on function dondepido.catalog_has_membership(uuid) to dondepido_catalog_owner;

create policy catalog_business_read on dondepido.businesses for select to dondepido_catalog_owner
    using (dondepido.catalog_has_membership(id));
create policy catalog_reception_update on dondepido.businesses for update to dondepido_catalog_owner
    using (dondepido.catalog_has_membership(id)) with check (dondepido.catalog_has_membership(id));
create policy catalog_reference_read on dondepido.catalog_references for select to dondepido_catalog_owner
    using ((select dondepido.actor_id()) is not null);
create policy catalog_reference_create on dondepido.catalog_references for insert to dondepido_catalog_owner
    with check ((select dondepido.actor_is_admin()));
create policy catalog_reference_edit on dondepido.catalog_references for update to dondepido_catalog_owner
    using ((select dondepido.actor_is_admin())) with check ((select dondepido.actor_is_admin()));
create policy catalog_offer_own on dondepido.catalog_offers for all to dondepido_catalog_owner
    using (dondepido.catalog_has_membership(business_id));
create policy catalog_component_own on dondepido.catalog_components for all to dondepido_catalog_owner
    using (dondepido.catalog_has_membership(business_id));
create policy catalog_discount_own on dondepido.catalog_discounts for all to dondepido_catalog_owner
    using (dondepido.catalog_has_membership(business_id));

create policy discovery_enabled_city on dondepido.cities for select to dondepido_discovery_owner using (enabled);
create policy discovery_published_business on dondepido.businesses for select to dondepido_discovery_owner using (
    publication_status = 'published' and not admin_hidden
    and exists (select 1 from dondepido.cities c where c.id = businesses.city_id and c.enabled)
);
create policy discovery_reference_read on dondepido.catalog_references for select to dondepido_discovery_owner using (true);
create policy discovery_offer_read on dondepido.catalog_offers for select to dondepido_discovery_owner using (
    exists (select 1 from dondepido.businesses b where b.id = catalog_offers.business_id)
);
create policy discovery_component_read on dondepido.catalog_components for select to dondepido_discovery_owner using (
    exists (select 1 from dondepido.businesses b where b.id = catalog_components.business_id)
);
create policy discovery_discount_read on dondepido.catalog_discounts for select to dondepido_discovery_owner using (
    exists (select 1 from dondepido.businesses b where b.id = catalog_discounts.business_id)
);

create function dondepido.catalog_search_text(value text)
returns text
language sql immutable
set search_path = pg_catalog
as $$
    select btrim(regexp_replace(translate(lower(coalesce(value, '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g'))
$$;

create function dondepido.catalog_effective_price(
    regular_price bigint, discount_percent integer, discount_price bigint
)
returns bigint
language sql immutable
set search_path = pg_catalog
as $$
    select case
        when discount_price between 1 and regular_price - 1 then discount_price
        when discount_percent between 1 and 99
            and (regular_price * (100 - discount_percent) + 50) / 100 between 1 and regular_price - 1
            then (regular_price * (100 - discount_percent) + 50) / 100
        else regular_price
    end
$$;

-- Resolved sellable terms shared by public discovery and checkout.
create function dondepido.catalog_effective(at_time timestamptz, offer_ids uuid[] default null)
returns table (
    id uuid, business_id uuid, name text, category text, brand text, price bigint, original_price bigint,
    kind text, variant_id uuid, revision bigint, components jsonb, discount_id uuid, promotion_ends_at timestamptz
)
language sql stable
set search_path = pg_catalog
as $$
    with individual as materialized (
        select o.id, o.business_id, o.name, o.category, o.brand, o.kind, o.variant_id, o.revision,
            p.effective_price as price, o.price as original_price,
            case when p.effective_price < o.price then d.id end as discount_id,
            case when p.effective_price < o.price then d.ends_at end as promotion_ends_at
        from dondepido.catalog_offers o
        left join lateral (
            select cd.id, cd.fixed_price, cd.percent, cd.ends_at from dondepido.catalog_discounts cd
            where cd.offer_id = o.id and cd.starts_at <= at_time and (cd.ends_at is null or cd.ends_at > at_time)
            order by cd.starts_at desc, cd.id limit 1
        ) d on true
        cross join lateral (
            select dondepido.catalog_effective_price(o.price, d.percent, d.fixed_price) as effective_price
        ) p
        where o.kind = 'individual' and o.available
            and (offer_ids is null or o.id = any(offer_ids) or exists (
                select 1 from dondepido.catalog_components c
                where c.component_id = o.id and c.combo_id = any(offer_ids)
            ))
    ), combos as (
        select o.id, o.business_id, o.name, o.category, o.brand, o.price, c.reference_price as original_price,
            o.kind, o.variant_id, o.revision, c.items as components, null::uuid as discount_id,
            o.ends_at as promotion_ends_at
        from dondepido.catalog_offers o
        cross join lateral (
            select count(*) as total, count(i.id) as eligible, sum(i.price * cc.quantity)::bigint as reference_price,
                jsonb_agg(jsonb_build_object('offer_id', i.id, 'name', i.name, 'category', i.category,
                    'brand', i.brand, 'variant_id', i.variant_id, 'quantity', cc.quantity, 'price', i.price,
                    'revision', i.revision, 'discount_id', i.discount_id) order by cc.component_id) as items
            from dondepido.catalog_components cc left join individual i on i.id = cc.component_id
            where cc.combo_id = o.id
        ) c
        where o.kind = 'combo' and o.available
            and (o.starts_at is null or o.starts_at <= at_time) and (o.ends_at is null or o.ends_at > at_time)
            and (offer_ids is null or o.id = any(offer_ids))
            and c.total >= 2 and c.total = c.eligible and o.price < c.reference_price
    )
    select i.id, i.business_id, i.name, i.category, i.brand, i.price, i.original_price, i.kind, i.variant_id,
        i.revision, '[]'::jsonb, i.discount_id, i.promotion_ends_at
    from individual i where offer_ids is null or i.id = any(offer_ids)
    union all
    select c.id, c.business_id, c.name, c.category, c.brand, c.price, c.original_price, c.kind, c.variant_id,
        c.revision, c.components, c.discount_id, c.promotion_ends_at from combos c
$$;

revoke execute on function dondepido.catalog_search_text(text),
    dondepido.catalog_effective_price(bigint, integer, bigint), dondepido.catalog_effective(timestamptz, uuid[])
    from public, anon, authenticated, service_role;
grant execute on function dondepido.catalog_search_text(text),
    dondepido.catalog_effective_price(bigint, integer, bigint), dondepido.catalog_effective(timestamptz, uuid[])
    to dondepido_catalog_owner, dondepido_discovery_owner;

create function dondepido.browse_catalog(input jsonb)
returns jsonb
language sql stable security definer
set search_path = pg_catalog
as $$
    with filters as (
        select coalesce(nullif(input ->> 'city', ''), 'dean-funes') as city,
            nullif(input ->> 'sector', '') as sector,
            dondepido.catalog_search_text(input ->> 'category') as category,
            dondepido.catalog_search_text(input ->> 'brand') as brand,
            dondepido.catalog_search_text(left(input ->> 'q', 180)) as search,
            coalesce(nullif(left(input ->> 'seed', 100), ''), current_date::text) as seed
    ), options as (
        select f.*, f.search ~ '^promo(s|cion|ciones)?( |$)' as promotions_only,
            regexp_replace(f.search, '^promo(s|cion|ciones)?( de)?( |$)', '') as term
        from filters f
    ), shops as materialized (
        select b.id, b.name, b.sector_code, b.address, b.offers_pickup, b.offers_delivery,
            b.accepting_orders, b.relevance, b.delivery_fee, c.currency_code,
            -ln(((hashtextextended(b.id::text || f.seed, 2847) & 2147483647) + 1)::numeric / 2147483649)
                / b.relevance as position
        from dondepido.businesses b
        join dondepido.cities c on c.id = b.city_id
        cross join options f
        where c.slug = f.city and (f.sector is null or b.sector_code = f.sector)
    ), filtered_offers as materialized (
        select e.*, s.currency_code
        from dondepido.catalog_effective(statement_timestamp(), array(
            select o.id from dondepido.catalog_offers o join shops s on s.id = o.business_id
        )) e
        join shops s on s.id = e.business_id
        left join dondepido.catalog_references r on r.id = e.variant_id
        cross join options f
        where (not f.promotions_only or e.price < e.original_price)
            and (f.category = '' or f.category = dondepido.catalog_search_text(e.category)
                or exists (select 1 from jsonb_array_elements(e.components) as comp
                    where f.category = dondepido.catalog_search_text(comp ->> 'category')))
            and (f.brand = '' or f.brand = dondepido.catalog_search_text(e.brand)
                or exists (select 1 from jsonb_array_elements(e.components) as comp
                    where f.brand = dondepido.catalog_search_text(comp ->> 'brand')))
            and (f.term = '' or strpos(dondepido.catalog_search_text(concat_ws(' ', e.name, e.brand, e.category,
                r.name, r.presentation, array_to_string(r.aliases, ' '), e.components::text, s.name)), f.term) > 0)
        order by e.name, e.id limit 150
    )
    select jsonb_build_object(
        'businesses', coalesce((
            select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'sector', b.sector_code,
                'address', b.address, 'offers_pickup', b.offers_pickup, 'offers_delivery', b.offers_delivery,
                'accepting_orders', b.accepting_orders, 'delivery_fee', b.delivery_fee,
                'currency', b.currency_code) order by b.position, b.id)
            from (
                select s.* from shops s cross join options f
                where f.term = '' or strpos(dondepido.catalog_search_text(s.name), f.term) > 0
                    or exists (select 1 from filtered_offers e where e.business_id = s.id)
                order by s.position, s.id limit 100
            ) b
        ), '[]'::jsonb),
        'offers', coalesce((
            select jsonb_agg((to_jsonb(e) - 'revision' - 'discount_id') order by e.name, e.id)
            from filtered_offers e
        ), '[]'::jsonb)
    )
$$;

create function dondepido.manage_catalog(input jsonb)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    action text := input ->> 'action';
    business uuid;
    offer uuid;
    reference_id uuid;
    variant dondepido.catalog_references%rowtype;
    saved dondepido.catalog_offers%rowtype;
    offer_name text := btrim(input ->> 'name');
    offer_category text := btrim(input ->> 'category');
    offer_brand text := nullif(btrim(input ->> 'brand'), '');
    offer_kind text;
    offer_price bigint;
    offer_available boolean;
    starts timestamptz;
    ends timestamptz;
    component jsonb;
    selected_component uuid;
    component_quantity integer;
    discount_percent integer;
    discount_price bigint;
    discount_id uuid;
    created_discount uuid;
begin
    if dondepido.actor_id() is null or not dondepido.actor_has_aal2() then
        raise insufficient_privilege using message = 'Verified access with MFA is required';
    end if;

    if action = 'reference' then
        if not dondepido.actor_is_admin() then
            raise insufficient_privilege using message = 'Administrative access is required';
        end if;
        if offer_name is null or offer_name !~ '[^[:space:]]' or char_length(offer_name) > 160
            or offer_category is null or offer_category !~ '[^[:space:]]' or char_length(offer_category) > 100
            or (input ? 'aliases' and jsonb_typeof(input -> 'aliases') is distinct from 'array') then
            raise invalid_parameter_value using message = 'Invalid catalog reference';
        end if;

        reference_id := nullif(input ->> 'variantId', '')::uuid;
        if reference_id is null then
            insert into dondepido.catalog_references (name, category, brand, presentation, aliases)
            values (offer_name, offer_category, offer_brand, nullif(btrim(input ->> 'presentation'), ''),
                array(select left(btrim(value), 160) from jsonb_array_elements_text(
                    coalesce(input -> 'aliases', '[]'::jsonb)) limit 30))
            returning id into reference_id;
        else
            update dondepido.catalog_references r set name = offer_name, category = offer_category,
                brand = offer_brand, presentation = nullif(btrim(input ->> 'presentation'), ''),
                aliases = array(select left(btrim(value), 160) from jsonb_array_elements_text(
                    coalesce(input -> 'aliases', '[]'::jsonb)) limit 30)
            where r.id = reference_id;
            if not found then raise no_data_found using message = 'Reference not found'; end if;
        end if;
        return jsonb_build_object('id', reference_id);
    end if;

    business := nullif(input ->> 'businessId', '')::uuid;
    if action = 'mine' then
        if business is not null and not dondepido.catalog_has_membership(business) then
            raise insufficient_privilege using message = 'Business access is required';
        end if;
        return jsonb_build_object(
            'offers', coalesce((
                select jsonb_agg(to_jsonb(o) || jsonb_build_object(
                    'components', coalesce((select jsonb_agg(jsonb_build_object('offerId', c.component_id,
                        'quantity', c.quantity) order by c.component_id)
                        from dondepido.catalog_components c where c.combo_id = o.id), '[]'::jsonb),
                    'discounts', coalesce((select jsonb_agg(to_jsonb(d) order by d.starts_at, d.id)
                        from dondepido.catalog_discounts d where d.offer_id = o.id), '[]'::jsonb)
                ) order by o.name, o.id)
                from dondepido.catalog_offers o where business is null or o.business_id = business
            ), '[]'::jsonb),
            'references', coalesce((
                select jsonb_agg(to_jsonb(r) order by r.name, r.id) from dondepido.catalog_references r
            ), '[]'::jsonb)
        );
    end if;

    -- Serialize catalog mutations and reception with checkout and administrative visibility.
    perform 1 from dondepido.businesses b where b.id = business for update;
    if not found then raise insufficient_privilege using message = 'Business access is required'; end if;

    if action = 'reception' then
        if jsonb_typeof(input -> 'acceptingOrders') is distinct from 'boolean' then
            raise invalid_parameter_value using message = 'Invalid reception status';
        end if;
        offer_available := (input ->> 'acceptingOrders')::boolean;
        update dondepido.businesses b set accepting_orders = offer_available, updated_at = clock_timestamp()
        where b.id = business;
        return jsonb_build_object('id', business, 'accepting_orders', offer_available);
    end if;

    if action = 'delivery' then
        if not input ? 'deliveryFee'
            or (input -> 'deliveryFee' <> 'null'::jsonb and (
                jsonb_typeof(input -> 'deliveryFee') <> 'number'
                or input ->> 'deliveryFee' !~ '^[0-9]{1,10}$'
            )) then
            raise invalid_parameter_value using message = 'Invalid delivery fee';
        end if;
        offer_price := (input ->> 'deliveryFee')::bigint;
        update dondepido.businesses b set delivery_fee = offer_price, updated_at = clock_timestamp()
        where b.id = business;
        return jsonb_build_object('id', business, 'delivery_fee', offer_price);
    end if;

    offer := nullif(input ->> 'offerId', '')::uuid;
    if offer is not null then
        select o.* into saved from dondepido.catalog_offers o where o.id = offer and o.business_id = business;
        if not found then raise no_data_found using message = 'Offer not available'; end if;
    elsif action is distinct from 'save' then
        raise invalid_parameter_value using message = 'Offer is required';
    end if;

    if action = 'availability' then
        if jsonb_typeof(input -> 'available') is distinct from 'boolean' then
            raise invalid_parameter_value using message = 'Invalid offer availability';
        end if;
        offer_available := (input ->> 'available')::boolean;
        update dondepido.catalog_offers o set available = offer_available, revision = o.revision + 1,
            updated_at = clock_timestamp() where o.id = offer;
        return jsonb_build_object('id', offer, 'available', offer_available);
    end if;

    if action = 'discount' then
        if saved.kind <> 'individual' then
            raise invalid_parameter_value using message = 'Only individual offers can be discounted';
        end if;
        discount_id := nullif(input ->> 'discountId', '')::uuid;
        if discount_id is not null or coalesce((input ->> 'remove')::boolean, false) then
            delete from dondepido.catalog_discounts d
            where d.offer_id = offer and (discount_id is null or d.id = discount_id);
        end if;
        if not coalesce((input ->> 'remove')::boolean, false) then
            starts := coalesce(nullif(input ->> 'startsAt', '')::timestamptz, clock_timestamp());
            ends := nullif(input ->> 'endsAt', '')::timestamptz;
            discount_percent := nullif(input ->> 'percent', '')::integer;
            discount_price := nullif(input ->> 'price', '')::bigint;
            if (discount_percent is null) = (discount_price is null)
                or (ends is not null and ends <= starts)
                or dondepido.catalog_effective_price(saved.price, discount_percent, discount_price) >= saved.price then
                raise invalid_parameter_value using message = 'Invalid discount';
            end if;
            if exists (select 1 from dondepido.catalog_discounts d where d.offer_id = offer
                and tstzrange(d.starts_at, d.ends_at, '[)') && tstzrange(starts, ends, '[)')) then
                raise object_not_in_prerequisite_state using message = 'Discount validity overlaps an existing discount';
            end if;
            insert into dondepido.catalog_discounts (offer_id, business_id, percent, fixed_price, starts_at, ends_at)
            values (offer, business, discount_percent, discount_price, starts, ends) returning id into created_discount;
        end if;
        update dondepido.catalog_offers o set revision = o.revision + 1, updated_at = clock_timestamp()
        where o.id = offer;
        return jsonb_build_object('id', offer, 'discount_id', created_discount);
    end if;

    if action is distinct from 'save' then
        raise invalid_parameter_value using message = 'Invalid catalog operation';
    end if;
    reference_id := nullif(input ->> 'variantId', '')::uuid;
    offer_kind := coalesce(input ->> 'kind', saved.kind, 'individual');
    if reference_id is not null then
        select r.* into variant from dondepido.catalog_references r where r.id = reference_id;
        if not found then raise no_data_found using message = 'Reference not found'; end if;
        offer_name := coalesce(nullif(offer_name, ''), variant.name);
        offer_category := variant.category;
        offer_brand := variant.brand;
    end if;
    offer_price := nullif(input ->> 'price', '')::bigint;
    offer_available := coalesce((input ->> 'available')::boolean, saved.available, true);
    starts := nullif(input ->> 'startsAt', '')::timestamptz;
    ends := nullif(input ->> 'endsAt', '')::timestamptz;
    if offer_name is null or offer_name !~ '[^[:space:]]' or char_length(offer_name) > 160
        or offer_category is null or offer_category !~ '[^[:space:]]' or char_length(offer_category) > 100
        or offer_kind not in ('individual', 'combo') or (saved.id is not null and offer_kind <> saved.kind)
        or offer_price is null or offer_price not between 1 and 9999999999
        or (offer_kind = 'individual' and (starts is not null or ends is not null))
        or (starts is not null and ends is not null and ends <= starts)
        or (offer_kind = 'combo' and reference_id is not null) then
        raise invalid_parameter_value using message = 'Invalid offer';
    end if;
    if offer_kind = 'combo' then
        if jsonb_typeof(input -> 'components') is distinct from 'array' then
            raise invalid_parameter_value using message = 'Combo requires components';
        end if;
        if jsonb_array_length(input -> 'components') not between 2 and 20 then
            raise invalid_parameter_value using message = 'Combo requires 2 to 20 distinct offers';
        end if;
    end if;

    if offer is null then
        insert into dondepido.catalog_offers (business_id, variant_id, name, category, brand, price, kind,
            available, starts_at, ends_at)
        values (business, reference_id, offer_name, offer_category, offer_brand, offer_price, offer_kind,
            offer_available, starts, ends) returning id into offer;
    else
        update dondepido.catalog_offers o set variant_id = reference_id, name = offer_name, category = offer_category,
            brand = offer_brand, price = offer_price, available = offer_available, starts_at = starts,
            ends_at = ends, revision = o.revision + 1, updated_at = clock_timestamp() where o.id = offer;
    end if;
    if offer_kind = 'combo' then
        delete from dondepido.catalog_components c where c.combo_id = offer;
        for component in select value from jsonb_array_elements(input -> 'components') loop
            selected_component := nullif(component ->> 'offerId', '')::uuid;
            component_quantity := nullif(component ->> 'quantity', '')::integer;
            if selected_component is null or component_quantity is null or component_quantity not between 1 and 20
                or not exists (select 1 from dondepido.catalog_offers o where o.id = selected_component
                    and o.business_id = business and o.kind = 'individual')
                or exists (select 1 from dondepido.catalog_components c where c.combo_id = offer
                    and c.component_id = selected_component) then
                raise invalid_parameter_value using message = 'Invalid or repeated combo component';
            end if;
            insert into dondepido.catalog_components (combo_id, component_id, business_id, quantity)
            values (offer, selected_component, business, component_quantity);
        end loop;
        if offer_available and not exists (
            select 1 from dondepido.catalog_effective(greatest(starts, clock_timestamp()), array[offer])
        ) then
            raise object_not_in_prerequisite_state using message = 'Combo must offer a saving with available components';
        end if;
    end if;
    return jsonb_build_object('id', offer);
end;
$$;

revoke execute on function dondepido.browse_catalog(jsonb), dondepido.manage_catalog(jsonb)
    from public, anon, authenticated, service_role;
grant execute on function dondepido.browse_catalog(jsonb) to dondepido_backend, dondepido_catalog_reader;
grant execute on function dondepido.manage_catalog(jsonb) to dondepido_backend;

alter function dondepido.browse_catalog(jsonb) owner to dondepido_discovery_owner;
alter function dondepido.manage_catalog(jsonb) owner to dondepido_catalog_owner;
revoke create on schema dondepido from dondepido_catalog_owner, dondepido_discovery_owner;
revoke dondepido_catalog_owner, dondepido_discovery_owner from current_user;
