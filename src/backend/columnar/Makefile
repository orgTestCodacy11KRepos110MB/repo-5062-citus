citus_subdir = src/backend/columnar
citus_top_builddir = ../../..
safestringlib_srcdir = $(citus_abs_top_srcdir)/vendor/safestringlib
SUBDIRS = . safeclib
SUBDIRS +=
ENSURE_SUBDIRS_EXIST := $(shell mkdir -p $(SUBDIRS))
OBJS += \
	$(patsubst $(citus_abs_srcdir)/%.c,%.o,$(foreach dir,$(SUBDIRS), $(sort $(wildcard $(citus_abs_srcdir)/$(dir)/*.c))))

MODULE_big = citus_columnar
EXTENSION = citus_columnar

columnar_sql_files = $(patsubst $(citus_abs_srcdir)/%,%,$(wildcard $(citus_abs_srcdir)/sql/*.sql))
columnar_downgrade_sql_files = $(patsubst $(citus_abs_srcdir)/%,%,$(wildcard $(citus_abs_srcdir)/sql/downgrades/*.sql))
DATA = $(columnar_sql_files) \
		$(columnar_downgrade_sql_files)

PG_CPPFLAGS += -I$(libpq_srcdir) -I$(safestringlib_srcdir)/include

include $(citus_top_builddir)/Makefile.global

.PHONY: install-all
install-all: install
