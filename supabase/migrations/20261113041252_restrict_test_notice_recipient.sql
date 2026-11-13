grant dondepido_notice_owner to current_user;
grant create on schema dondepido to dondepido_notice_owner;

create function dondepido.claim_test_notice(target_order uuid, expected_recipient text)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog
as $$
begin
    -- Lock only a matching row, so an incorrect test target cannot consume an order.
    perform 1
    from dondepido.order_notice_outbox q
    where q.order_id = target_order and q.status = 'queued'
        and q.recipient_phone = expected_recipient
    for update of q skip locked;
    if not found then
        return jsonb_build_object('status', 'empty');
    end if;
    return dondepido.claim_local_notice(target_order);
end;
$$;

revoke execute on function dondepido.claim_test_notice(uuid, text)
    from public, anon, authenticated, service_role, dondepido_backend, dondepido_catalog_reader;
grant execute on function dondepido.claim_test_notice(uuid, text) to dondepido_notice_dispatcher;
alter function dondepido.claim_test_notice(uuid, text) owner to dondepido_notice_owner;
revoke create on schema dondepido from dondepido_notice_owner;
revoke dondepido_notice_owner from current_user;
