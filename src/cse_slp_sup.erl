%%% cse_slp_sup.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
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
-module(cse_slp_sup).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(supervisor).

%% export the callback needed for supervisor behaviour
-export([init/1]).

%%----------------------------------------------------------------------
%%  The cse_slp_sup private API
%%----------------------------------------------------------------------


%%----------------------------------------------------------------------
%%  The supervisor callback
%%----------------------------------------------------------------------

init([] = _Args) ->
	ChildSpecs = [fsm(cse_slp_cap_fsm)],
	SupFlags = #{strategy => simple_one_for_one},
	{ok, {SupFlags, ChildSpecs}}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec fsm(StartMod) -> Result
	when
		StartMod :: atom(),
		Result :: supervisor:child_spec().
%% @doc Build a supervisor child specification for a
%% 	{@link //stdlib/gen_statem. gen_statem} behaviour.
%% @private
%%
fsm(StartMod) ->
	StartArgs = [StartMod],
	StartFunc = {gen_statem, start_link, StartArgs},
	#{id => StartMod, start => StartFunc,
			restart => temporary, modules => [StartMod]}.

