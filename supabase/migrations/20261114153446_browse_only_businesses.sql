alter table dondepido.businesses drop constraint businesses_publication_status_check;
alter table dondepido.businesses add constraint businesses_publication_status_check
    check (publication_status in ('draft', 'catalog_only', 'published'));
alter table dondepido.businesses add constraint business_catalog_only_no_orders
    check (publication_status <> 'catalog_only' or not accepting_orders);

alter policy discovery_published_business on dondepido.businesses using (
    publication_status in ('published', 'catalog_only') and not admin_hidden
    and exists (select 1 from dondepido.cities c where c.id = businesses.city_id and c.enabled)
);

grant select on dondepido.business_weekly_hours to dondepido_backend;
create policy scoped_weekly_hours_read on dondepido.business_weekly_hours for select to dondepido_backend using (
    exists (
        select 1 from dondepido.business_memberships m
        where m.business_id = business_weekly_hours.business_id
          and m.user_id = (select dondepido.actor_id()) and m.revoked_at is null
    )
);
