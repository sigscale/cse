%%% cse_sup.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2023 SigScale Global Inc.
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
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(supervisor).

%% export the callback needed for supervisor behaviour
-export([init/1]).

-type registered_name() :: {local, Name :: atom()}
		| {global, Name :: atom()}
		| {via, ViaModule :: atom(), Name :: any()}.

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
	ChildSpecs = [server({local, cse}, cse_server, [self()], []),
			supervisor({local, cse_log_sup}, cse_log_sup, []),
			supervisor({local, cse_tco_sup_sup}, cse_tco_sup_sup, []),
			supervisor(cse_slp_sup, []),
			supervisor({local, cse_statistics_sup},
					cse_statistics_sup, []),
			supervisor({local, cse_diameter_sup}, cse_diameter_sup, []),
			supervisor({local, cse_rest_pagination_sup},
					cse_rest_pagination_sup, [])],
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

-spec supervisor(RegName, StartMod, Args) -> Result
	when
		RegName :: registered_name(),
		StartMod :: atom(),
		Args :: [term()],
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%%    {@link //stdlib/supervisor. supervisor} behaviour
%%    with registered name.
%% @private
%%
supervisor(RegName, StartMod, Args) ->
	StartArgs = [RegName, StartMod, Args],
	StartFunc = {supervisor, start_link, StartArgs},
	#{id => StartMod, start => StartFunc,
			type => supervisor, modules => [StartMod]}.

-spec server(RegName, StartMod, Args, Opts) -> Result
	when
		RegName :: registered_name(),
		StartMod :: atom(),
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
server(RegName, StartMod, Args, Opts) ->
	StartArgs = [RegName, StartMod, Args, Opts],
	StartFunc = {gen_server, start_link, StartArgs},
	#{id => StartMod, start => StartFunc, modules => [StartMod]}.

