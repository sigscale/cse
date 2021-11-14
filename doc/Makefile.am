## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

modhtml = cse.html \
		cse_app.html \
		cse_sup.html \
		cse_server.html \
		cse_tco_sup.html \
		cse_slp_sup.html \
		cse_slp_cap_fsm.html \
		cse_slp_inap_fsm.html \
		cse_tco_server_cb.html \
		cse_codec.html \
		cse_log.html

doc_DATA = overview.edoc $(modhtml) \
		modules-frame.html overview-summary.html \
		index.html stylesheet.css edoc-info \
		sigscale-logo.png supervision.png

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
	-cp -n $(top_srcdir)/doc/in-processing-model.png .
	-cp -n $(top_srcdir)/doc/in-functional-architecture.png .
	-cp -n $(top_srcdir)/doc/supervision.png .
	-cp -n $(top_srcdir)/doc/o-bcsm-camel.png .
	-cp -n $(top_srcdir)/doc/t-bcsm-camel.png .
	-cp -n $(top_srcdir)/doc/o-bcsm-inap.png .
	-cp -n $(top_srcdir)/doc/t-bcsm-inap.png .
	-cp -n $(top_srcdir)/doc/messaging.png .
	-cp -n $(top_srcdir)/doc/distribution.png .

CLEANFILES = overview.edoc edoc-info index.html \
		modules-frame.html overview-summary.html packages-frame.html \
		stylesheet.css erlang.png sigscale-logo.png \
		$(modhtml)

