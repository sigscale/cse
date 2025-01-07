%%% cse_diameter_service_fsm_sup.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2025 SigScale Global Inc.
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
-module(cse_diameter_service_fsm_sup).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

-behaviour(supervisor).

%% export the call back needed for supervisor behaviour
-export([init/1]).

%%----------------------------------------------------------------------
%%  The supervisor callback
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: [term()],
		Result :: {ok, {SupFlags, [ChildSpec]}} | ignore,
		SupFlags :: supervisor:sup_flags(),
		ChildSpec :: supervisor:child_spec().
%% @doc Initialize the {@module} supervisor.
%% @see //stdlib/supervisor:init/1
%% @private
%%
init(Args) ->
	ChildSpecs = [fsm(cse_diameter_service_fsm, Args)],
	SupFlags = #{},
	{ok, {SupFlags, ChildSpecs}}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec fsm(StartMod, Args) -> Result
	when
		StartMod :: atom(),
		Args :: [term()],
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //stdlib/gen_statem. gen_statem} behaviour.
%% @private
%%
fsm(StartMod, Args) ->
	StartArgs = [StartMod, Args, []],
	StartFunc = {gen_statem, start_link, StartArgs},
	#{id => StartMod, start => StartFunc,
			restart => permanent, modules => [StartMod]}.
