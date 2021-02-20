## Makefile.am
##
## Process this file with automake to produce Makefile.in

appdir = $(beamdir)
app_DATA = cse.app
EXTRA_DIST = cse.app

beam_DATA = cse.beam \
		cse_app.beam \
		cse_sup.beam \
		cse_server.beam \
		cse_tco_sup.beam \
		cse_slp_sup.beam \
		cse_slp_fsm.beam \
		cse_tco_server_cb.beam

%.beam:	$(top_srcdir)/src/%.erl
	$(ERLC) $(ERLCFLAGS) $<

%.app:   %.app-in
	sed -e 's/%APP_NAME%/$(PACKAGE_NAME)/' \
			-e 's/%APP_VERSION%/$(PACKAGE_VERSION)/' < $< > $@ 

CLEANFILES = $(beam_DATA) $(app_DATA)

