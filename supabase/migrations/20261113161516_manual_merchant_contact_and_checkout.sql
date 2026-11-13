alter table dondepido.business_applications
    add column verified_contact_phone text check (verified_contact_phone ~ '^\+[1-9][0-9]{7,14}$'),
    add column verified_contact_at timestamptz,
    add column contact_verification_method text check (contact_verification_method in ('call', 'whatsapp')),
    add constraint application_contact_verification_shape check (
        num_nonnulls(verified_contact_phone, verified_contact_at, contact_verification_method) in (0, 3)
    );

alter table dondepido.suborders
    add column customer_contact_phone text check (customer_contact_phone ~ '^\+[1-9][0-9]{7,14}$');

grant update (verified_contact_phone, verified_contact_at, contact_verification_method)
    on dondepido.business_applications to dondepido_backend;

alter policy admin_approved_application_audit on dondepido.audit_events with check (
    (select dondepido.actor_is_admin()) and actor_id = (select dondepido.actor_id())
    and entity_type = 'business_application'
    and action in ('application_corrected', 'application_suspension_changed', 'application_contact_verified')
);

create function dondepido.clear_application_contact_on_email_change()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
    new.verified_contact_phone := null;
    new.verified_contact_at := null;
    new.contact_verification_method := null;
    return new;
end;
$$;

revoke execute on function dondepido.clear_application_contact_on_email_change()
    from public, anon, authenticated, service_role;

create trigger clear_application_contact_on_email_change
    before update of email on dondepido.business_applications
    for each row when (old.email is distinct from new.email)
    execute function dondepido.clear_application_contact_on_email_change();

create function dondepido.verify_application_contact(
    application_id uuid, phone text, method text
) returns void
language plpgsql security invoker
set search_path = pg_catalog
as $$
declare
    application dondepido.business_applications%rowtype;
    confirmed_at timestamptz := clock_timestamp();
begin
    if not dondepido.actor_is_admin()
        or nullif(current_setting('dondepido.actor_email', true), '') is null then
        raise insufficient_privilege;
    end if;
    if phone is null or phone !~ '^\+[1-9][0-9]{7,14}$'
        or method is null or method not in ('call', 'whatsapp') then
        raise invalid_parameter_value;
    end if;

    select a.* into application from dondepido.business_applications a
    where a.id = application_id for update;
    if not found then raise no_data_found; end if;
    if application.status not in ('approved', 'consumed')
        or (application.status = 'approved' and application.expires_at <= clock_timestamp()) then
        raise object_not_in_prerequisite_state;
    end if;

    update dondepido.business_applications a
    set verified_contact_phone = phone, verified_contact_at = confirmed_at, contact_verification_method = method
    where a.id = application.id;
    insert into dondepido.audit_events (actor_id, action, entity_type, entity_id, old_values, new_values)
    values (dondepido.actor_id(), 'application_contact_verified', 'business_application', application.id,
        jsonb_build_object('method', application.contact_verification_method, 'verified_at', application.verified_contact_at),
        jsonb_build_object('method', method, 'verified_at', confirmed_at,
            'phone_changed', phone is distinct from application.verified_contact_phone));
end;
$$;

revoke execute on function dondepido.verify_application_contact(uuid, text, text)
    from public, anon, authenticated, service_role;
grant execute on function dondepido.verify_application_contact(uuid, text, text)
    to dondepido_backend;

-- Replace existing functions with their original owners and grants.
grant dondepido_onboarding_owner, dondepido_orders_owner to current_user;
grant create on schema dondepido to dondepido_onboarding_owner, dondepido_orders_owner;

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
    if not exists (select 1 from dondepido.cities c where c.id = application.city_id) then
        raise object_not_in_prerequisite_state using message = 'Enabled city is required';
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


create function dondepido.business_verified_contact(business_id uuid)
returns text
language sql stable security definer
set search_path = pg_catalog
as $$
    select coalesce(a.verified_contact_phone, b.contact_phone_e164, p.phone_e164)
    from dondepido.businesses b
    join dondepido.business_memberships m on m.business_id = b.id
    left join dondepido.business_applications a on a.id = b.application_id
    left join dondepido.verified_phones p on p.user_id = m.user_id
    where b.id = business_verified_contact.business_id and m.user_id = dondepido.actor_id()
        and dondepido.onboarding_email() is not null and m.role = 'owner' and m.revoked_at is null
$$;

