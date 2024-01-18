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
		scripts/send_mms.escript \
		scripts/cdr_ps.escript \
		scripts/cdr_ims.escript

RELEASE_NAME = $(PACKAGE_NAME)-$(PACKAGE_VERSION)

.PHONY: release
release: $(RELEASE_NAME).tar.gz

if SIGTRAN
$(RELEASE_NAME).rel: $(PACKAGE_NAME).rel sigtran.rel
	sed -e '/{sigscale_mibs,/r sigtran.rel' $< > $@
else
$(RELEASE_NAME).rel: $(PACKAGE_NAME).rel
	cp $< $@
endif

ERLTMP := $(shell mktemp -d)

$(RELEASE_NAME).tar.gz: $(RELEASE_NAME).rel sys.config
	mkdir -p $(ERLTMP)/lib/$(PACKAGE_NAME)-$(PACKAGE_VERSION)
	cp -r $(DESTDIR)/$(ERLANG_INSTALL_LIB_DIR)/$(PACKAGE_NAME)-$(PACKAGE_VERSION)/* $(ERLTMP)/lib/$(PACKAGE_NAME)-$(PACKAGE_VERSION)
	ERL_LIBS=$(ERLTMP)/lib:$(ERL_LIBS) RELDIR=releases $(ERL) -noinput -boot_var OTPHOME lib \
			-eval "systools:make_script(\"$(RELEASE_NAME)\", [{variables, [{\"OTPHOME\", \"$(ERLTMP)\"}]}])" \
			-eval "systools:make_tar(\"$(RELEASE_NAME)\", [{dirs, [include,mibs,doc]}])" \
			-s init stop
	rm -rf $(ERLTMP)

install-data-hook: $(RELEASE_NAME).tar.gz
	$(MKDIR_P) $(DESTDIR)/$(reldir)
	$(INSTALL_DATA) $< $(DESTDIR)/$(reldir)
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/db
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/tls
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log/http
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/log/slp
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/snmp/conf
	$(MKDIR_P) $(DESTDIR)/$(otpdir)/snmp/db

EXTRA_DIST = $(RELEASE_NAME).tar.gz

CLEANFILES = $(RELEASE_NAME).rel $(RELEASE_NAME).script $(RELEASE_NAME).boot $(RELEASE_NAME).tar.gz

