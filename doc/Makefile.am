## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

modhtml = cse.html \
		cse_app.html \
		cse_sup.html \
		cse_log_sup.html \
		cse_diameter_sup.html \
		cse_log_server_sup.html \
		cse_log_server.html \
		cse_log_job_sup.html \
		cse_diameter_service_fsm_sup.html \
		cse_diameter_service_fsm.html \
		cse_diameter_base_application_cb.html \
		cse_diameter_3gpp_ro_application_cb.html \
		cse_diameter_3gpp_rf_application_cb.html \
		cse_server.html \
		cse_tco_sup.html \
		cse_slp_sup.html \
		cse_slp_cap_fsm.html \
		cse_slp_inap_fsm.html \
		cse_slp_prepaid_cap_fsm.html \
		cse_slp_prepaid_inap_fsm.html \
		cse_slp_prepaid_diameter_ps_fsm.html \
		cse_slp_prepaid_diameter_ims_fsm.html \
		cse_slp_prepaid_diameter_sms_fsm.html \
		cse_slp_prepaid_diameter_mms_fsm.html \
		cse_slp_postpaid_diameter_ps_fsm.html \
		cse_slp_postpaid_diameter_ims_fsm.html \
		cse_slp_postpaid_diameter_sms_fsm.html \
		cse_slp_postpaid_diameter_mms_fsm.html \
		cse_tco_server_cb.html \
		cse_codec.html \
		cse_log.html \
		cse_log_codec_ecs.html \
		cse_log_codec_bx.html \
		cse_gtt.html \
		cse_rest.html \
		cse_mib.html \
		mod_cse_rest_accepted_content.html \
		mod_cse_rest_get.html \
		mod_cse_rest_post.html \
		mod_cse_rest_delete.html \
		mod_cse_rest_patch.html \
		cse_rest_res_health.html \
		cse_rest_res_resource.html \
		cse_rest_pagination_server.html \
		cse_rest_pagination_sup.html \
		cse_rest_query_scanner.html \
		cse_rest_query_parser.html \
		diameter_gen_ietf.html \
		diameter_gen_etsi.html \
		diameter_gen_3gpp.html \
		diameter_gen_3gpp_ro_application.html \
		diameter_gen_3gpp_rf_application.html \
		diameter_gen_cc_application_rfc4006.html \
		diameter_gen_nas_application_rfc7155.html

doc_DATA = overview.edoc $(modhtml) \
		modules-frame.html overview-summary.html \
		index.html stylesheet.css edoc-info \
		sigscale-logo.png \
		oas-logo.svg \
		swaggerhub-logo.svg \
		supervision.svg \
		in-processing-model.svg \
		in-functional-architecture.svg \
		o-bcsm-camel.svg \
		t-bcsm-camel.svg \
		o-bcsm-inap.svg \
		t-bcsm-inap.svg \
		messaging.svg \
		distribution.svg \
		ocf-ocs.svg \
		ocf-nrf-msc.svg \
		ocf-nrf-iec-msc.svg \
		ctf-cdf-msc.svg \
		prepaid-diameter-data.svg \
		prepaid-diameter-voice.svg \
		prepaid-diameter-event.svg \
		postpaid-cdf.svg

overview.edoc: overview.edoc-in
	sed -e 's!%VERSION%!$(VERSION)!' \
			-e 's!%DESCRIPTION%!$(PACKAGE)!' < $< > $@

%.html:$(top_srcdir)/src/%.erl	overview.edoc $(top_srcdir)/doc/supervision.edoc
	$(ERL) -noshell -run edoc_run application \
			"'$(PACKAGE_NAME)'" "'$(top_builddir)'" \
			'[{sort_functions,false},{private,true},{todo,true},{source_path,["$(top_srcdir)/src"]},{subpackages,false},{def,{docsrc,"$(top_srcdir)/doc/{@?}"}},{stylesheet_file, "$(top_srcdir)/doc/sigscale.css"}]'
	for i in `ls *.html`; do \
			sed -e 's!erlang logo!sigscale logo!' \
					-e 's!href=\"http://www.erlang.org/\"!href=\"http://www.sigscale.org/\"!' \
					-e 's!erlang.png!sigscale-logo.png!' $$i > $$i.tmp; \
			mv $$i.tmp $$i; \
	done
	-cp -n $(top_srcdir)/doc/sigscale-logo.png .
	-cp -n $(top_srcdir)/doc/oas-logo.svg .
	-cp -n $(top_srcdir)/doc/swaggerhub-logo.svg .
	-cp -n $(top_srcdir)/doc/in-processing-model.svg .
	-cp -n $(top_srcdir)/doc/in-functional-architecture.svg .
	-cp -n $(top_srcdir)/doc/supervision.svg .
	-cp -n $(top_srcdir)/doc/o-bcsm-camel.svg .
	-cp -n $(top_srcdir)/doc/t-bcsm-camel.svg .
	-cp -n $(top_srcdir)/doc/o-bcsm-inap.svg .
	-cp -n $(top_srcdir)/doc/t-bcsm-inap.svg .
	-cp -n $(top_srcdir)/doc/messaging.svg .
	-cp -n $(top_srcdir)/doc/distribution.svg .
	-cp -n $(top_srcdir)/doc/ocf-ocs.svg .
	-cp -n $(top_srcdir)/doc/ocf-nrf-msc.svg .
	-cp -n $(top_srcdir)/doc/ocf-nrf-iec-msc.svg .
	-cp -n $(top_srcdir)/doc/ctf-cdf-msc.svg .
	-cp -n $(top_srcdir)/doc/prepaid-diameter-data.svg .
	-cp -n $(top_srcdir)/doc/prepaid-diameter-voice.svg .
	-cp -n $(top_srcdir)/doc/prepaid-diameter-event.svg .
	-cp -n $(top_srcdir)/doc/postpaid-cdf.svg .

CLEANFILES = $(doc_DATA) $(modhtml) erlang.png

