%%% cse_test_lib.erl
%%% vim: ts=3
%%%
-module(cse_test_lib).

-export([init_tables/0]).
-export([start/0, start/1, stop/0, stop/1]).
-export([load/1, unload/1]).

-define(Applications, [mnesia, inets, asn1, snmp, sigscale_mibs, m3ua, tcap, gtt, cse]).
-define(TIMEOUT, 1000).

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
	init_tables([resource, service], cse_app, T);
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
	start(?Applications).

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
	stop(lists:reverse(?Applications)).

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

