## Makefile.am ##
## Process this file with automake to produce Makefile.in

appdir = $(beamdir)
app_DATA = cse.app cse.appup
EXTRA_DIST = cse.app cse.appup

beam_DATA = cse.beam \
		cse_app.beam \
		cse_sup.beam \
		cse_log_sup.beam \
		cse_log_server_sup.beam \
		cse_log_server.beam \
		cse_log_job_sup.beam \
		cse_diameter.beam \
		cse_diameter_sup.beam \
		cse_diameter_service_fsm_sup.beam \
		cse_diameter_service_fsm.beam \
		cse_diameter_base_application_cb.beam \
		cse_diameter_3gpp_ro_application_cb.beam \
		cse_diameter_3gpp_rf_application_cb.beam \
		cse_radius_sup.beam \
		cse_radius_server_sup.beam \
		cse_radius_auth_server.beam \
		cse_radius_acct_server.beam \
		cse_server.beam \
		cse_tco_sup_sup.beam \
		cse_tco_sup.beam \
		cse_slp_sup.beam \
		cse_slp_prepaid_diameter_ps_fsm.beam \
		cse_slp_prepaid_diameter_ims_fsm.beam \
		cse_slp_prepaid_diameter_sms_fsm.beam \
		cse_slp_prepaid_diameter_mms_fsm.beam \
		cse_slp_postpaid_diameter_ps_fsm.beam \
		cse_slp_postpaid_diameter_ims_fsm.beam \
		cse_slp_postpaid_diameter_sms_fsm.beam \
		cse_slp_postpaid_diameter_mms_fsm.beam \
		cse_slp_prepaid_radius_ps_fsm.beam \
		cse_statistics_server.beam \
		cse_statistics_sup.beam \
		cse_codec.beam \
		cse_log.beam \
		cse_log_codec_ecs.beam \
		cse_log_codec_bx.beam \
		cse_gtt.beam \
		cse_rest.beam \
		mod_cse_rest_accepted_content.beam \
		mod_cse_rest_get.beam \
		mod_cse_rest_head.beam \
		mod_cse_rest_post.beam \
		mod_cse_rest_delete.beam \
		mod_cse_rest_patch.beam \
		cse_rest_res_health.beam \
		cse_rest_res_resource.beam \
		cse_rest_pagination_server.beam \
		cse_rest_pagination_sup.beam \
		cse_rest_query_scanner.beam \
		cse_rest_query_parser.beam \
		diameter_gen_ietf.beam \
		diameter_gen_etsi.beam \
		diameter_gen_3gpp.beam \
		diameter_gen_3gpp_ro_application.beam \
		diameter_gen_3gpp_rf_application.beam \
		diameter_gen_3gpp_sy_application.beam \
		cse_mib.beam \
		user_default.beam

if SIGTRAN
beam_DATA += cse_tco_server_cb.beam \
		cse_slp_cap_fsm.beam \
		cse_slp_inap_fsm.beam \
		cse_slp_prepaid_cap_fsm.beam \
		cse_slp_prepaid_inap_fsm.beam

cse_codec.beam:$(top_builddir)/src/cse_codec.erl $(top_srcdir)/include/cse_codec.hrl
	$(ERLC) $(ERLCFLAGS) -DCAP -I $(top_srcdir)/include -I $(top_builddir)/include $<
endif

%.beam:	$(top_srcdir)/src/%.erl $(top_srcdir)/include/cse.hrl $(top_srcdir)/include/cse_codec.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_srcdir)/include -I $(top_builddir)/include $<

cse_rest_query_scanner.beam:$(top_builddir)/src/cse_rest_query_scanner.erl
	$(ERLC) $<

cse_rest_query_parser.beam:$(top_builddir)/src/cse_rest_query_parser.erl
	$(ERLC) $<

diameter_gen_ietf.beam:$(top_builddir)/src/diameter_gen_ietf.erl \
		$(top_builddir)/include/diameter_gen_ietf.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_etsi.beam:$(top_builddir)/src/diameter_gen_etsi.erl \
		$(top_builddir)/include/diameter_gen_etsi.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp.beam:$(top_builddir)/src/diameter_gen_3gpp.erl \
		$(top_builddir)/include/diameter_gen_etsi.hrl \
		$(top_builddir)/include/diameter_gen_3gpp.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_ro_application.beam:$(top_builddir)/src/diameter_gen_3gpp_ro_application.erl \
		$(top_builddir)/include/diameter_gen_ietf.hrl \
		$(top_builddir)/include/diameter_gen_etsi.hrl \
		$(top_builddir)/include/diameter_gen_3gpp.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_rf_application.beam:$(top_builddir)/src/diameter_gen_3gpp_rf_application.erl \
		$(top_builddir)/include/diameter_gen_ietf.hrl \
		$(top_builddir)/include/diameter_gen_etsi.hrl \
		$(top_builddir)/include/diameter_gen_3gpp.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

diameter_gen_3gpp_sy_application.beam:$(top_builddir)/src/diameter_gen_3gpp_sy_application.erl \
		$(top_builddir)/include/diameter_gen_ietf.hrl \
		$(top_builddir)/include/diameter_gen_3gpp.hrl
	$(ERLC) $(ERLCFLAGS) -I $(top_builddir)/include $<

if SIGTRAN
%.app:   %.app-in
	sed -e 's/%APP_NAME%/$(PACKAGE_NAME)/' \
			-e 's/%APP_VERSION%/$(PACKAGE_VERSION)/' < $< > $@
else
%.app:   %.app-in
	sed -e 's/%APP_NAME%/$(PACKAGE_NAME)/' \
			-e 's/%APP_VERSION%/$(PACKAGE_VERSION)/' \
			-e '/^[[:blank:]]*cse_slp_cap_fsm,/d' \
			-e '/^[[:blank:]]*cse_slp_inap_fsm,/d' \
			-e '/^[[:blank:]]*cse_slp_prepaid_cap_fsm,/d' \
			-e '/^[[:blank:]]*cse_slp_prepaid_inap_fsm,/d' \
			-e '/^[[:blank:]]*cse_tco_server_cb,/d' < $< > $@
endif


CLEANFILES = $(beam_DATA) $(app_DATA)

