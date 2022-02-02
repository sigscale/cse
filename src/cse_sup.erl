%%% cse_sup.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
%%% @author Vance Shipley <vances@sigscale.org> [http://www.sigscale.org]
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
%%% @docfile "{@docsrc supervision.edoc}"
%%%
-module(cse_sup).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(supervisor).

%% export the callback needed for supervisor behaviour
-export([init/1]).

%%----------------------------------------------------------------------
%%  The cse_sup private API
%%----------------------------------------------------------------------


%%----------------------------------------------------------------------
%%  The supervisor callback
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: [],
		Result :: {ok, {SupFlags, [ChildSpec]}} | ignore,
		SupFlags :: supervisor:sup_flags(),
		ChildSpec :: supervisor:child_spec().
%% @doc Initialize the {@module} supervisor.
%% @see //stdlib/supervisor:init/1
%% @private
%%
init(_Args) ->
	ChildSpecs = [server(cse_server, {local, cse}, [], []),
			bridge(cse_tco_sup, [self()]),
			supervisor(cse_slp_sup, []),
			supervisor(cse_diameter_sup, []),
			supervisor(cse_rest_pagination_sup, cse_rest_pagination_sup, [])],
	SupFlags = #{},
	{ok, {SupFlags, ChildSpecs}}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec supervisor(StartMod, Args) -> Result
	when
		StartMod :: atom(),
		Args :: [term()],
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //stdlib/supervisor. supervisor} behaviour.
%% @private
%%
supervisor(StartMod, Args) ->
	StartArgs = [StartMod, Args],
	StartFunc = {supervisor, start_link, StartArgs},
	#{id => StartMod, start => StartFunc,
			type => supervisor, modules => [StartMod]}.

-spec supervisor(StartMod, RegName, Args) -> Result
	when
		StartMod :: atom(),
		RegName :: atom(),
		Args :: [term()],
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%%    {@link //stdlib/supervisor. supervisor} behaviour
%%    with registered name.
%% @private
%%
supervisor(StartMod, RegName, Args) ->
	StartArgs = [{local, RegName}, StartMod, Args],
	StartFunc = {supervisor, start_link, StartArgs},
	{StartMod, StartFunc, permanent, infinity, supervisor, [StartMod]}.

-spec bridge(StartMod, Args) -> Result
	when
		StartMod :: atom(),
		Args :: [term()],
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //stdlib/supervisor_bridge. supervisor_bridge} behaviour.
%% @private
%%
bridge(StartMod, Args) ->
	StartArgs = [StartMod, Args],
	StartFunc = {supervisor_bridge, start_link, StartArgs},
	#{id => StartMod, start => StartFunc,
			type => supervisor, modules => [StartMod]}.

-spec server(StartMod, Name, Args, Opts) -> Result
	when
		StartMod :: atom(),
		Name :: {local, LocalName} | {global, GlobalName}
				| {via, ViaModule, ViaName},
		LocalName :: atom(),
		GlobalName :: term(),
		ViaModule :: atom(),
		ViaName :: term(),
		Args :: [term()],
		Opts :: [Option],
		Option :: {timeout, Timeout} | {debug, [Flag]},
		Timeout :: pos_integer(),
		Flag :: trace | log | {logfile, file:filename()}
				| statistics | debug,
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link gen_server. gen_server} behaviour
%% 	with a registered name and options.
%% @private
%%
server(StartMod, Name, Args, Opts) ->
	StartArgs = [Name, StartMod, Args, Opts],
	StartFunc = {gen_server, start_link, StartArgs},
	#{id => StartMod, start => StartFunc, modules => [StartMod]}.

