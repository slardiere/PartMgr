-- begin ;

-- drop schema if exists partition cascade ;

-- create schema partition ;

create table @extschema@.part_pattern (
   id              char(1) not null,
   part_type       text not null,
   to_char_pattern text not null,
   next_part       interval not null,
   primary key ( id )
) ;

create table @extschema@.part_table (
   schemaname       text not null,
   tablename        text not null,
   keycolumn        text not null,
   pattern          char(1) not null references @extschema@.part_pattern ( id ) ,
   actif            bool not null default 't'::bool,
   cleanable        bool not null default 'f'::bool,
   detachable       bool not null default 'f'::bool,
   retention_period interval,

   primary key ( schemaname, tablename )
);

create table @extschema@.part_trigger (
   schemaname       text not null,
   tablename        text not null,
   triggername      text not null,
   triggerdef       text not null,

   foreign key ( schemaname, tablename )  references @extschema@.part_table ( schemaname, tablename )
) ;


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

insert into @extschema@.part_pattern values
    ('Y','year','YYYY', '1 month'),
    ('M','month','YYYYMM', '1 week'),
    ('W','week','IYYYIW', '3 day'),
    ('D','day', 'YYYYMMDD', '1 day')
;

-- \i part_api.sql
-- \i part_triggers.sql


-- commit ;
