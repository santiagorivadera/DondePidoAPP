begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;

select plan(7);

select is_empty(
  $$select rolname from pg_roles
    where rolname in ('anon', 'authenticated')
      and has_schema_privilege(oid, 'dondepido', 'USAGE, CREATE')$$,
  'Browser roles have no access to the private schema'
);

select is_empty(
  $$select roles.rolname, relations.relname
    from pg_roles as roles
    cross join pg_class as relations
    join pg_namespace as namespaces on namespaces.oid = relations.relnamespace
    where roles.rolname in ('anon', 'authenticated')
      and namespaces.nspname = 'dondepido'
      and relations.relkind in ('r', 'p', 'v', 'm', 'f')
      and (
        has_table_privilege(roles.oid, relations.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
        or has_any_column_privilege(roles.oid, relations.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
      )$$,
  'Browser roles have no direct table, view or column privileges in the private schema'
);

select is_empty(
  $$select roles.rolname, routines.proname
    from pg_roles as roles
    cross join pg_proc as routines
    join pg_namespace as namespaces on namespaces.oid = routines.pronamespace
    where roles.rolname in ('anon', 'authenticated')
      and namespaces.nspname = 'dondepido'
      and has_function_privilege(roles.oid, routines.oid, 'EXECUTE')
      and not (
        routines.oid = 'dondepido.featured_storage_visible(text)'::regprocedure
        or (roles.rolname = 'authenticated' and routines.oid in (
          'dondepido.featured_storage_is_admin()'::regprocedure,
          'dondepido.featured_storage_unreferenced(text)'::regprocedure
        ))
      )$$,
  'Browser roles can execute only the functions required by Storage policies'
);

select results_eq(
  $$select rolname::text collate "default" from pg_roles
    where rolname in ('dondepido_backend', 'dondepido_catalog_reader')
      and not rolcanlogin and not rolbypassrls and not rolsuper
      and not rolcreaterole and not rolcreatedb
    order by rolname::text collate "default"$$,
  array['dondepido_backend', 'dondepido_catalog_reader'],
  'Backend and catalog access use distinct, non-login roles without elevated privileges'
);

select is_empty(
  $$select relations.relname from pg_class as relations
    join pg_namespace as namespaces on namespaces.oid = relations.relnamespace
    join pg_roles as owners on owners.oid = relations.relowner
    where namespaces.nspname = 'dondepido' and relations.relkind in ('r', 'p')
      and (not relations.relrowsecurity
        or owners.rolname in ('dondepido_backend', 'dondepido_catalog_reader'))$$,
  'RLS is enabled on private tables and runtime roles do not own them'
);

select is_empty(
  $$select roles.rolname from pg_roles as roles
    where roles.rolname in ('anon', 'authenticated')
      and (pg_has_role(roles.oid, 'dondepido_backend', 'MEMBER')
        or pg_has_role(roles.oid, 'dondepido_catalog_reader', 'MEMBER'))$$,
  'Browser roles cannot assume internal runtime roles'
);

select ok(
  not has_function_privilege(
    'dondepido_catalog_reader',
    'dondepido.set_business_controls(uuid,bigint,boolean,integer,text)',
    'EXECUTE'
  ),
  'The catalog reader cannot execute the administrative controls operation'
);

select * from finish();
rollback;
