## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

noinst_DATA = cse_rest_query_scanner.erl \
		cse_rest_query_parser.erl \
		diameter_gen_ietf.erl \
		diameter_gen_etsi.erl \
		diameter_gen_3gpp.erl \
		diameter_gen_3gpp_ro_application.erl

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

diameter_gen_3gpp_ro_application.erl:  3gpp_ro_application.dia $(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -H $<

diameter_gen_3gpp_ro_application.hrl:  3gpp_ro_application.dia $(top_builddir)/ebin/diameter_gen_3gpp.beam
	$(DIAMETERC) -i $(top_builddir)/ebin -E $<

CLEANFILES = $(noinst_DATA)

