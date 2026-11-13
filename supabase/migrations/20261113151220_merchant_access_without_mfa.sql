-- Commercial operations require an authenticated account and active membership.
-- Administrative authorization continues to require actor_is_admin() and AAL2.
alter policy own_membership_read on dondepido.business_memberships using (
    user_id = (select dondepido.actor_id()) and revoked_at is null
);

alter policy scoped_business_read on dondepido.businesses using (
    (select dondepido.actor_is_admin()) or exists (
        select 1 from dondepido.business_memberships
        where business_id = businesses.id and user_id = (select dondepido.actor_id())
            and revoked_at is null
    )
);

alter policy onboarding_publish on dondepido.businesses using (
    not admin_hidden and exists (
        select 1 from dondepido.business_memberships m where m.business_id = businesses.id
            and m.user_id = (select dondepido.actor_id()) and m.role = 'owner' and m.revoked_at is null
    )
);

alter policy onboarding_weekly_hours on dondepido.business_weekly_hours using (
    exists (
        select 1 from dondepido.business_memberships m
        where m.business_id = business_weekly_hours.business_id
            and m.user_id = (select dondepido.actor_id()) and m.role = 'owner' and m.revoked_at is null
    )
);

alter policy catalog_own_membership on dondepido.business_memberships using (
    user_id = (select dondepido.actor_id()) and revoked_at is null
);

alter policy orders_own_membership on dondepido.business_memberships using (
    user_id = (select dondepido.actor_id()) and revoked_at is null
);

-- Keep the existing function owners and execute grants when replacing the bodies.
grant dondepido_onboarding_owner, dondepido_catalog_owner, dondepido_orders_owner to current_user;
grant create on schema dondepido to dondepido_onboarding_owner, dondepido_catalog_owner, dondepido_orders_owner;

create or replace function dondepido.publish_business(id uuid, pickup boolean, delivery boolean)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    contact dondepido.verified_phones%rowtype;
begin
    if actor is null or dondepido.onboarding_email() is null
        or not exists (
            select 1 from dondepido.business_memberships m where m.business_id = publish_business.id
                and m.user_id = actor and m.role = 'owner' and m.revoked_at is null
        ) then
        raise insufficient_privilege using message = 'Business owner access is required';
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

create or replace function dondepido.set_business_weekly_hours(business_id uuid, hours jsonb)
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
    if actor is null or dondepido.onboarding_email() is null
        or not exists (
            select 1 from dondepido.business_memberships m
            where m.business_id = set_business_weekly_hours.business_id
                and m.user_id = actor and m.role = 'owner' and m.revoked_at is null
        ) then
        raise insufficient_privilege using message = 'Business owner access is required';
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

create or replace function dondepido.manage_catalog(input jsonb)
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
    if dondepido.actor_id() is null or nullif(current_setting('dondepido.actor_email', true), '') is null then
        raise insufficient_privilege using message = 'A confirmed account is required';
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
        if (business is null and not dondepido.actor_is_admin())
            or (business is not null and not dondepido.catalog_has_membership(business)) then
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

create or replace function dondepido.order_stats(business uuid)
returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog
as $$
declare
    zone text;
    result jsonb;
begin
    if nullif(current_setting('dondepido.actor_email', true), '') is null or not dondepido.orders_has_membership(business) then
        raise insufficient_privilege using message = 'Business membership required';
    end if;

    select c.time_zone into zone
    from dondepido.businesses b join dondepido.cities c on c.id = b.city_id
    where b.id = business;
    if not found then raise no_data_found using message = 'Business unavailable'; end if;

    with events as materialized (
        select e.action, e.created_at at time zone zone as local_time
        from dondepido.suborders s join dondepido.order_events e on e.order_id = s.id
        where s.business_id = business
    ), completed as materialized (
        select to_char(local_time, 'YYYY-MM') as month_label,
            extract(isodow from local_time)::integer::text as weekday_label,
            to_char(local_time, 'HH24') as hour_label
        from events where action = 'completed'
    )
    select jsonb_build_object(
        'timeZone', zone,
        'counts', (select jsonb_build_object(
            'received', count(*) filter (where action = 'received'),
            'confirmed', count(*) filter (where action = 'confirmed'),
            'rejected', count(*) filter (where action = 'rejected'),
            'completed', count(*) filter (where action = 'completed'),
            'cancelled', count(*) filter (where action = 'cancelled'),
            'expired', count(*) filter (where action = 'expired')
        ) from events),
        'peakMonth', (select jsonb_build_object('label', month_label, 'count', count(*))
            from completed group by month_label order by count(*) desc, month_label limit 1),
        'peakWeekday', (select jsonb_build_object('label', weekday_label, 'count', count(*))
            from completed group by weekday_label order by count(*) desc, weekday_label limit 1),
        'peakHour', (select jsonb_build_object('label', hour_label, 'count', count(*))
            from completed group by hour_label order by count(*) desc, hour_label limit 1)
    ) into result;
    return result;
end;
$$;

revoke create on schema dondepido from dondepido_onboarding_owner, dondepido_catalog_owner, dondepido_orders_owner;
revoke dondepido_onboarding_owner, dondepido_catalog_owner, dondepido_orders_owner from current_user;
