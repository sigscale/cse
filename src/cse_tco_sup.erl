%%% cse_tco_sup.erl
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
-module(cse_tco_sup).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(supervisor_bridge).

%% export the callback needed for supervisor_bridge behaviour
-export([init/1, terminate/2]).

-record(state,
		{sup :: pid(),
		tco :: pid()}).
-type state() :: #state{}.

%%----------------------------------------------------------------------
%%  The cse_tco_sup private API
%%----------------------------------------------------------------------


%%----------------------------------------------------------------------
%%  The supervisor_bridge callback
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: list(),
		Result :: {ok, Pid, State} | ignore | {error, Reason},
		Pid :: pid(),
		State :: term(),
		Reason :: term().
%% @see //stdlib/supervisor_bridge:init/1
%% @private
%%
init([Sup] = _Args) ->
	{ok, Name} = application:get_env(tsl_name),
	{ok, Callback} = application:get_env(tsl_callback),
	init1(Sup, Name, Callback).
%% @hidden
init1(Sup, Name, Callback)
		when is_atom(Name), Name /= undefined,
		((is_atom(Callback) and (Callback /= undefined))
		orelse (element(1, Callback) == tcap_tco_cb)) ->
	{ok, TcoArgs} = application:get_env(tsl_args),
	{ok, Options} = application:get_env(tsl_opts),
	case tcap:start_tsl({local, Name}, Callback, [Sup | TcoArgs], Options) of
		{ok, TCO} ->
			{ok, TCO, #state{sup = Sup, tco = TCO}};
		{error, Reason} ->
			{error, Reason}
	end;
init1(_Sup, _Name, _Callback) ->
	ignore.

-spec terminate(Reason, State) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state().
%% @see //stdlib/gen_server_bridge:terminate/2
%% @private
terminate(_Reason, #state{tco = TCO} = _State) ->
	tcap:stop_tsl(TCO).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

