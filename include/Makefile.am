## Makefile.am
##
## Process this file with automake to produce Makefile.in

einclude_DATA = cse.hrl \
		cse_codec.hrl \
		diameter_gen_ietf.hrl \
		diameter_gen_etsi.hrl \
		diameter_gen_3gpp.hrl \
		diameter_gen_cc_application_rfc4006.hrl \
		diameter_gen_nas_application_rfc7155.hrl \
		diameter_gen_3gpp_ro_application.hrl \
		diameter_gen_3gpp_rf_application.hrl

DIAMETERC=$(ERLANG_LIB_DIR_diameter)/bin/diameterc

$(top_builddir)/ebin/%.beam:	$(top_builddir)/src/%.erl
	$(ERLC) $(ERLCFLAGS) -o $(top_builddir)/ebin $<

$(top_builddir)/src/diameter_gen_ietf.erl:	$(top_srcdir)/src/ietf.dia
	$(DIAMETERC) -H -o $(top_builddir)/src $<

$(top_builddir)/src/diameter_gen_etsi.erl:	$(top_srcdir)/src/etsi.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H -o $(top_builddir)/src $<

$(top_builddir)/src/diameter_gen_3gpp.erl:	$(top_srcdir)/src/3gpp.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H -o $(top_builddir)/src $<

$(top_builddir)/src/diameter_gen_cc_application_rfc4006.erl:	$(top_srcdir)/src/cc_application_rfc4006.dia \
		$(top_builddir)/ebin/nas_application_rfc7155.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H -o $(top_builddir)/src $<

$(top_builddir)/src/diameter_gen_nas_application_rfc7155.erl:	$(top_srcdir)/src/nas_application_rfc7155.dia
	$(DIAMETERC) -H -o $(top_builddir)/src $<

$(top_builddir)/src/diameter_gen_3gpp_ro_application.erl:	$(top_srcdir)/src/3gpp_ro_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam \
	$(DIAMETERC) -i $(top_builddir)/ebin -H -o $(top_builddir)/src $<

$(top_builddir)/src/diameter_gen_3gpp_rf_application.erl:	$(top_srcdir)/src/3gpp_rf_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam \
	$(DIAMETERC) -i $(top_builddir)/ebin -H -o $(top_builddir)/src $<

diameter_gen_ietf.hrl:	$(top_srcdir)/src/ietf.dia
	$(DIAMETERC) -E $<

diameter_gen_etsi.hrl:	$(top_srcdir)/src/etsi.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_3gpp.hrl:	$(top_srcdir)/src/3gpp.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_cc_application_rfc4006.hrl:	$(top_srcdir)/src/cc_application_rfc4006.dia \
		$(top_builddir)/ebin/diameter_gen_nas_application_rfc7155.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_nas_application_rfc7155.hrl:	$(top_srcdir)/src/nas_application_rfc7155.dia
	$(DIAMETERC) -E $<

diameter_gen_3gpp_ro_application.hrl:	$(top_srcdir)/src/3gpp_ro_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_3gpp_rf_application.hrl:	$(top_srcdir)/src/3gpp_rf_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

CLEANFILES = diameter_gen_ietf.hrl \
		diameter_gen_etsi.hrl \
		diameter_gen_3gpp.hrl \
		diameter_gen_cc_application_rfc4006.hrl \
		diameter_gen_nas_application_rfc7155.hrl \
		diameter_gen_3gpp_rf_application.hrl \
		diameter_gen_3gpp_ro_application.hrl

