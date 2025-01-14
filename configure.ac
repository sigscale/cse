## configure.ac ## vim: ts=3
##
## Process this file with autoconf to produce a configure script.
##
## Boilerplate:  standard boilerplate code
##
AC_INIT([cse], [1.9.0], [issues@sigscale.org])
AC_COPYRIGHT([Copyright (c) 2021-2025 SigScale Global Inc.])
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
PKG_PROG_PKG_CONFIG
AC_ARG_WITH([systemdsystemunitdir],
		[AS_HELP_STRING([--with-systemdsystemunitdir=DIR], [Directory for systemd service files])],,
		[with_systemdsystemunitdir=auto])
AS_IF([test "x$with_systemdsystemunitdir" = "xyes" -o "x$with_systemdsystemunitdir" = "xauto"],
		[def_systemdsystemunitdir=$($PKG_CONFIG --variable=systemdsystemunitdir systemd)
		AS_IF([test "x$def_systemdsystemunitdir" = "x"],
				[AS_IF([test "x$with_systemdsystemunitdir" = "xyes"],
						[AC_MSG_ERROR([systemd support requested but pkg-config unable to query systemd package])],
						[with_systemdsystemunitdir=no])],
				[with_systemdsystemunitdir="$def_systemdsystemunitdir"])])
AS_IF([test "x$with_systemdsystemunitdir" != "xno"],
		[AC_SUBST([systemdsystemunitdir], [$with_systemdsystemunitdir])])
AM_CONDITIONAL([HAVE_SYSTEMD], [test "x$with_systemdsystemunitdir" != "xno"])


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
otpdir=$ERLANG_INSTALL_LIB_DIR/..
appdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION
docdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/doc
erldir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/src
beamdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/ebin
eincludedir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/include
schemadir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/priv/schema
emibdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/priv/mibs
mibsdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/mibs
scriptdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/priv/bin
reldir=$ERLANG_INSTALL_LIB_DIR/../releases
envdir=/etc/default
AC_SUBST(otpdir)
AC_SUBST(appdir)
AC_SUBST(erldir)
AC_SUBST(beamdir)
AC_SUBST(eincludedir)
AC_SUBST(privdir)
AC_SUBST(schemadir)
AC_SUBST(emibdir)
AC_SUBST(mibsdir)
AC_SUBST(scriptdir)
AC_SUBST(reldir)
AC_SUBST(envdir)


##
## Libraries:  check for libraries
##
AC_ERLANG_SUBST_ERTS_VER
AC_ERLANG_CHECK_LIB([kernel], [], [AC_MSG_ERROR([kernel was not found!])])
AC_ERLANG_CHECK_LIB([stdlib],
		[AS_VERSION_COMPARE([$ERLANG_LIB_VER_stdlib], ["3.5"],
				[AC_MSG_ERROR([>= stdlib-3.5 required!])])],
		[AC_MSG_ERROR([stdlib was not found!])])
AC_ERLANG_CHECK_LIB([sasl], [], [AC_MSG_ERROR([sasl was not found!])])
AM_CONDITIONAL([MAKE_TAR_EXTRA_FILES],
		[AS_VERSION_COMPARE([$ERLANG_LIB_VER_sasl], ["4.0"], [false], [true], [true])])
AC_ERLANG_CHECK_LIB([mnesia], [], [AC_MSG_ERROR([mnesia was not found!])])
AC_ERLANG_CHECK_LIB([inets], [], [AC_MSG_ERROR([inets was not found!])])
AC_ERLANG_CHECK_LIB([snmp], [], [AC_MSG_ERROR([snmp was not found!])])
AC_ERLANG_CHECK_LIB([parsetools], [], [AC_MSG_ERROR([parsetools was not found!])])
AC_ERLANG_CHECK_LIB([zj], [], [AC_MSG_ERROR([zj was not found!])])
AC_ERLANG_CHECK_LIB([sigscale_mibs], [], [AC_MSG_ERROR([sigscale_mibs was not found!])])
AC_ERLANG_CHECK_LIB([diameter], [], [])
AC_ERLANG_CHECK_LIB([radius], [], [])
AC_ERLANG_CHECK_LIB([tcap], [], [])
AC_ERLANG_CHECK_LIB([m3ua], [], [])
AC_ERLANG_CHECK_LIB([sccp], [], [])
AC_ERLANG_CHECK_LIB([cap], [], [])
AC_ERLANG_CHECK_LIB([inap], [], [])
AC_ERLANG_CHECK_LIB([map], [], [])
AC_ERLANG_CHECK_LIB([gtt], [], [])
AM_CONDITIONAL([SIGTRAN],
		[test "$ERLANG_LIB_DIR_tcap" != "not found" \
				&& test "$ERLANG_LIB_DIR_m3ua" != "not found" \
				&& test "$ERLANG_LIB_DIR_sccp" != "not found" \
				&& test "$ERLANG_LIB_DIR_cap" != "not found" \
				&& test "$ERLANG_LIB_DIR_inap" != "not found" \
				&& test "$ERLANG_LIB_DIR_map" != "not found" \
				&& test "$ERLANG_LIB_DIR_gtt" != "not found"])


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
AS_VERSION_COMPARE([$ERLANG_LIB_VER_sasl], ["4.2"],
		[RELDIR="releases"], [RELDIR="/home/otp/releases"], [RELDIR="/home/otp/releases"])
AC_SUBST([RELDIR])
AC_OUTPUT([Makefile ebin/Makefile include/Makefile doc/Makefile
		src/Makefile priv/Makefile priv/schema/Makefile
		priv/mibs/Makefile mibs/Makefile test/Makefile
		sys.config sigtran.rel $PACKAGE_NAME.rel ebin/$PACKAGE_NAME.appup
		scripts/cse scripts/cse.service])