alter function dondepido.business_verified_contact(uuid) owner to dondepido_onboarding_owner;
revoke execute on function dondepido.business_verified_contact(uuid) from public, anon, authenticated, service_role;
grant execute on function dondepido.business_verified_contact(uuid) to dondepido_backend;

create function dondepido.publish_business(id uuid, pickup boolean, delivery boolean, expected_phone text)
returns void
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    actor uuid := dondepido.actor_id();
    contact_phone text;
    contact_verified timestamptz;
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

    -- A manual verification is private until the owner explicitly publishes the contact.
    if expected_phone is not null then
        select a.verified_contact_phone, a.verified_contact_at into contact_phone, contact_verified
        from dondepido.business_applications a
        join dondepido.businesses b on b.application_id = a.id
        where b.id = publish_business.id for share of a;
    end if;
    if contact_phone is null then
        select b.contact_phone_e164, b.contact_verified_at into contact_phone, contact_verified
        from dondepido.businesses b where b.id = publish_business.id and b.contact_verified_at is not null;
    end if;
    if contact_phone is null then
        select p.phone_e164, p.verified_at into contact_phone, contact_verified
        from dondepido.verified_phones p where p.user_id = actor for share;
    end if;
    if contact_phone is null then
        raise object_not_in_prerequisite_state using message = 'Verified business contact is required';
    end if;
    if expected_phone is not null and expected_phone is distinct from contact_phone then
        raise serialization_failure using message = 'Verified business contact changed';
    end if;

    update dondepido.businesses b set publication_status = 'published', offers_pickup = pickup,
        offers_delivery = delivery, contact_phone_e164 = contact_phone,
        contact_verified_at = contact_verified, updated_at = clock_timestamp()
    where b.id = publish_business.id and not b.admin_hidden
        and exists (select 1 from dondepido.cities c where c.id = b.city_id);
    if not found then
        raise object_not_in_prerequisite_state using message = 'Business is not eligible to publish';
    end if;
end;
$$;

alter function dondepido.publish_business(uuid, boolean, boolean, text) owner to dondepido_onboarding_owner;
revoke execute on function dondepido.publish_business(uuid, boolean, boolean, text)
    from public, anon, authenticated, service_role;
grant execute on function dondepido.publish_business(uuid, boolean, boolean, text) to dondepido_backend;

-- During rollout, older callers can still publish an existing or SMS-verified number.
create or replace function dondepido.publish_business(id uuid, pickup boolean, delivery boolean)
returns void
language sql security invoker
set search_path = pg_catalog
as $$
    select dondepido.publish_business(id, pickup, delivery, null::text)
$$;


create or replace function dondepido.order_rows(target_order uuid, target_business uuid, target_group uuid)
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
                'customer_phone', s.customer_contact_phone,
                'business_phone', case when s.customer_id = dondepido.actor_id()
                    and s.status in ('confirmed', 'completed') and b.contact_verified_at is not null
                    then b.contact_phone_e164 end,
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
        left join dondepido.businesses b on b.id = s.business_id
        where (target_order is null or s.id = target_order)
            and (target_business is null or s.business_id = target_business)
            and (target_group is null or s.group_id = target_group)
            and (target_order is not null or target_business is not null or s.customer_id = dondepido.actor_id())
        order by s.created_at desc, s.id limit 100
    ) rows
$$;


create or replace function dondepido.manage_orders(input jsonb)
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
    customer_phone text;
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
        if input ? 'contactPhone' and jsonb_typeof(input -> 'contactPhone') not in ('string', 'null') then
            raise invalid_parameter_value using message = 'Invalid customer contact phone';
        end if;
        customer_phone := nullif(btrim(input ->> 'contactPhone'), '');
        if customer_phone is not null and customer_phone !~ '^\+[1-9][0-9]{7,14}$' then
            raise invalid_parameter_value using message = 'Invalid customer contact phone';
        end if;
        if attempt.expires_at <= clock_timestamp() then
            raise object_not_in_prerequisite_state using message = 'Quote expired';
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
                currency, subtotal, mode, delivery_fee, expires_at, customer_contact_phone)
            values (group_row.id, actor, shop_id, row_item ->> 'name', row_item ->> 'pickup_address', group_row.currency,
                (row_item ->> 'subtotal')::bigint, row_item ->> 'mode', (row_item ->> 'delivery_fee')::bigint,
                clock_timestamp() + interval '60 minutes', customer_phone) returning id into order_id_value;
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


revoke create on schema dondepido from dondepido_onboarding_owner, dondepido_orders_owner;
revoke dondepido_onboarding_owner, dondepido_orders_owner from current_user;
