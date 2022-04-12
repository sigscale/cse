%%% cse_slp_prepaid_diameter_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
%%% @author Refath Wadood <refath@sigscale.org> [http://www.sigscale.org]
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
%%% 	module implements a Service Logic Processing Program (SLP)
%%% 	for CAMEL Application Part (CAP) within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This module is not intended to be started directly but rather
%%% 	pushed onto the callback stack of the
%%% 	{@link //cse/cse_slp_cap_fsm. cse_slp_cap_fsm}
%%% 	{@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module which handles initialization, dialog `BEGIN' and the
%%% 	first `Invoke' with `InitialDP'.  The Service Key is used to
%%% 	lookup the SLP implementation module (this) and push it onto
%%% 	the callback stack.
%%%
-module(cse_slp_prepaid_diameter_fsm).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Refath Wadood <refath@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3]).
%% export the private api
-export([]).

-include_lib("kernel/include/logger.hrl").
-include_lib("cse/include/cse_codec.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_cc_application_rfc4006.hrl").

-type state() :: null.

-type statedata() :: #{nrf_profile => atom(),
		nrf_uri => string(),
		nrf_location => string() | undefined,
		nrf_reqid => reference() | undefined}.

%%----------------------------------------------------------------------
%%  The cse_slp_prepaid_diameter_fsm gen_statem callbacks
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
	{ok, null, #{}}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(enter, null = _EventContent, _Data) ->
	keep_state_and_data;
null({call, From}, #'3gpp_ro_CCR'{} = EventContent, Data) ->
	{ok, Profile} = application:get_env(cse, nrf_profile),
	{ok, URI} = application:get_env(cse, nrf_uri),
	NewData = Data#{from => From, bill_profile => Profile, bill_uri => URI},
	Actions = [{next_event, internal, EventContent}],
	{next_state, collect_information, NewData, Actions};
null(enter, _EventContent, _Data) ->
	keep_state_and_data.

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
handle_event(_EventType, _EventContent, _State, _Data) ->
	keep_state_and_data.

-spec terminate(Reason, State, Data) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state(),
		Data ::  statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_statem:terminate/3
%% @private
%%
terminate(_Reason, _State, _Data) ->
	ok.

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
%%  private api
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

