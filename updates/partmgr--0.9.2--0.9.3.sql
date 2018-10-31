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
          if current_setting('server_version_num')::integer >= 100000
             and (select relkind = 'p' from pg_class join pg_namespace on relnamespace = pg_namespace.oid
                      where relname = i_table and nspname= i_schema )
            then
            -- V10 create partition
            execute ' create table ' || i_schema || '.' || spart
            || ' PARTITION OF  ' || qname
            || ' FOR VALUES FROM ( ' || quote_literal( loval ) || ' ) TO (   ' || quote_literal( hival ) || ' )' ;

            tables := tables + 1 ;

            if current_setting('server_version_num')::integer < 110000
            then
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
            end if;

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


          if current_setting('server_version_num')::integer < 110000
          then
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
          end if ;

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


create or replace function @extschema@.version( )
returns text
language sql
as $$
select '0.9.3'::text
$$ ;
