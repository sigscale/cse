## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

ERLCFLAGS +=  +'{group_check, false}'

emib_DATA =  SIGSCALE-DIAMETER-BASE-PROTOCOL-MIB.bin \
		SIGSCALE-DIAMETER-CC-APPLICATION-MIB.bin

%.bin:$(top_srcdir)/mibs/%.mib $(top_srcdir)/mibs/%.funcs
	$(ERLC) $(ERLCFLAGS) -I $(ERLANG_LIB_DIR_sigscale_mibs)/priv/mibs -I $(ERLANG_LIB_DIR_snmp)/priv/mib $<

CLEANFILES = $(emib_DATA)

