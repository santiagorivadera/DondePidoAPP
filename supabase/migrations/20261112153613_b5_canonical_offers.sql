update dondepido.catalog_offers o
set name = r.name, category = r.category, brand = r.brand, revision = o.revision + 1
from dondepido.catalog_references r
where r.id = o.variant_id
    and (o.name, o.category, o.brand) is distinct from (r.name, r.category, r.brand);

update dondepido.catalog_offers o
set available = false, revision = o.revision + 1
from dondepido.businesses b
where b.id = o.business_id and b.sector_code = 'kioscos'
    and o.kind = 'individual' and o.variant_id is null and o.available;

create function dondepido.canonicalize_catalog_offer()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
declare
    reference dondepido.catalog_references%rowtype;
begin
    if new.variant_id is not null then
        select r.* into reference from dondepido.catalog_references r where r.id = new.variant_id;
        if not found then raise no_data_found using message = 'Reference not found'; end if;
        new.name := reference.name;
        new.category := reference.category;
        new.brand := reference.brand;
    else
        if new.kind = 'individual' and new.available and exists (
            select 1 from dondepido.businesses b where b.id = new.business_id and b.sector_code = 'kioscos'
        ) then
            raise invalid_parameter_value using message = 'Kiosk offers require a verified reference';
        end if;
        new.name := upper(left(btrim(new.name), 1)) || substring(btrim(new.name) from 2);
    end if;
    return new;
end;
$$;

revoke execute on function dondepido.canonicalize_catalog_offer() from public, anon, authenticated, service_role;
grant execute on function dondepido.canonicalize_catalog_offer() to dondepido_catalog_owner;

create trigger canonicalize_catalog_offer_before_write
before insert or update of variant_id, name, category, brand, available on dondepido.catalog_offers
for each row execute function dondepido.canonicalize_catalog_offer();
