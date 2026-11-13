create role dondepido_notice_owner nologin noinherit nobypassrls;
create role dondepido_notice_dispatcher nologin noinherit nobypassrls;
grant dondepido_notice_owner to current_user;
grant usage, create on schema dondepido to dondepido_notice_owner;
grant usage on schema dondepido to dondepido_notice_dispatcher;

alter table dondepido.order_notice_outbox
    drop constraint order_notice_outbox_status_check,
    add constraint order_notice_outbox_status_check
        check (status in ('queued', 'dispatching', 'sent', 'failed', 'cancelled', 'uncertain')),
    add column claim_token uuid,
    add column claimed_at timestamptz,
    add column resolved_at timestamptz;

create index order_notice_queue_idx on dondepido.order_notice_outbox (created_at, order_id)
    where status = 'queued';

grant select on dondepido.order_notice_outbox to dondepido_notice_owner;
grant update (status, claim_token, claimed_at, resolved_at) on dondepido.order_notice_outbox to dondepido_notice_owner;
grant select (id, customer_id, business_id, business_name, pickup_address, mode, status)
    on dondepido.suborders to dondepido_notice_owner;
grant select (id, contact_phone_e164, contact_verified_at) on dondepido.businesses to dondepido_notice_owner;
grant select (order_id, address) on dondepido.order_delivery_details to dondepido_notice_owner;
grant select (order_id, offer_id, quantity, snapshot) on dondepido.order_lines to dondepido_notice_owner;
grant select (user_id, phone_e164) on dondepido.verified_phones to dondepido_notice_owner;
grant select (user_id, phone_e164, enabled) on dondepido.order_notice_consent to dondepido_notice_owner;
grant execute on function dondepido.catalog_search_text(text) to dondepido_notice_owner;

create policy notice_outbox_read on dondepido.order_notice_outbox for select to dondepido_notice_owner
    using (true);
create policy notice_outbox_update on dondepido.order_notice_outbox for update to dondepido_notice_owner
    using (status in ('queued', 'dispatching')) with check (status in ('dispatching', 'sent', 'cancelled', 'uncertain'));
create policy notice_order_read on dondepido.suborders for select to dondepido_notice_owner
    using (exists (select 1 from dondepido.order_notice_outbox q where q.order_id = suborders.id
        and q.status = 'queued'));
create policy notice_business_read on dondepido.businesses for select to dondepido_notice_owner
    using (exists (select 1 from dondepido.suborders s where s.business_id = businesses.id));
create policy notice_address_read on dondepido.order_delivery_details for select to dondepido_notice_owner
    using (exists (select 1 from dondepido.order_notice_outbox q where q.order_id = order_delivery_details.order_id
        and q.status = 'queued'));
create policy notice_lines_read on dondepido.order_lines for select to dondepido_notice_owner
    using (exists (select 1 from dondepido.order_notice_outbox q where q.order_id = order_lines.order_id
        and q.status = 'queued'));
create policy notice_phone_read on dondepido.verified_phones for select to dondepido_notice_owner
    using (exists (select 1 from dondepido.suborders s where s.customer_id = verified_phones.user_id));
create policy notice_consent_read on dondepido.order_notice_consent for select to dondepido_notice_owner
    using (exists (select 1 from dondepido.suborders s where s.customer_id = order_notice_consent.user_id));

-- A claimed row never returns to the queue. A crashed or uncertain send needs reconciliation.
create function dondepido.claim_local_notice(target_order uuid default null)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog
as $$
declare
    queued_order uuid;
    payload jsonb;
    dispatch_token uuid;
begin
    select q.order_id into queued_order
    from dondepido.order_notice_outbox q
    where q.status = 'queued' and (target_order is null or q.order_id = target_order)
    order by q.created_at, q.order_id
    limit 1 for update of q skip locked;
    if not found then
        return jsonb_build_object('status', 'empty');
    end if;

    select jsonb_build_object(
        'orderId', s.id, 'recipient', p.phone_e164, 'businessName', s.business_name, 'mode', s.mode,
        'address', case when s.mode = 'delivery' then d.address else s.pickup_address end,
        'contact', case when b.contact_verified_at is not null then b.contact_phone_e164 end,
        'items', l.items
    ) into payload
    from dondepido.order_notice_outbox q
    join dondepido.suborders s on s.id = q.order_id and s.status = 'confirmed'
    join dondepido.verified_phones p on p.user_id = s.customer_id and p.phone_e164 = q.recipient_phone
    join dondepido.order_notice_consent c on c.user_id = p.user_id and c.phone_e164 = p.phone_e164 and c.enabled
    join dondepido.businesses b on b.id = s.business_id
    left join dondepido.order_delivery_details d on d.order_id = s.id
    cross join lateral (
        select jsonb_agg(jsonb_build_object(
            'quantity', line.quantity,
            'name', line.snapshot ->> 'name',
            'components', (
                select coalesce(jsonb_agg(jsonb_build_object(
                    'quantity', part.value -> 'quantity', 'name', part.value ->> 'name'
                ) order by part.position), '[]'::jsonb)
                from jsonb_array_elements(line.snapshot -> 'components') with ordinality as part(value, position)
            )
        ) order by line.offer_id) as items,
        bool_or(dondepido.catalog_search_text(line.snapshot::text) ~
            '(^| )(fernet|cerveza|vino|sidra|vodka|whisky|whiskey|ron|gin|tequila|alcohol)( |$)') as has_alcohol
        from dondepido.order_lines line where line.order_id = s.id
    ) l
    where q.order_id = queued_order and l.items is not null and not l.has_alcohol
        and (s.mode <> 'delivery' or d.address is not null);

    if payload is null then
        update dondepido.order_notice_outbox q set status = 'cancelled', resolved_at = clock_timestamp()
        where q.order_id = queued_order;
        return jsonb_build_object('status', 'cancelled');
    end if;

    dispatch_token := gen_random_uuid();
    update dondepido.order_notice_outbox q set status = 'dispatching', claim_token = dispatch_token,
        claimed_at = clock_timestamp()
    where q.order_id = queued_order;
    return payload || jsonb_build_object('status', 'dispatching', 'claimToken', dispatch_token);
end;
$$;

create function dondepido.finish_local_notice(target_order uuid, target_claim uuid, outcome text)
returns boolean
language plpgsql security definer
set search_path = pg_catalog
as $$
begin
    if outcome is null or outcome not in ('sent', 'uncertain') then
        raise invalid_parameter_value using message = 'Invalid notice dispatch outcome';
    end if;
    update dondepido.order_notice_outbox q set status = outcome, claim_token = null, resolved_at = clock_timestamp()
    where q.order_id = target_order and q.status = 'dispatching' and q.claim_token = target_claim;
    return found;
end;
$$;

revoke execute on function dondepido.claim_local_notice(uuid), dondepido.finish_local_notice(uuid, uuid, text)
    from public, anon, authenticated, service_role, dondepido_backend, dondepido_catalog_reader;
grant execute on function dondepido.claim_local_notice(uuid), dondepido.finish_local_notice(uuid, uuid, text)
    to dondepido_notice_dispatcher;
alter function dondepido.claim_local_notice(uuid) owner to dondepido_notice_owner;
alter function dondepido.finish_local_notice(uuid, uuid, text) owner to dondepido_notice_owner;
revoke create on schema dondepido from dondepido_notice_owner;
revoke dondepido_notice_owner from current_user;
