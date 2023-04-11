%%% cse_test_lib.erl
%%% vim: ts=3
%%%
-module(cse_test_lib).

-export([init_tables/0]).
-export([start/0, start/1, stop/0, stop/1]).
-export([load/1, unload/1]).
-export([rand_name/0, rand_name/1]).
-export([rand_dn/0, rand_dn/1]).
-export([rand_value/0]).

-define(TIMEOUT, 1000).

-ifdef(SIGTRAN).
applications() ->
	[mnesia, inets, asn1, snmp, sigscale_mibs, m3ua, tcap, gtt, diameter, cse].
-else.
applications() ->
	[mnesia, inets, asn1, snmp, sigscale_mibs, diameter, cse].
-endif.

-spec init_tables() -> Result
	when
		Result :: ok | {error, Reason :: term()}.
%% @doc Initial mnesia tables for applications.
init_tables() ->
	init_tables([m3ua, gtt, cse]).
%% @hidden
init_tables([m3ua | T]) ->
	init_tables([m3ua_asp, m3ua_as], m3ua_app, T);
init_tables([gtt | T]) ->
	init_tables([gtt_ep, gtt_as, gtt_pc], gtt_app, T);
init_tables([cse | T]) ->
	init_tables([resource, cse_service, cse_context], cse_app, T);
init_tables([]) ->
	ok.
%% @hidden
init_tables(Tables, Mod, T) ->
	case Mod:install() of
		{ok, Installed} ->
			case lists:subtract(Tables, Installed) of
				[] ->
					init_tables(T);
				Other ->
					{error, Other}
			end;
		{error, Reason} ->
			{error, Reason}
	end.

start() ->
	start(applications()).

start([H | T]) ->
	case application:start(H) of
		ok  ->
			start(T);
		{error, {already_started, H}} ->
			start(T);
		{error, Reason} ->
			{error, Reason}
	end;
start([]) ->
	ok.

stop() ->
	stop(lists:reverse(applications())).

stop([H | T]) ->
	case application:stop(H) of
		ok  ->
			stop(T);
		{error, {not_started, H}} ->
			stop(T);
		{error, Reason} ->
			{error, Reason}
	end;
stop([]) ->
	ok.

load(Application) ->
	case application:load(Application) of
		ok ->
			ok;
		{error, {already_loaded, Application}} ->
			ok = unload(Application),
			load(Application);
		{error, {running, Application}} ->
			ok = application:stop(Application),
			ok = unload(Application),
			load(Application)
	end.

unload(Application) ->
	case application:unload(Application) of
		ok ->
			ok;
		{error, {running, Application}} ->
			ok = application:stop(Application),
			unload(Application);
		{error, {not_loaded, Application}} ->
			ok
	end.

%% @doc Returns 5-3 random printable characters.
rand_name() ->
	rand_name(rand:uniform(8) + 5).

%% @doc Returns N random printable characters.
rand_name(N) ->
	UpperCase = lists:seq(65, 90),	
	LowerCase = lists:seq(97, 122),
	Digits = lists:seq(48, 57),
	Special = [$#, $%, $+, $-, $.],
	CharSet = lists:flatten([UpperCase, LowerCase, Digits, Special]),
	rand_name(N, CharSet, []).
rand_name(0, _CharSet, Acc) ->
	Acc;
rand_name(N, CharSet, Acc) ->
	Char = lists:nth(rand:uniform(length(CharSet)), CharSet),
	rand_name(N - 1, CharSet, [Char | Acc]).

%% @doc Returns ten random digits.
rand_dn() ->
	rand_dn(10).

%% @doc Returns N random digits.
rand_dn(N) ->
	rand_dn(N, []).
rand_dn(0, Acc) ->
	Acc;
rand_dn(N, Acc) ->
	rand_dn(N - 1, [47 + rand:uniform(10) | Acc]).

%% @doc Returns a random value.
rand_value() ->
	rand_value(rand:uniform(10)).
rand_value(1) ->
	true;
rand_value(2) ->
	false;
rand_value(3) ->
	rand_name();
rand_value(4) ->
	rand_dn();
rand_value(5) ->
	rand:uniform(1000);
rand_value(6) ->
	- rand:uniform(1000);
rand_value(7) ->
	rand:uniform();
rand_value(8) ->
	- rand:uniform();
rand_value(9) ->
	lists:seq(1, rand:uniform(10));
rand_value(10) ->
	F = fun F(0, Acc) ->
				Acc;
			F(N, Acc) ->
				F(N - 1, [rand_name() | Acc])
	end,
	F(rand:uniform(10), []).

