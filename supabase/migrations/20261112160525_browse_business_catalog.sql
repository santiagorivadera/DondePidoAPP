grant dondepido_discovery_owner to current_user;
grant create on schema dondepido to dondepido_discovery_owner;

create function dondepido.browse_business_catalog(target uuid, city_slug text)
returns jsonb
language sql stable security definer
set search_path = pg_catalog
as $$
    with shop as materialized (
        select b.id, b.name, b.sector_code as sector, b.address, b.offers_pickup, b.offers_delivery,
            b.accepting_orders, b.delivery_fee, c.currency_code as currency
        from dondepido.businesses b join dondepido.cities c on c.id = b.city_id
        where b.id = target and c.slug = city_slug
    ), offers as (
        select e.*, s.currency
        from dondepido.catalog_effective(statement_timestamp(), array(
            select o.id from dondepido.catalog_offers o join shop s on s.id = o.business_id
        )) e join shop s on s.id = e.business_id
        order by e.name, e.id limit 150
    )
    select jsonb_build_object(
        'businesses', coalesce((select jsonb_agg(to_jsonb(shop)) from shop), '[]'::jsonb),
        'offers', coalesce((select jsonb_agg(
            (to_jsonb(e) - 'revision' - 'discount_id') || jsonb_build_object('components', coalesce((
                select jsonb_agg(c.item - 'revision' - 'discount_id' order by c.sequence)
                from jsonb_array_elements(e.components) with ordinality as c(item, sequence)
            ), '[]'::jsonb))
            order by e.name, e.id
        ) from offers e), '[]'::jsonb)
    )
$$;

revoke execute on function dondepido.browse_business_catalog(uuid, text) from public, anon, authenticated, service_role;
grant execute on function dondepido.browse_business_catalog(uuid, text) to dondepido_backend;
alter function dondepido.browse_business_catalog(uuid, text) owner to dondepido_discovery_owner;
revoke create on schema dondepido from dondepido_discovery_owner;
revoke dondepido_discovery_owner from current_user;
