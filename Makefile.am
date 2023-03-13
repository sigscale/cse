## Makefile.am
##
## Process this file with automake to produce Makefile.in

SUBDIRS = include src ebin doc test priv mibs

if HAVE_SYSTEMD
systemdsystemunit_DATA = scripts/cse.service
env_DATA = scripts/cse
endif

script_SCRIPTS = scripts/snapshot.escript \
		scripts/data_session.escript \
		scripts/voice_call.escript \
		scripts/send_sms.escript \
		scripts/send_mms.escript

.PHONY: release
release: $(PACKAGE_VERSION).tar.gz

if SIGTRAN
$(PACKAGE_VERSION).rel: $(PACKAGE_NAME).rel sigtran.rel
	sed -e '/{sigscale_mibs,/r sigtran.rel' $< > $@
else
$(PACKAGE_VERSION).rel: $(PACKAGE_NAME).rel
	cp $< $@
endif

ERLTMP := $(shell mktemp -d)

$(PACKAGE_VERSION).tar.gz: $(PACKAGE_VERSION).rel sys.config
	mkdir -p $(ERLTMP)/lib/$(PACKAGE_NAME)-$(PACKAGE_VERSION)
	cp -r $(DESTDIR)/$(ERLANG_INSTALL_LIB_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)/* $(ERLTMP)/lib/$(PACKAGE_NAME)-$(PACKAGE_VERSION)
	ERL_LIBS=$(ERLTMP)/lib:$(ERL_LIBS) RELDIR=releases $(ERL) -noinput -boot_var OTPHOME lib \
			-eval "systools:make_script(\"$(PACKAGE_VERSION)\", [{variables, [{\"OTPHOME\", \"$(ERLTMP)\"}]}])" \
			-eval "systools:make_tar(\"$(PACKAGE_VERSION)\", [{dirs, [include,mibs,doc]}])" \
			-s init stop
	rm -rf $(ERLTMP)

install-data-hook: $(PACKAGE_VERSION).tar.gz
	$(MKDIR_P) $(DESTDIR)/$(reldir)
	$(INSTALL_DATA) $< $(DESTDIR)/$(reldir)
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/db
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/tls
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log/http
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log/slp
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/snmp/conf
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/snmp/db

EXTRA_DIST = $(PACKAGE_VERSION).tar.gz

CLEANFILES = $(PACKAGE_VERSION).rel $(PACKAGE_VERSION).script $(PACKAGE_VERSION).boot $(PACKAGE_VERSION).tar.gz

