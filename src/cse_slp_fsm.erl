%%% cse_slp_fsm.erl
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
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements a Service Logic Program (SLP) instance within
%%% 	the {@link //cse. cse} application.
%%%
%%%
-module(cse_slp_fsm).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([collect_information/3, analyse_information/3,
		routing/3, o_alerting/3, o_active/3]).

-include_lib("tcap/include/tcap.hrl").
-include_lib("cap/include/CAP-operationcodes.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: collect_information | analyse_information
		| routing | o_alerting | o_active.

%% the cse_slp_fsm state data
-record(statedata,
		{did :: byte() | undefined,
		ac :: tuple() | undefined,
		dest_address :: sccp_codec:party_address() | undefined,
		orig_address :: sccp_codec:party_address() | undefined}).
-type statedata() :: #statedata{}.

%%----------------------------------------------------------------------
%%  The cse_slp_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	[state_functions].

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
%% 	Initialize a Service Logic Program (SLP) instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init([APDU]) ->
erlang:display({?MODULE, ?LINE, init, APDU}),
	process_flag(trap_exit, true),
	Data = #statedata{},
	{ok, collect_information, Data}.

-spec collect_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>collect_information</em> state.
%% @private
collect_information(cast, {'TC', 'BEGIN', indication,
		#'TC-BEGIN'{appContextName = AC,
		dialogueID = DialogueID, qos = _QoS,
		destAddress = DestAddress, origAddress = OrigAddress,
		componentsPresent = true, userInfo = _UserInfo}} = _EventContent,
		#statedata{did = undefined} = Data) ->
	NewData = Data#statedata{did = DialogueID, ac = AC,
			dest_address = DestAddress, orig_address = OrigAddress},
erlang:display({?MODULE, ?LINE, collect_information, cast, _EventContent, NewData}),
	{keep_state, NewData};
collect_information(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-initialDP',
		dialogueID = DialogueID, invokeID = InvokeID,
		lastComponent = true, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case 'CAP-gsmSSF-gsmSCF-pkgs-contracts-acs':decode(
			'GenericSSF-gsmSCF-PDUs_InitialDPArg', Argument) of
		{ok, InitialDPArg} ->
			erlang:display({?MODULE, ?LINE, collect_information, InitialDPArg}),
			NewData = Data#statedata{},
			{keep_state, NewData};
		{error, Reason} ->
			{stop, Reason}
	end.

-spec analyse_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>analyse_information</em> state.
%% @private
analyse_information(_EventType, _EventContent, #statedata{} = _Data) ->
erlang:display({?MODULE, ?LINE, analyse_information, _EventType, _EventContent, _Data}),
	keep_state_and_data.

-spec routing(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>routing</em> state.
%% @private
routing(_EventType, _EventContent, #statedata{} = _Data) ->
erlang:display({?MODULE, ?LINE, routing, _EventType, _EventContent, _Data}),
	keep_state_and_data.

-spec o_alerting(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_alerting</em> state.
%% @private
o_alerting(_EventType, _EventContent, #statedata{} = _Data) ->
erlang:display({?MODULE, ?LINE, o_alerting, _EventType, _EventContent, _Data}),
	keep_state_and_data.

-spec o_active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_active</em> state.
%% @private
o_active(_EventType, _EventContent, #statedata{} = _Data) ->
erlang:display({?MODULE, ?LINE, o_active, _EventType, _EventContent, _Data}),
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
erlang:display({?MODULE, ?LINE, handle_event, _EventType, _EventContent, _State, _Data}),
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
erlang:display({?MODULE, ?LINE, terminate, _Reason, _State, _Data}),
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
%%  internal functions
%%----------------------------------------------------------------------

