#!/bin/bash
# Install an Erlang/OTP release package

PKG_NAME=cse

set -e
cd ${HOME}
if [ -f "releases/RELEASES" ] ;
	OLD_VER=$(grep "{$PKG_NAME," releases/RELEASES | sed -e 's/[[:blank:]]*{'$PKG_NAME',[[:blank:]]*"//' -e 's/\([0-9.]*\).*/\1/')
fi
PKG_NEW=$(find releases -name ${PKG_NAME}-*.tar.gz 2> /dev/null | sort --version-sort | tail -1 | sed -e 's/releases\///' -e 's/\.tar\.gz//')
if [ -z "$PKG_NEW" ];
then
	echo "Release package not found."
	exit 1
fi
tar -zxf releases/$PKG_NEW.tar.gz
INSTDIR="$HOME/lib"
APPDIRS=$(sed -e 's|.*{\([a-z][a-zA-Z_0-9]*\),[[:blank:]]*\"\([0-9.]*\)\".*|{\1,\"\2\",\"'$INSTDIR'\"},|' -e '1s|^.*$|[|' -e '$s|\,$|]|' releases/$PKG_NEW.rel | tr -d "\r\n")
SASLVER=$(erl -noinput -eval 'application:load(sasl), {ok, Vsn} = application:get_key(sasl, vsn), io:fwrite("~s", [Vsn]), init:stop()')

# Compare old and new release versions
if [ -n "$OLD_VER" ] && [ "$PKG_NEW" != "$PKG_NAME-$OLD_VER" ] && [ -d "lib/$PKG_NAME-$OLD_VER" ] ;
then
	# Perform an OTP release upgrade
	OTP_NODE="${PKG_NAME}@$(echo $HOSTNAME | sed -e 's/\..*//')"
	cp releases/$PKG_NEW/sys.config releases/$PKG_NEW/sys.config.dist
	if [ -f "releases/$PKG_NAME-$OLD_VER/sys.config.dist" ] ;
	then
		set +e
		echo "Merging previous system configuration localizations (sys.config) ..."
		diff --text --unified releases/$PKG_NAME-$OLD_VER/sys.config.dist \
				releases/$PKG_NAME-$OLD_VER/sys.config \
				> releases/$PKG_NAME-$OLD_VER/sys.config.patch
		patch releases/$PKG_NEW/sys.config \
				releases/$PKG_NAME-$OLD_VER/sys.config.patch && echo "... merge done."
		if [ "$?" -ne 0 ] ;
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
	then
		# Upgrade using rpc
		RPC_SNAME=$(id -un)
		echo "Performing an in-service upgrade ..."
		if echo -e "4.2\n$SASLVER"  | sort --check=quiet --version-sort;
		then
			set -e
			erl -noshell -sname $RPC_SNAME \
					-eval "rpc:call('$OTP_NODE', application, start, [sasl])" \
					-eval "rpc:call('$OTP_NODE', systools, make_relup, [\"releases/$PKG_NEW\", [\"releases/$PKG_NAME-$OLD_VER\"], [\"releases/$PKG_NAME-$OLD_VER\"], [{path,[\"lib/$PKG_NEW/ebin\"]}, {outdir, \"releases/$PKG_NEW\"}]])" \
					-eval "{ok, _} = rpc:call('$OTP_NODE', release_handler, set_unpacked, [\"$HOME/releases/$PKG_NEW.rel\", $APPDIRS])" \
					-eval "{ok, _, _} = rpc:call('$OTP_NODE', release_handler, install_release, [\"$PKG_NEW\", [{update_paths, true}]])" \
					-eval "ok = rpc:call('$OTP_NODE', release_handler, make_permanent, [\"$PKG_NEW\"])" \
					-s init stop && echo "... done."
		else
			set -e
			erl -noshell -sname $RPC_SNAME \
					-eval "rpc:call('$OTP_NODE', application, start, [sasl])" \
					-eval "rpc:call('$OTP_NODE', systools, make_relup, [\"releases/$PKG_NEW\", [\"releases/$PKG_NAME-$OLD_VER\"], [\"releases/$PKG_NAME-$OLD_VER\"], [{path,[\"lib/$PKG_NEW/ebin\"]}, {outdir, \"releases/$PKG_NEW\"}]])" \
					-eval "{ok, _} = rpc:call('$OTP_NODE', release_handler, set_unpacked, [\"releases/$PKG_NEW.rel\", $APPDIRS])" \
					-eval "{ok, _, _} = rpc:call('$OTP_NODE', release_handler, install_release, [\"$PKG_NEW\", [{update_paths, true}]])" \
					-eval "ok = rpc:call('$OTP_NODE', release_handler, make_permanent, [\"$PKG_NEW\"])" \
					-s init stop && echo "... done."
		fi
	else
		# Start sasl and mnesia, perform upgrade, stop started applications
		echo "Performing an out-of-service upgrade ..."
		if echo -e "4.2\n$SASLVER"  | sort --check=quiet --version-sort;
		then
			set -e
			ERL_LIBS=lib RELDIR=$HOME/releases erl -noshell \
					-sname $OTP_NODE -config releases/$PKG_NAME-$OLD_VER/sys \
					-s mnesia \
					-eval "application:start(sasl)" \
					-eval "application:load($PKG_NAME)" \
					-eval "systools:make_relup(\"releases/$PKG_NEW\", [\"releases/$PKG_NAME-$OLD_VER\"], [\"releases/$PKG_NAME-$OLD_VER\"], [{path,[\"lib/$PKG_NAME-$OLD_VER/ebin\"]}, {outdir, \"releases/$PKG_NEW\"}])" \
					-eval "{ok, _} = release_handler:set_unpacked(\"$HOME/releases/$PKG_NEW.rel\", $APPDIRS)" \
					-eval "{ok, _, _} = release_handler:install_release(\"$PKG_NEW\", [{update_paths, true}])" \
					-eval "ok = release_handler:make_permanent(\"$PKG_NEW\")" \
					-s init stop && echo "... done."
		else
			set -e
			ERL_LIBS=lib RELDIR=releases erl -noshell -sname $OTP_NODE -config releases/$PKG_NAME-$OLD_VER/sys \
					-s mnesia \
					-eval "application:start(sasl)" \
					-eval "application:load($PKG_NAME)" \
					-eval "systools:make_relup(\"releases/$PKG_NEW\", [\"releases/$PKG_NAME-$OLD_VER\"], [\"releases/$PKG_NAME-$OLD_VER\"], [{path,[\"lib/$PKG_NAME-$OLD_VER/ebin\"]}, {outdir, \"releases/$PKG_NEW\"}])" \
					-eval "{ok, _} = release_handler:set_unpacked(\"releases/$PKG_NEW.rel\", $APPDIRS)" \
					-eval "{ok, _, _} = release_handler:install_release(\"$PKG_NEW\", [{update_paths, true}])" \
					-eval "ok = release_handler:make_permanent(\"$PKG_NEW\")" \
					-s init stop && echo "... done."
		fi
	fi
