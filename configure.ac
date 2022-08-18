## configure.ac ## vim: ts=3
##
## Process this file with autoconf to produce a configure script.
##
## Boilerplate:  standard boilerplate code
##
AC_INIT([cse], [1.2.9], [issues@sigscale.org])
AC_COPYRIGHT([Copyright (c) 2021-2022 SigScale Global Inc.])
AC_PREREQ(2.64)
AC_CONFIG_SRCDIR([src/cse_app.erl])
AC_CONFIG_HEADERS([config.h])
AC_LANG([Erlang])
AM_INIT_AUTOMAKE([-Wno-portability])

##
## Options:  control options to configure, support code for the options
##
AC_ARG_ENABLE([debug],
		[AS_HELP_STRING([--enable-debug], [enable debugging (default is no)])])


##
## Programs:  check for programs needed by the configure process,
##            the build process, or by one of the programs being built
##
AC_ERLANG_NEED_ERL
AC_ERLANG_NEED_ERLC
if test -z "${ERLCFLAGS}" ; then
	ERLCFLAGS="-W -v"
fi
if test "x$enable_debug" == xyes ; then
	ERLCFLAGS="$ERLCFLAGS +debug_info"
fi
AC_ERLANG_SUBST_LIB_DIR
if test -z "${ERLANG_INSTALL_LIB_DIR}" ; then
	ERLANG_INSTALL_LIB_DIR=$ERLANG_LIB_DIR
fi
AC_ERLANG_SUBST_ROOT_DIR
AC_PROG_MKDIR_P
AC_PROG_INSTALL
AC_PROG_LN_S
AC_ERLANG_SUBST_INSTALL_LIB_DIR
appdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION
docdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/doc
erldir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/src
beamdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/ebin
eincludedir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/include
reldir=$ERLANG_INSTALL_LIB_DIR/../releases
schemadir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/priv/schema
emibdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/priv/mibs
mibsdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/mibs
AC_SUBST(appdir)
AC_SUBST(erldir)
AC_SUBST(beamdir)
AC_SUBST(eincludedir)
AC_SUBST(reldir)
AC_SUBST(privdir)
AC_SUBST(schemadir)
AC_SUBST(emibdir)
AC_SUBST(mibsdir)


##
## Libraries:  check for libraries
##
AC_ERLANG_SUBST_ERTS_VER
AC_ERLANG_CHECK_LIB([kernel], [], [AC_MSG_ERROR([kernel was not found!])])
AC_ERLANG_CHECK_LIB([stdlib],
		[AS_VERSION_COMPARE([$ERLANG_LIB_VER_stdlib], ["3.5"],
				[AC_MSG_ERROR([>= stdlib-3.5 required!])])],
		[AC_MSG_ERROR([stdlib was not found!])])
AC_ERLANG_CHECK_LIB([sasl], [], [AC_MSG_WARN([sasl was not found!])])
AC_ERLANG_CHECK_LIB([mnesia], [], [AC_MSG_WARN([mnesia was not found!])])
AC_ERLANG_CHECK_LIB([inets], [], [AC_MSG_WARN([inets was not found!])])
AC_ERLANG_CHECK_LIB([snmp], [], [AC_MSG_WARN([snmp was not found!])])
AC_ERLANG_CHECK_LIB([diameter], [], [AC_MSG_WARN([diameter was not found!])])
AC_ERLANG_CHECK_LIB([sigscale_mibs], [], [AC_MSG_WARN([sigscale_mibs was not found!])])
AC_ERLANG_CHECK_LIB([m3ua], [], [AC_MSG_ERROR([m3ua was not found!])])
AC_ERLANG_CHECK_LIB([sccp], [], [AC_MSG_ERROR([sccp was not found!])])
AC_ERLANG_CHECK_LIB([gtt], [], [AC_MSG_ERROR([gtt was not found!])])
AC_ERLANG_CHECK_LIB([tcap], [], [AC_MSG_ERROR([tcap was not found!])])
AC_ERLANG_CHECK_LIB([map], [], [AC_MSG_ERROR([map was not found!])])
AC_ERLANG_CHECK_LIB([inap], [], [AC_MSG_ERROR([inap was not found!])])
AC_ERLANG_CHECK_LIB([cap], [], [AC_MSG_ERROR([cap was not found!])])
AC_ERLANG_CHECK_LIB([zj], [], [AC_MSG_ERROR([zj was not found!])])


##
## Headers:  check for header files
##


##
## Typedefs & Structures:  check for typedefs, structures,
##                         and compiler characteristics.
##


##
## Functions:  check for library functions
##


##
## Output:  create output files
##

AC_OUTPUT([Makefile ebin/Makefile include/Makefile doc/Makefile src/Makefile
		priv/Makefile priv/schema/Makefile
		priv/mibs/Makefile mibs/Makefile
		test/Makefile $PACKAGE_NAME.rel sys.config])

