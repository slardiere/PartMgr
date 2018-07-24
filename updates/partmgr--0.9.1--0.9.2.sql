
alter table @extschema@.part_table add column detachable bool not null default 'f'::bool ;

create table @extschema@.part_index (
   schemaname       text not null,
   tablename        text not null,
   indexdef       text not null,

   foreign key ( schemaname, tablename )  references @extschema@.part_table ( schemaname, tablename )
) ;

create table @extschema@.part_fkey (
   schemaname       text not null,
   tablename        text not null,
   fkeydef          text not null,

   foreign key ( schemaname, tablename )  references @extschema@.part_table ( schemaname, tablename )
) ;


-- fonction create
create or replace function @extschema@.create
(
	i_schema text,
	i_table text,
	i_column text,
        i_period text,
        i_pattern text,
	begin_date date,
	end_date date,
	OUT tables integer,
	OUT indexes integer,
        OUT triggers integer,
        OUT grants integer
)
returns record
LANGUAGE plpgsql
set client_min_messages = warning
as $BODY$
  declare
    loval  date;
    hival  date;
    counter int := 0 ;
    pmonth date ;
    spart text ;
    col text ;
    qname text = i_schema || '.' || i_table ;
    v_triggerdef text ;
    v_indexdef text ;
    v_fkeydef text ;
    v_owner text ;
    v_current_role text ;
    t_grants int = 0 ;
    v_constraint text ;
  begin
    tables = 0 ;
    indexes = 0 ;
    triggers = 0 ;
    grants = 0 ;


    FOR pmonth IN SELECT (begin_date + x * ('1 '||i_period)::interval )::date
                    FROM generate_series(0, @extschema@.between(i_period, begin_date, end_date ) ) x
    LOOP
        loval := date_trunc( i_period , pmonth)::date;
        hival := (loval + ('1 '||i_period)::interval )::date;

        spart = i_table || '_' || to_char ( pmonth , i_pattern );

        begin
          if current_setting('server_version_num')::integer >= 100000 and (select relkind = 'p' from pg_class join pg_namespace on relnamespace = pg_namespace.oid where relname = i_table and nspname= i_schema ) then
            -- V10 create partition
            execute ' create table ' || i_schema || '.' || spart
            || ' PARTITION OF  ' || qname
            || ' FOR VALUES FROM ( ' || quote_literal( loval ) || ' ) TO (   ' || quote_literal( hival ) || ' )' ;

            tables := tables + 1 ;

            -- create index
            for v_indexdef in select replace( indexdef,  qname || ' ' ,  i_schema || '.' || spart || ' ' )
               from @extschema@.part_index
               where schemaname= i_schema and tablename = i_table
            loop
              execute v_indexdef ;
              indexes := indexes + 1;
            end loop ;


            -- create fkey
            for v_fkeydef in select replace( fkeydef,  qname || ' ' ,  i_schema || '.' || spart || ' ' )
               from @extschema@.part_fkey
               where schemaname= i_schema and tablename = i_table
            loop
              execute v_fkeydef ;
            end loop ;

          else -- version < 10 ou partitionnement non natif
            execute ' create table ' || i_schema || '.' || spart || ' ( '
              || ' like ' || qname
              || ' INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES, '
              || ' check ( '|| i_column  ||' >= ' || quote_literal( loval ) || ' and '|| i_column  ||' < ' || quote_literal( hival ) || ' )) '
              || ' inherits ( ' || qname || ') ;' ;

            tables := tables + 1 ;

            FOR col IN SELECT * FROM (VALUES ( i_column )) t(c)
            LOOP

              perform 1 from pg_catalog.pg_attribute a
                where a.attrelid in ( SELECT i.indexrelid
                          FROM pg_catalog.pg_class c,
                               pg_catalog.pg_class c2,
                               pg_catalog.pg_namespace n,
                               pg_catalog.pg_index i
                          WHERE c.relname = spart
                            AND n.nspname = i_schema
                            AND c.relnamespace = n.oid
                            AND c.oid = i.indrelid
                            AND i.indexrelid = c2.oid
                      )
                group by a.attrelid
                having count(*) = 1
                  and ARRAY[ col ] @> array_agg( a.attname::text ) ;
              if not found then
                EXECUTE 'CREATE INDEX idx_' || spart ||'_'||col|| ' ON ' || i_schema || '.' || spart || '('||col||')';
                indexes := indexes + 1;
              end if ;
            END LOOP;
          end if ;

          -- create fk
          FOR v_constraint IN select ' add '||pg_get_constraintdef( con.oid , true )
                                from pg_constraint con
                                    join pg_class c
                                      on con.conrelid=c.oid
                                    join pg_namespace n
                                      on c.relnamespace=n.oid
                                    where con.contype='f'
                                      and n.nspname = i_schema
                                      and c.relname = i_table
          loop
            execute ' ALTER TABLE ' || i_schema || '.' || spart ||  v_constraint ;
          end loop ;

          -- create trigger
          for v_triggerdef in select replace( triggerdef,  qname || ' ' ,  i_schema || '.' || spart || ' ' )
             from @extschema@.part_trigger
             where schemaname= i_schema and tablename = i_table
          loop
            execute v_triggerdef ;
            triggers := triggers + 1;
          end loop ;

          select a.rolname, user into v_owner, v_current_role
            from pg_class c
              join pg_namespace n on c.relnamespace=n.oid
              join pg_roles a on c.relowner=a.oid
            where n.nspname= i_schema and c.relname= i_table ;

          if v_owner <> v_current_role then
            execute 'alter table '|| i_schema || '.' || spart ||' owner to ' || v_owner ;
          end if ;

          -- grant role
          select @extschema@.setgrant( i_schema, i_table, '_' || to_char ( pmonth , i_pattern ) ) into t_grants ;
          grants = grants + t_grants ;

        exception when duplicate_table then
          raise notice 'Create Part : % ', SQLERRM ;
        end ;

        counter = counter + 1 ;

    END LOOP;

    return ;

  end ;

