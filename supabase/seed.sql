-- Local development reference data. No users, phones or businesses are seeded.
insert into dondepido.cities (slug, name, time_zone, currency_code)
values ('dean-funes', 'Deán Funes', 'America/Argentina/Cordoba', 'ARS')
on conflict (slug) do nothing;
