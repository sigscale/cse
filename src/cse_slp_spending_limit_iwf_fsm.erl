%%% cse_slp_spending_limit_iwf_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2026 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements {@link //stdlib/ets. ets} table management for a
%%% 	Service Logic Processing Program (SLP) providing an interworking 
%%% 	function (IWF) for spending limits with DIAMETER Sy and Nchf SBI
%%% 	within the {@link //cse. cse} application.
%%%
%%% This module implements a process which creates, and has ownership of,
%%% the {@link //stdlib/ets. ets} tables required by the
%%% {@link //diameter/diameter_app. diameter_app} and
%%% {@link //inets/httpd. httpd} callback modules
%%% (`cse_diameter_3gpp_sy_application_cb', `cse_rest_res_nchf')
%%% which together implement the SLP providing the IWF.
%%%
%%% == Tables ==
%%% The `sy_session' table contains `{SessionId, SUPI, SubscriptionURL}'.<br/>
%%% The `nchf_session' table contains `{SUPI, Service, SessionId, OriginHost, OriginRealm, DestinationHost, DestinationRealm, SupportedFeatures}'.
%%%
%%% == SLP Call Sequence ==
%%% The diagram below depicts the normal call sequence for the overall SLP:
%%%
%%% <img alt="call sequence chart" src="slp-spending-limit-iwf-msc.svg" />
%%%
-module(cse_slp_spending_limit_iwf_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([up/3]).

-type state() :: up.
-type statedata() :: [ets:tid()].

%%----------------------------------------------------------------------
%%  The cse_slp_spending_limit_iwf_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	[state_functions, state_enter].

-spec init(Args) -> Result
	when
		Args :: [term()],
		Result :: {ok, State, Data} | {ok, State, Data, Actions}
				| ignore | {stop, Reason},
		State :: state(),
		Data :: statedata(),
		Actions :: Action | [Action],
		Action :: gen_statem:action(),
		Reason :: term().
%% @doc Initialize the {@module} finite state machine.
%%
%% 	Initialize a Service Logic Processing Program (SLP) instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init(_Args) ->
	Options = [public, named_table],
	Tables = [sy_session, nchf_session],
	process_flag(trap_exit, true),
	init1(Tables, Options, []).
%% @hidden
init1([H | T], Options, Data) ->
	case ets:whereis(H) of
		undefined ->
			init2(H, T, Options, Data);
		_Tid when length(Data) == 0 ->
			ignore
	end;
init1([], _Options, Data) ->
	{ok, up, Data}.
%% @hidden
init2(H, T, Options, Data) ->
	ets:new(H, Options),
	init1(T, Options, [H | Data]).

-spec up(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>up</em> state.
%% @private
up(enter, up = _EventContent, _Data) ->
	keep_state_and_data;
up(EventType, up = _EventContent, _Data) ->
	{stop, EventType}.

-spec handle_event(EventType, EventContent, State, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		State :: state(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(State).
%% @doc Handles events received in any state.
%% @private
%%
handle_event(EventType, _EventContent, _State, _Data) ->
	{stop, EventType}.

-spec terminate(Reason, State, Data) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state(),
		Data ::  statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_statem:terminate/3
%% @private
%%
terminate(shutdown, _State, Data) ->
	F = fun(Tid) ->
			ets:delete(Tid)
	end,
	lists:foreach(F, Data).

-spec code_change(OldVsn, OldState, OldData, Extra) -> Result
	when
		OldVsn :: Version | {down, Version},
		Version ::  term(),
		OldState :: state(),
		OldData :: statedata(),
		Extra :: term(),
		Result :: {ok, NewState, NewData} |  Reason,
		NewState :: state(),
		NewData :: statedata(),
		Reason :: term().
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_statem:code_change/3
%% @private
%%
code_change(_OldVsn, OldState, OldData, _Extra) ->
	{ok, OldState, OldData}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