$BODY$ ;

create or replace function @extschema@.detach
(
	i_schema text,
	i_table text,
	i_column text,
        i_period text,
        i_pattern text,
	i_retention_date date,
	OUT tables integer
)
returns integer
set client_min_messages = warning
LANGUAGE plpgsql
as $BODY$
  declare
    loval  timestamp;
    hival  timestamp;
    counter int := 0 ;
    pmonth date ;
    spart text ;
    col text ;
    qname text = i_schema || '.' || i_table ;
    begin_date date ;
  begin

    tables = 0 ;

    -- raise notice 'i_schema %, i_table %, i_column %, i_period %, i_pattern %, retention_date %',i_schema, i_table, i_column, i_period, i_pattern, i_retention_date  ;

    perform schemaname, tablename from @extschema@.part_table
        where schemaname=i_schema and tablename=i_table and detachable
          and (select relkind = 'p' from pg_class
                           join pg_namespace on relnamespace = pg_namespace.oid
                where relname = i_table and nspname= i_schema )
 ;
    if found then

      -- look up for older partition to detach
      select min( to_date(substr(tablename, length(tablename) - length( i_pattern ) +1 , length(tablename)), i_pattern ) ) into begin_date
          from pg_tables where schemaname=i_schema and tablename ~ ('^'||i_table||'_[0-9]{'||length( i_pattern )||'}') ;

      FOR pmonth IN SELECT (begin_date + x * ('1 '||i_period)::interval )::date
                      FROM generate_series(0, @extschema@.between(i_period, begin_date, i_retention_date ) ) x
      LOOP
          loval := date_trunc( i_period , pmonth)::date;
          hival := (loval + ('1 '||i_period)::interval  )::date;

          spart = i_table || '_' || to_char ( pmonth , i_pattern );

          begin
            execute 'ALTER TABLE '|| i_schema || '.' || i_table ||' DETACH PARTITION ' || i_schema || '.' || spart ;

            tables := tables + 1 ;

          exception when others then
            raise notice 'Detach Partition : % ', SQLERRM ;
          end ;

          counter = counter + 1 ;

      END LOOP;

    end if ;

    return ;

  end ;

$BODY$
;


create or replace function @extschema@.detach
(
	OUT o_tables  integer
)
 returns integer
LANGUAGE plpgsql
set client_min_messages = warning
as $BODY$
declare
  p_table record ;
  tables int = 0 ;
begin

  o_tables = 0 ;

  for p_table in select t.schemaname, t.tablename, t.keycolumn, p.part_type, p.to_char_pattern,
                        current_date - t.retention_period as retention_date
                   from @extschema@.part_table t , @extschema@.part_pattern p
                  where t.pattern=p.id and t.actif and t.detachable
                    and (select relkind = 'p' from pg_class
                                     join pg_namespace on relnamespace = pg_namespace.oid
                          where relname = tablename and nspname= schemaname )
                  order by schemaname, tablename
    loop

    select * from @extschema@.detach( p_table.schemaname, p_table.tablename, p_table.keycolumn, p_table.part_type, p_table.to_char_pattern, p_table.retention_date::date )
      into tables ;

    o_tables = o_tables + tables ;

  end loop ;

  return ;

end ;
$BODY$
;

create or replace function @extschema@.setgrant( p_schemaname text, p_tablename text, p_part text )
returns int
language plpgsql
as $BODY$
declare
 v_acl text[] ;
 v_grant text ;
 i int = 0 ;
 v_nb_grant int = 0 ;
begin
  select c.relacl into v_acl
    from pg_class c
      join pg_namespace n
        on c.relnamespace=n.oid
     where c.relkind in ('r', 'p')
       and n.nspname= p_schemaname
       and c.relname= p_tablename  ;
  if found then
    if v_acl is not null
    then
      for i in array_lower( v_acl, 1)..array_upper( v_acl, 1 )
      loop
        select @extschema@.grant(  v_acl[i], p_schemaname||'.'||p_tablename||p_part ) into v_grant ;
        execute v_grant ;
        -- raise notice 'ACL : % % ', i, v_acl[i] ;
        -- raise notice 'GRANT : % % ', i, v_grant ;
        v_nb_grant =  v_nb_grant + 1  ;
      end loop ;
    end if ;
  end if ;

  return v_nb_grant ;
end;
$BODY$ ;

create or replace function @extschema@.version( )
returns text
language sql
as $$
select '0.9.2'::text
$$ ;
