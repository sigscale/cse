#!/bin/bash
# Install an Erlang/OTP release package

PKG_NAME=cse

set -e
cd ${HOME}
PKG_NEW=`find releases -name ${PKG_NAME}-*.tar.gz | sort --version-sort | tail -1 | sed -e 's/releases\///' -e 's/.tar.gz//'`
tar -zxf releases/$PKG_NEW.tar.gz
INSTDIR="$HOME/lib"
APPDIRS=`sed -e 's|.*{\([a-z][a-z_0-9]*\), *\"\([0-9.]*\)\".*|{\1,\"\2\",\"'$INSTDIR'\"},|' -e '1s|^.*$|[|' -e '$s|\,$|]|' releases/$PKG_NEW.rel | tr -d "\r\n"`

# Compare old and new release versions
if [ -n "$OLD_VER" ] && [ "$PKG_NEW" != "$PKG_NAME-$OLD_VER" ] && [ -d lib/$PKG_NAME-$OLD_VER ] ;
then
	# Perform an OTP release upgrade
	OTP_NODE="${PKG_NAME}@`echo $HOSTNAME | sed -e 's/\..*//'`"
	cp releases/$PKG_NEW/sys.config releases/$PKG_NEW/sys.config.dist
	if [ -f releases/$PKG_NAME-$OLD_VER/sys.config.dist ] ;
	then
		set +e
		echo "Merging previous system configuration localizations (sys.config) ..."
		diff --text --unified releases/$PKG_NAME-$OLD_VER/sys.config.dist \
				releases/$PKG_NAME-$OLD_VER/sys.config \
				> releases/$PKG_NAME-$OLD_VER/sys.config.patch
		patch releases/$PKG_NEW/sys.config \
				releases/$PKG_NAME-$OLD_VER/sys.config.patch && echo "... merge done."
		if [ $? -ne 0 ] ;
		then
			echo "... merge failed."
			echo "Using previous system configuration without any newly distributed changes."
			sed -e "s/$PKG_NAME-$OLD_VER/$PKG_NEW/" \
					releases/$PKG_NAME-$OLD_VER/sys.config > releases/$PKG_NEW/sys.config
		fi
		set -e
	else
		echo "Using previous system configuration localizations (sys.config) without any newly distributed changes."
		sed -e "s/$PKG_NAME-$OLD_VER/$PKG_NEW/" \
				releases/$PKG_NAME-$OLD_VER/sys.config > releases/$PKG_NEW/sys.config
	fi
	set +e
	if epmd -names 2> /dev/null | grep -q '^name cse at';
	set -e
	then
		# Upgrade using rpc
		RPC_SNAME=`id -un`
		echo "Performing an in-service upgrade ..."
		erl -noshell -sname $RPC_SNAME \
				-eval "rpc:call('$OTP_NODE', application, start, [sasl])" \
				-eval "rpc:call('$OTP_NODE', systools, make_relup, [\"releases/$PKG_NEW\", [\"releases/$PKG_NAME-$OLD_VER\"], [\"releases/$PKG_NAME-$OLD_VER\"], [{path,[\"lib/$PKG_NEW/ebin\"]}, {outdir, \"releases/$PKG_NEW\"}]])" \
				-eval "rpc:call('$OTP_NODE', release_handler, set_unpacked, [\"releases/$PKG_NEW.rel\", $APPDIRS])" \
				-eval "rpc:call('$OTP_NODE', release_handler, install_release, [\"$PKG_NEW\", [{update_paths, true}]])" \
				-eval "rpc:call('$OTP_NODE', release_handler, make_permanent, [\"$PKG_NEW\"])" \
				-s init stop && echo "... done."
	else
		# Start sasl and mnesia, perform upgrade, stop started applications
		echo "Performing an out-of-service upgrade ..."
		ERL_LIBS=lib RELDIR=releases erl -noshell -sname $OTP_NODE -config releases/$PKG_NAME-$OLD_VER/sys \
				-s mnesia \
				-eval "application:start(sasl)" \
				-eval "application:load($PKG_NAME)" \
				-eval "systools:make_relup(\"releases/$PKG_NEW\", [\"releases/$PKG_NAME-$OLD_VER\"], [\"releases/$PKG_NAME-$OLD_VER\"], [{path,[\"lib/$PKG_NAME-$OLD_VER/ebin\"]}, {outdir, \"releases/$PKG_NEW\"}])" \
				-eval "release_handler:set_unpacked(\"releases/$PKG_NEW.rel\", $APPDIRS)" \
				-eval "release_handler:install_release(\"$PKG_NEW\", [{update_paths, true}])" \
				-eval "release_handler:make_permanent(\"$PKG_NEW\")" \
				-s init stop && echo "... done."
	fi
else
	# Install release via shell
	echo "Installing an initial release ..."
	RELDIR=releases erl -noshell -eval "application:start(sasl)" \
			-eval "release_handler:create_RELEASES(\"$HOMEDIR/releases\", \"$HOMEDIR/releases/$PKG_NEW.rel\", $APPDIRS)" \
			-s init stop && echo "... done."
	if ! test -f releases/RELEASES;
	then
		exit 1
	fi
	cp releases/$PKG_NEW/sys.config releases/$PKG_NEW/sys.config.dist
fi
ERTS=`grep "^\[{release," releases/RELEASES | cut -d, -f4 | tr -d \"`
echo "$ERTS $PKG_NEW" > releases/start_erl.data
exit 0

