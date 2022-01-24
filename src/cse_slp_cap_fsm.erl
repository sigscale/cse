%%% cse_slp_cap_fsm.erl
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
%%% @reference 3GPP TS
%%% 	<a href="https://webapp.etsi.org/key/key.asp?GSMSpecPart1=23&amp;GSMSpecPart2=078">23.078</a>
%%% 	CAMEL Phase 4; Stage 2
%%%
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements an initial  Service Logic Processing Program (SLP)
%%% 	for CAMEL Application Part (CAP) within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	An `InitialDP' procedure contains a `serviceKey' parameter which
%%% 	indicates the IN service requested and is used to select which
%%% 	Service Logic Processing Program (SLP) should be used.
%%%
%%% 	A service table lookup provides the name of another
%%% 	{@link //stdlib/gen_statem. gen_statem} behaviour callback module
%%% 	implementing the target SLP and this process continues using the
%%% 	new callback.
%%%
-module(cse_slp_cap_fsm).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3]).

-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("cap/include/CAP-gsmSSF-gsmSCF-pkgs-contracts-acs.hrl").
-include_lib("cap/include/CAP-operationcodes.hrl").
-include_lib("cap/include/CAP-errorcodes.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: null.
-type statedata() :: #{dha =>  pid() | undefined,
		cco => pid() | undefined,
		did => 0..4294967295 | undefined,
		ac => tuple() | undefined,
		scf => sccp_codec:party_address() | undefined,
		ssf => sccp_codec:party_address() | undefined}.

-define(Pkgs, 'CAP-gsmSSF-gsmSCF-pkgs-contracts-acs').

%%----------------------------------------------------------------------
%%  The cse_slp_cap_fsm gen_statem callbacks
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
%% 	Initialize a Service Logic Processing Program (SLP) instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init([_APDU]) ->
	process_flag(trap_exit, true),
	{ok, null, #{}}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(cast, {register_csl, DHA, CCO} = _EventContent, Data) ->
	link(DHA),
	NewData = Data#{dha => DHA, cco => CCO},
	{keep_state, NewData};
null(cast, {'TC', 'BEGIN', indication,
		#'TC-BEGIN'{appContextName = AC,
				dialogueID = DialogueID, qos = _QoS,
				destAddress = DestAddress, origAddress = OrigAddress,
				componentsPresent = true, userInfo = _UserInfo}} = _EventContent,
		Data) when not is_map_key(did, Data) ->
	NewData = Data#{did => DialogueID, ac => AC,
			scf => DestAddress, ssf => OrigAddress},
	{keep_state, NewData};
null(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-initialDP',
				dialogueID = DialogueID, invokeID = InvokeID,
				parameters = Argument} = Invoke},
		#{did := DialogueID, ac := AC, dha := DHA, cco := CCO,
				ssf := SSF, scf := SCF} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_InitialDPArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{
				serviceKey = ServiceKey} = InitialDPArg}
				when is_integer(ServiceKey) ->
			F = fun() ->
					mnesia:read(service, ServiceKey, read)
			end,
			case mnesia:async_dirty(F) of
				[{service, ServiceKey, CbModule, EDP}]
						when is_atom(CbModule), is_map(EDP) ->
					NewData = Data#{edp => EDP},
					Actions = [{push_callback_module, CbModule},
							{next_event, internal, {Invoke, InitialDPArg}}],
					{keep_state, NewData, Actions};
				[] ->
					Error = #'TC-U-ERROR'{dialogueID = DialogueID,
							invokeID = InvokeID,
							error = ?'errcode-missingCustomerRecord'},
					gen_statem:cast(CCO, {'TC', 'U-ERROR', request, Error}),
					End = #'TC-END'{dialogueID = DialogueID,
							appContextName = AC, qos = {true, true},
							termination = basic},
					gen_statem:cast(DHA, {'TC', 'END', request, End}),
					?LOG_WARNING([{ac, AC}, {did, DialogueID},
							{ssf, SSF}, {scf, SCF},
							{serviceKey, ServiceKey}, {slp, not_found}]),
					keep_state_and_data
			end;
		{ok, #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{}} ->
			Reject = #'TC-U-REJECT'{dialogueID = DialogueID,
					invokeID = InvokeID,
					problemCode =  {returnError, mistypedParameter}},
			gen_statem:cast(CCO, {'TC', 'U-REJECT', request, Reject}),
			End = #'TC-END'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					termination = basic},
			gen_statem:cast(DHA, {'TC', 'END', request, End}),
			keep_state_and_data;
		{error, _Reason} ->
			Reject = #'TC-U-REJECT'{dialogueID = DialogueID,
					invokeID = InvokeID,
					problemCode =  {returnError, mistypedParameter}},
			gen_statem:cast(CCO, {'TC', 'U-REJECT', request, Reject}),
			End = #'TC-END'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					termination = basic},
			gen_statem:cast(DHA, {'TC', 'END', request, End}),
			keep_state_and_data
	end;
null(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = Other,
				dialogueID = DialogueID, invokeID = InvokeID} = _Invoke},
		#{did := DialogueID, as := AC, dha := DHA, cco := CCO,
				ssf := SSF, scf := SCF} = _Data) ->
	Reject = #'TC-U-REJECT'{dialogueID = DialogueID,
			invokeID = InvokeID,
			problemCode = {invoke, unrecognizedOperation}},
	gen_statem:cast(CCO, {'TC', 'U-REJECT', request, Reject}),
	End = #'TC-END'{dialogueID = DialogueID,
			appContextName = AC, qos = {true, true},
			termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	?LOG_WARNING([{ac, AC}, {did, DialogueID},
			{ssf, SSF}, {scf, SCF}, {operation, Other},
			{error, unrecognizedOperation}]),
	keep_state_and_data;
null(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

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
%%  internal functions
%%----------------------------------------------------------------------

