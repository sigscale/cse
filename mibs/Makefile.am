## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

mibs_DATA = SIGSCALE-DIAMETER-BASE-PROTOCOL-MIB.mib \
		SIGSCALE-DIAMETER-CC-APPLICATION-MIB.mib

check_DATA = .tree_ok

.tree_ok:
	@if snmptranslate -V > /dev/null 2>&1; then \
		snmptranslate -M +$(ERLANG_LIB_DIR_sigscale_mibs)/mibs:$(top_srcdir)/mibs \
			-m +SIGSCALE-DIAMETER-BASE-PROTOCOL-MIB \
			-Lo -Tp -IR diameterBaseProtocolMIB; \
		snmptranslate -M +$(ERLANG_LIB_DIR_sigscale_mibs)/mibs:$(top_srcdir)/mibs \
			-m +SIGSCALE-DIAMETER-CC-APPLICATION-MIB \
			-Lo -Tp -IR diameterCCAMIB; \
	fi

