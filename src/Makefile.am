## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

noinst_DATA = cse_rest_query_scanner.erl \
		cse_rest_query_parser.erl \
		diameter_gen_ietf.erl \
		diameter_gen_etsi.erl \
		diameter_gen_3gpp.erl \
		diameter_gen_cc_application_rfc4006.erl \
		diameter_gen_nas_application_rfc7155.erl \
		diameter_gen_3gpp_ro_application.erl \
		diameter_gen_3gpp_rf_application.erl

%.erl:%.xrl
	$(ERLC) $<

%.erl:%.yrl
	$(ERLC) $<

DIAMETERC=$(ERLANG_LIB_DIR_diameter)/bin/diameterc

diameter_gen_ietf.erl:	ietf.dia
	$(DIAMETERC) -H $<

diameter_gen_ietf.hrl:	ietf.dia
	$(DIAMETERC) -E $<

diameter_gen_etsi.erl:	etsi.dia
	$(DIAMETERC) -H $<

diameter_gen_etsi.hrl:	etsi.dia
	$(DIAMETERC) -E $<

diameter_gen_3gpp.erl:	3gpp.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H $<

diameter_gen_3gpp.hrl:	3gpp.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_cc_application_rfc4006.erl:	cc_application_rfc4006.dia \
		$(top_builddir)/ebin/diameter_gen_nas_application_rfc7155.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H $<

diameter_gen_cc_application_rfc4006.hrl:	cc_application_rfc4006.dia \
		$(top_builddir)/ebin/diameter_gen_nas_application_rfc7155.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_nas_application_rfc7155.erl:	nas_application_rfc7155.dia
	$(DIAMETERC) -H $<

diameter_gen_nas_application_rfc7155.hrl:	nas_application_rfc7155.dia
	$(DIAMETERC) -E $<

diameter_gen_3gpp_ro_application.erl:	3gpp_ro_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H $<

diamter_gen_3gpp_ro_application.hrl:	3gpp_ro_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

diameter_gen_3gpp_rf_application.erl:	3gpp_rf_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H $<

diamter_gen_3gpp_rf_application.hrl:	3gpp_rf_application.dia \
		$(top_builddir)/ebin/diameter_gen_ietf.beam \
		$(top_builddir)/ebin/diameter_gen_etsi.beam \
		$(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

CLEANFILES = $(noinst_DATA)

