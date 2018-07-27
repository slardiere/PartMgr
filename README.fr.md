# Partmgr

Partmgr est un ensemble de tables et de procédures stockées écrites pour
faciliter la gestion des tables partitionnées dans les bases de données.

La clé de partitionnement est une date (Année, Mois, Semaine ou Jour),
correspondant à un attribut de la table. Il est possible de déterminer
une période de rétention.

Les tables de PartMgr sont des catalogues contenant des informations sur
les types de partitions, les tables concernées et les triggers associées à ces
tables.

Les procédures stockées permettent de gérer la création des triggers de
partitionnement et des partitions, la suppression d'anciennes partitions
et la surveillance de la présence des futures partitions.

## Tables ( catalogue )

Les tables sont dans un schéma "partition" :

  - `partmgr.part_pattern` : type de partitions
  - `partmgr.part_table` : tables partitionnées
  - `partmgr.part_trigger` : triggers des tables partitionnées

pour la version 10 de PostgreSQL :

  - `partmgr.part_index` : index des tables partitionnées
  - `partmgr.part_fkey` : clées étrangères des tables partitionnées

La table `part_pattern` contient les différents patterns de
partitionnement. Sauf lors de l'ajout de nouveaux patterns, il n'y a
pas besoin de la modifier. Les différents pattern, et donc les types
de partitions, sont : `year`, `month`, `week`, et `day`.

La table `part_table` contient la liste des tables que l'utilisateur
souhaite partitionner.  Elle doit renseignée par l'utilisateur.

La table `part_trigger` contient la liste des triggers associés aux
tables partitionnées. Elle est renseignée automatiquement lors de la
configuration d'une nouvelle table partitionnée.

## Liste des fonctions

 - `fonction partmgr.between()` : determine le nombre d'unités
      comprises entre deux dates pour un type de partition donné
 - `fonctions partmgr.create()` : créer les partitions

   - `partmgr.create()` : fonction générique, qui crée les
       partitions de toutes les tables, à la date courante.
   - `partmgr.create( date)` : crée les partitions pour toutes les
       tables à la date indiquée.
   - `partmgr.create( begin_date, end_date )` : crée les
       partitions pour toutes les tables pour la période bornée par les
       dates.
   - `partmgr.create( schema, table, begin_date, end_date )` :
       crée les partitions pour la table indiquée et pour la période
       bornée par les dates.
   - `partmgr.create( schema, table, column, period, pattern,
      begin_date, end_date )` : fonction bas niveau, appelée par les
      autres fonctions `create`, pour créer les partitions selon les
      parametres donnés.

 - `function partmgr.create_next()` : crée les prochaines
   partitions de toutes les tables. La prochaine période dépend de la
   date courante, à laquelle on ajoute l'intervalle `next_part` du
   pattern ( i.e. : current_date + 7jours pour un partitionnement
   mensuel ). Cette fonction est destinée à être appelé
   quotidiennement dans un planificateur tel que cron.
 - `function partmgr.drop()` : supprimme les partitions, si la
   configuration le permet
 - `function partmgr.detach()` : à partir de la version 10 de
   PostgreSQL, détache les partitions, si la configuration le permet
 - `function partmgr.check_next_part()` : destiné à être appelée
      par une sonde Nagios, permet de surveiller la présence des
      prochaines partitions utiles
 - `function partmgr.grant_replace( p_acl text, p_grant text, p_ext_grant text )`
 - `function partmgr.grant( acl text, tablename text )`
 - `function partmgr.setgrant( p_schemaname text, p_tablename text,
     p_part text )` : utilisé par `partmgr.create()` pour
     appliquer les privilèges lors de la création des partitions
 - `function partmgr.create_part_trigger()` : crée les fonctions
      triggers de partitionnement, et installe le trigger sur la table
      mère,
 - `function partmgr.set_trigger_def()` : Fonction trigger
      permettant de copier les triggers de la table mère sur les
      partitions. Déclenché à l'insertion dans
      `partmgr.part_table`

# Tutoriel

## Installation

Installation de PartMgr en utilisant le système d'extensions.  Il crée
le schéma, les tables et fonctions, et remplit les tables de
références :

```bash
$ make
$ make install
$ psql -Upostgres dbname
=# create schema partmgr ;
=# create extension partmgr WITH SCHEMA partmgr ;
```

Si Partmgr a déjà été installé, migrer depuis l'installation existante ::

```bash
$ make
$ make install
$ psql -Upostgres dbname
=# create schema partmgr ;
=# create extension partmgr WITH SCHEMA partmgr from unpackaged;
=# drop schema partition. cascade ;
```

## Configuration

Il y a 2 opérations necessaire. La première est l'insertion des tables
à partitionner dans `partmgr.part_table` ::

```sql
INSERT INTO partmgr.part_table ( schemaname, tablename, keycolumn, pattern, actif, cleanable, retention_period)
  values ('test', 'test1mois', 'ev_date', 'M', 't', 'f', null),
         ('test', 'test_mois', 'ev_date', 'M', 't', 't', '1 mon') ;
```

A partir de la version 10 de PostgreSQL, les partitions natives sont
gérées, et détachables :

```sql
INSERT INTO partmgr.part_table ( schemaname, tablename, keycolumn, pattern, actif, detachable, retention_period)
    values ('test', 'test1mois', 'ev_date', 'M', 't', 'f', null) ;
```

Les triggers présent sur ces tables sont enregistrés dans la table
`partmgr.part_trigger` pour être automatiquement ajouté sur les
partitions. À noter que ces triggers ne seront plus présent sur la
table mère.

Les privilèges définis sur la table mère sont automatiquement
appliqués sur les partitions.

Puis, la création et l'installation du trigger de partitionnement ::

```sql
SELECT partmgr.create_part_trigger('schema_name','table_name');
```

Cette fonction génère la fonction trigger spécifique à la table passée
en parametre.  La fonction trigger est crée dans le schéma
`partmgr` et le trigger `_partitionne` est créé sur la table.

Dans le cas de l'utilisation des partitions natives de PostgreSQL 10,
cet appel est inutile.

## Création des partitions

Ensuite, l'ensemble des partitions peuvent être crées avec les
fonctions `partmgr.create()` ::

```sql
part=$ select * from partmgr.create('2012-09-01','2012-11-01') ;
 o_tables | o_indexes | o_triggers | o_grants
----------+-----------+------------+----------
       74 |        74 |         65 |      126
(1 row)
```
```sql
part=$ select * from partmgr.create('test','test_mois','2012-11-01','2013-03-01') ;
 o_tables | o_indexes | o_triggers | o_grants
----------+-----------+------------+----------
        4 |         4 |          0 |        4
(1 row)
```

puis supprimées avec la fonction `partmgr.drop()` ::

```sql
part=$ select * from partmgr.drop() ;
 o_tables
----------
        0
(1 row)
```

Seules les partitions `cleanable` et dont la période de rétention
est passée seront supprimées.

De la même manière, il est possible de détacher les partitions natives :

```sql
part=$ select * from partmgr.detach() ;
 o_tables
----------
        0
(1 row)
```

Seules les partitions `detachable` et dont la période de rétention
est passée seront détachées.

## Planifier la création

La création des prochaines partitions, celle du mois prochain ou du
jour prochain, peut être créé simplement avec la fonction
`partmgr.create_next()` . Cette fonction s'appuie sur la colonne
`next_part` de la table `partmgr.part_pattern` pour déterminer la
date de la partition a créer.

## Monitoring

La fonction `partmgr.check_next_part()` permet la surveillance depuis Nagios :

```sql
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
```
