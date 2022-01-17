## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

testmods = cse_api_SUITE \
		cse_cap_SUITE \
		cse_inap_SUITE \
		cse_codec_SUITE \
		mod_ct_nrf

check_DATA = .dialyzer_ok .common_test_ok

.dialyzer_ok:	$(addsuffix .beam, $(testmods))
	dialyzer --src $(top_srcdir)/src

%.beam:$(top_srcdir)/test/%.erl
	$(ERLC) $(ERLCFLAGS) -I $(top_srcdir)/include $<

.common_test_ok:	$(addsuffix .beam, $(testmods))
	@if [ ! -d log ]; then mkdir log; fi
	@if [ ! -f ct.cfg ]; then cp $(top_srcdir)/test/ct.cfg .; fi
	@if [ ! -f test.spec ]; then cp $(top_srcdir)/test/test.spec .; fi
	@if [ ! -d cse_cap_SUITE_data ]; then mkdir cse_cap_SUITE_data; fi
	@if [ ! -d cse_inap_SUITE_data ]; then mkdir cse_inap_SUITE_data; fi
	ct_run -no_auto_compile \
			-pa $(top_builddir)/ebin \
			-pa $(ERLANG_LIB_DIR_sccp)/ebin \
			-pa $(ERLANG_LIB_DIR_tcap)/ebin \
			-pa $(ERLANG_LIB_DIR_inap)/ebin \
			-logdir log -config ct.cfg -spec test.spec -dir . \
			-erl_args -noshell -sname $(LOGNAME)-ct

clean-local:
	-rm -r *.beam log/*