else
	# Install release via shell
	echo "Installing an initial release ..."
	set +e
	if echo -e "4.2\n$SASLVER"  | sort --check=quiet --version-sort;
	then
		set -e
		RELDIR=$HOME/releases erl -noshell -eval "application:start(sasl)" \
				-eval "ok = release_handler:create_RELEASES(\"$HOME/releases\", \"$HOME/releases/$PKG_NEW.rel\", $APPDIRS)" \
				-s init stop && echo "... done."
	else
		set -e
		RELDIR=releases erl -noshell -eval "application:start(sasl)" \
				-eval "ok = release_handler:create_RELEASES(code:root_dir(), \"$HOME/releases\", \"$HOME/releases/$PKG_NEW.rel\", $APPDIRS)" \
				-s init stop && echo "... done."
	fi
	if ! test -f releases/RELEASES;
	then
		exit 1
	fi
	cp releases/$PKG_NEW/sys.config releases/$PKG_NEW/sys.config.dist
fi
ERTS=$(grep "^\[{release," releases/RELEASES | sed -e 's/^\[{release,[[:blank:]]*\"//' -e 's/^[^"]*\",[[:blank:]]*\"//' -e 's/^[^"]*\",[[:blank:]]*\"//' -e 's/^\([0-9.]*\).*/\1/')
echo "$ERTS $PKG_NEW" > releases/start_erl.data
exit 0

