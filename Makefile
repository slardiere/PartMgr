EXTENSION = partmgr
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")
DATA = $(filter-out $(wildcard updates/*--*.sql),$(wildcard sql/*.sql))
DOCS = $(wildcard *.rst)
PG_CONFIG = pg_config
PG91 = $(shell $(PG_CONFIG) --version | egrep " 8\.| 9\.0" > /dev/null && echo no || echo yes)

ifeq ($(PG91),yes)
all: $(EXTENSION)--$(EXTVERSION).sql

$(EXTENSION)--$(EXTVERSION).sql: sql/partition.sql sql/part_api.sql sql/part_triggers.sql
	cat $^ > $@

DATA = $(wildcard updates/*--*.sql) $(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = $(EXTENSION)--$(EXTVERSION).sql
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
