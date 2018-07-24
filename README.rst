Partmgr
=======

Partmgr is a set of tables and functions wrote to help the management
of partitionning tables in PostgreSQL databases.

The partition key is a date, matching a table's attribute. It is
possible to set up a retention period

Partmgr's tables are catalog which contains informations about
partition type, tables and triggers

Functions can manage trigger creation, partition, drop, and
monitoring.

Tables ( catalog )
--------------------

Tables are in "partmgr" schema :

  - ``partmgr.part_pattern`` : partition's type
  - ``partmgr.part_table`` : partitionned tables
  - ``partmgr.part_trigger`` : trigger's partitionned tables

from PostgreSQL 10  :

  - ``partmgr.part_index`` : index of partitionned tables
  - ``partmgr.part_fkey`` : foreign key of partitionned tables

Table ``part_pattern`` contiens some partitioning patterns. Until
there no new pattern, there is no need to modify it. Different
patterns, and therefore partition types are: ``year``, ``month``,
``week``, and ``day``.

Table ``part_table`` contains user's tables, and must be set by the user.

La table ``part_trigger`` contains partition table's triggers. Filling
this table is automatically done when the user set up a new partition
table.

Functions list
--------------------

  - ``fonction partmgr.between()`` : compute unit number betwenn two date fon a given pattern.
  - ``fonctions partmgr.create()`` : create the partitions

    -  ``partmgr.create()`` : generic function, which create partitions for all tables, at the current date.
    -  ``partmgr.create( date)`` : create partitions for all tables, at the given date.
    -  ``partmgr.create( begin_date, end_date )`` : create partitions for all tables, at the given period.
    -  ``partmgr.create( schema, table, begin_date, end_date )`` : create partitions for the given table, at the given period.
    -  ``partmgr.create( schema, table, column, period, pattern, begin_date, end_date )`` : low-level function fonction,
called by all ``create`` functions.

  - ``function partmgr.create_next()`` : create next functions of all tables. The next period depends of current date,
plus ``next_part`` interval from pattern. This fonction could called by a scheduler like cron.
  - ``function partmgr.drop()`` : drop partition, if permit by setup.
  - ``function partmgr.detach()`` : detach partition, if permit by setup.
  - ``function partmgr.check_next_part()`` : had to be called by Nagios plugin. Can monitoring if next partition exists.

  - ``function partmgr.grant_replace( p_acl text, p_grant text, p_ext_grant text )`` :
  - ``function partmgr.grant( acl text, tablename text )`` :
  - ``function partmgr.setgrant( p_schemaname text, p_tablename text, p_part text )`` : used by ``partmgr.create()`` to apply grants on partitions.

  - ``function partmgr.create_part_trigger()`` : create partitioning triggers, and create the trigger on the partmgr.
  - ``function partmgr.set_trigger_def()`` : Trigger function which copy trigger definition from mother table to catalog. Triggered on ``partmgr."table"``

Tutorial
````````

Installation
::::::::::::

Install PartMgr as extension. It make the schema, tables and
functions, and fill the table ::

  $ make
  $ make install
  $ psql -Upostgres dbname
  # create schema partmgr ;
  # create extension partmgr WITH SCHEMA partmgr ;

If Partmgr was already used before, migrate from old installation ::

  $ make
  $ make install
  $ psql -Upostgres dbname
  # create schema partmgr ;
  # create extension partmgr WITH SCHEMA partmgr from unpackaged;
  # drop schema partition cascade ;


Setup
:::::

There is two operations needed to setup up partitionning table. One is
insertion into ``partmgr.part_table`` ::

  INSERT INTO partmgr.part_table ( schemaname, tablename, keycolumn, pattern, actif, cleanable, retention_period)
    values ('test', 'test1mois', 'ev_date', 'M', 't', 'f', null),
           ('test', 'test_mois', 'ev_date', 'M', 't', 't', '1 mon') ;

From PostgreSQL 10, native partitionned tables are managed and detachable :

  INSERT INTO partmgr.part_table ( schemaname, tablename, keycolumn, pattern, actif, detachable, retention_period)
    values ('test', 'test1mois', 'ev_date', 'M', 't', 'f', null) ;

Triggers on this table are inserted into ``partmgr.part_trigger`` to
be auto-added on partition. These triggers won't be present on the
mother table.

Privileges setted up on the mother table are automatically applied on
partitions.

The second step is creation and setup of partitionning trigger ::

  SELECT partmgr.create_part_trigger('schema_name','table_name');

This function make the specific function trigger for the given
table. The new trigger function is created in the ``partmgr`` schema
and the trigger ``_partitionne`` is created on the table.

When using native partitionning, this function is not used.

Partition Creation
::::::::::::::::::

Then, the set of partition should be created with ``partmgr.create()`` functions ::

  part=$ select * from partmgr.create('2012-09-01','2012-11-01') ;
   o_tables | o_indexes | o_triggers | o_grants
  ----------+-----------+------------+----------
         74 |        74 |         65 |      126
  (1 row)

  part=$ select * from partmgr.create('test','test_mois','2012-11-01','2013-03-01') ;
   o_tables | o_indexes | o_triggers | o_grants
  ----------+-----------+------------+----------
          4 |         4 |          0 |        4
  (1 row)


then dropped by ``partmgr.drop()`` function ::

  part=$ select * from partmgr.drop() ;
   o_tables
  ----------
          0
  (1 row)

Only partitions ``cleanable``  and whose retention period has passed will be deleted.

With natives partitionning, partitions are detachable :

  part=$ select * from partmgr.detach() ;
   o_tables
  ----------
          0
  (1 row)

Only partitions ``detachable``  and whose retention period has passed will be detached.


Schedule Creation
:::::::::::::::::

The creation of the next partitions, the next month or the next day,
can be created simply with the ``partmgr.create_next ()``. This
function is based on the ``next_part`` column of the table
``partmgr.part_pattern`` to determine the date of the partition to
create.

Monitoring
::::::::::

``partmgr.check_next_part()`` function allows monitoring from Nagios ::

  part=$ select * from partmgr.check_next_part() ;
   nagios_return_code |              message
  --------------------+-----------------------------------
                    2 | Missing : test.test1jour_20120628
  (1 row)
  part=$ select * from partmgr.create('test','test1jour','2012-06-28','2012-06-29') ;
   o_tables | o_indexes | o_triggers | o_grants
  ----------+-----------+------------+----------
          2 |         2 |          2 |        4
  (1 row)
  part=$ select * from partmgr.check_next_part() ;
   nagios_return_code | message
  --------------------+---------
                    0 |
  (1 row)
