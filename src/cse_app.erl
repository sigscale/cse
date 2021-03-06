%%% cse_app.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This {@link //stdlib/application. application} behaviour callback
%%%   module starts and stops the {@link //cse. cse} application.
%%%
-module(cse_app).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(application).

%% callbacks needed for application behaviour
-export([start/2, stop/1, config_change/3]).
%% optional callbacks for application behaviour
-export([prep_stop/1, start_phase/3]).

-record(state, {}).

%%----------------------------------------------------------------------
%%  The cse_app aplication callbacks
%%----------------------------------------------------------------------

-type start_type() :: normal | {takeover, node()} | {failover, node()}.
-spec start(StartType, StartArgs) -> Result
	when
		StartType :: start_type(),
		StartArgs :: term(),
		Result :: {ok, pid()} | {ok, pid(), State} | {error, Reason},
		State :: #state{},
		Reason :: term().
%% @doc Starts the application processes.
start(normal = _StartType, _Args) ->
	case inets:services_info() of
		ServicesInfo when is_list(ServicesInfo) ->
			{ok, Profile} = application:get_env(nrf_profile),
			start1(Profile, ServicesInfo);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start1(Profile, [{httpc, _Pid, Info} | T]) ->
	case proplists:lookup(profile, Info) of
		{profile, Profile} ->
			start2(Profile);
		_ ->
			start1(Profile, T)
	end;
start1(Profile, [_ | T]) ->
	start1(Profile, T);
start1(Profile, []) ->
	case inets:start(httpc, [{profile, Profile}]) of
		{ok, _Pid} ->
			start2(Profile);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start2(Profile) ->
	{ok, Options} = application:get_env(nrf_options),
	case httpc:set_options(Options, Profile) of
		ok ->
			start3();
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start3() ->
	Options = [set, public, named_table, {write_concurrency, true}],
	ets:new(counters, Options),
	ets:insert(counters, {nrf_seq, 0}),
	supervisor:start_link({local, cse_sup}, cse_sup, []).

-spec start_phase(Phase, StartType, PhaseArgs) -> Result
	when
		Phase :: atom(),
		StartType :: start_type(),
		PhaseArgs :: term(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Called for each start phase in the application and included
%%   applications.
%% @see //kernel/app
%%
start_phase(_Phase, _StartType, _PhaseArgs) ->
	ok.

-spec prep_stop(State) -> #state{}
	when
		State :: #state{}.
%% @doc Called when the application is about to be shut down,
%%   before any processes are terminated.
%% @see //kernel/application:stop/1
%%
prep_stop(State) ->
	State.

-spec stop(State) -> any()
	when
		State :: #state{}.
%% @doc Called after the application has stopped to clean up.
%%
stop(_State) ->
	ok.

-spec config_change(Changed, New, Removed) -> ok
	when
		Changed:: [{Par, Val}],
		New :: [{Par, Val}],
		Removed :: [Par],
		Par :: atom(),
		Val :: atom().
%% @doc Called after a code  replacement, if there are any
%%   changes to the configuration  parameters.
%%
config_change(_Changed, _New, _Removed) ->
	ok.

%%----------------------------------------------------------------------
%%  Internal functions
%%----------------------------------------------------------------------

