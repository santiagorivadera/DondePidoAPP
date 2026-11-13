grant dondepido_orders_owner to current_user;
grant create on schema dondepido to dondepido_orders_owner;

create function dondepido.order_stats(business uuid)
returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog
as $$
declare
    zone text;
    result jsonb;
begin
    if not dondepido.actor_has_aal2() or not dondepido.orders_has_membership(business) then
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

revoke execute on function dondepido.order_stats(uuid) from public, anon, authenticated, service_role;
grant execute on function dondepido.order_stats(uuid) to dondepido_backend;
alter function dondepido.order_stats(uuid) owner to dondepido_orders_owner;
revoke create on schema dondepido from dondepido_orders_owner;
revoke dondepido_orders_owner from current_user;
