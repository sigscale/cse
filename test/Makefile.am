## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

check_DATA = .dialyzer_ok .common_test_ok

testmods = cse_api_SUITE \
		cse_gtt_SUITE \
		cse_query_parse_SUITE \
		cse_rest_api_SUITE \
		cse_log_SUITE \
		cse_log_codec_ecs_SUITE \
		cse_codec_SUITE \
		cse_test_lib \
		cse_diameter_SUITE \
		cse_radius_SUITE \
		cse_snmp_SUITE \
		cse_test_diameter_cb \
		cse_test_ocs_server \
		mod_ct_nrf \
		cse_snmpm_cb

DIA_ARGS =
CT_ARGS = -spec test.spec

if SIGTRAN
testmods += cse_inap_SUITE \
		cse_cap_SUITE

cse_test_lib.beam:$(top_srcdir)/test/cse_test_lib.erl
	$(ERLC) $(ERLCFLAGS) -DSIGTRAN -I $(top_srcdir)/include -I $(top_builddir)/include $<

DIA_ARGS += -DCAP
CT_ARGS += -pa $(top_builddir)/ebin \
         -pa $(ERLANG_LIB_DIR_m3ua)/ebin \
         -pa $(ERLANG_LIB_DIR_sccp)/ebin \
         -pa $(ERLANG_LIB_DIR_gtt)/ebin \
         -pa $(ERLANG_LIB_DIR_tcap)/ebin \
         -pa $(ERLANG_LIB_DIR_map)/ebin \
         -pa $(ERLANG_LIB_DIR_cap)/ebin \
         -pa $(ERLANG_LIB_DIR_inap)/ebin \
         -pa $(ERLANG_LIB_DIR_sigscale_mibs)/ebin \
         -pa $(ERLANG_LIB_DIR_zj)/ebin
endif

.dialyzer_ok:	$(addsuffix .beam, $(testmods))
	dialyzer $(DIA_ARGS) --src -I $(top_builddir)/include $(top_srcdir)/src

%.beam:$(top_srcdir)/test/%.erl
	$(ERLC) $(ERLCFLAGS) -I $(top_srcdir)/include -I $(top_builddir)/include $<

.common_test_ok:	$(addsuffix .beam, $(testmods))
	@if [ ! -d log ]; then mkdir log; fi
	@if [ ! -f ct.cfg ]; then cp $(top_srcdir)/test/ct.cfg .; fi
	@if [ ! -f test.spec ]; then cp $(top_srcdir)/test/test.spec .; fi
	@if [ ! -d cse_api_SUITE_data ]; then mkdir cse_api_SUITE_data; fi
	@if [ ! -d cse_rest_api_SUITE_data ]; then mkdir cse_rest_api_SUITE_data; fi
	@if [ ! -d cse_log_SUITE_data ]; then mkdir cse_log_SUITE_data; fi
	@if [ ! -d cse_cap_SUITE_data ]; then mkdir cse_cap_SUITE_data; fi
	@if [ ! -d cse_inap_SUITE_data ]; then mkdir cse_inap_SUITE_data; fi
	@if [ ! -d cse_diameter_SUITE_data ]; then mkdir cse_diameter_SUITE_data; fi
	ct_run -no_auto_compile \
			-pa $(top_builddir)/ebin \
			$(CT_ARGS) \
			-pa $(ERLANG_LIB_DIR_sigscale_mibs)/ebin \
			-pa $(ERLANG_LIB_DIR_zj)/ebin \
			-logdir log -config ct.cfg -dir . \
			-erl_args -noshell -sname $(LOGNAME)-ct

clean-local:
	-rm -r *.beam log/*

