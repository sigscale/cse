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
-export([null/3, collect_information/3, analyse_information/3,
		routing/3, o_alerting/3, o_active/3]).

-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("cap/include/CAP-operationcodes.hrl").
-include_lib("cap/include/CAP-datatypes.hrl").
-include_lib("cap/include/CAP-gsmSSF-gsmSCF-pkgs-contracts-acs.hrl").
-include_lib("cap/include/CAMEL-datatypes.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: null | collect_information
		| analyse_information | routing | o_alerting | o_active.

%% the cse_slp_fsm state data
-record(statedata,
		{dha :: pid() | undefined,
		cco :: pid() | undefined,
		did :: 0..4294967295 | undefined,
		ac :: tuple() | undefined,
		scf :: sccp_codec:party_address() | undefined,
		ssf :: sccp_codec:party_address() | undefined}).
-type statedata() :: #statedata{}.

-define(Pkgs, 'CAP-gsmSSF-gsmSCF-pkgs-contracts-acs').

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
%% 	Initialize a Service Logic Program (SLP) instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init([APDU]) ->
	process_flag(trap_exit, true),
	Data = #statedata{},
	{ok, null, Data}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(enter, null, _Data) ->
	keep_state_and_data;
null(enter, OldState,
		#statedata{did = DialogueID, dha = DHA} = Data) ->
	End = #'TC-END'{dialogueID = DialogueID,
			qos = {true, true}, termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	{stop, normal};
null(cast, {register_csl, DHA, CCO}, Data) ->
	NewData = Data#statedata{dha = DHA, cco = CCO},
	{next_state, collect_information, NewData}.

-spec collect_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>collect_information</em> state.
%% @private
collect_information(enter, _State, _Data) ->
	keep_state_and_data;
collect_information(cast, {'TC', 'BEGIN', indication,
		#'TC-BEGIN'{appContextName = AC,
		dialogueID = DialogueID, qos = _QoS,
		destAddress = DestAddress, origAddress = OrigAddress,
		componentsPresent = true, userInfo = _UserInfo}} = _EventContent,
		#statedata{did = undefined} = Data) ->
	NewData = Data#statedata{did = DialogueID, ac = AC,
			scf = DestAddress, ssf = OrigAddress},
	{keep_state, NewData};
collect_information(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-initialDP',
		dialogueID = DialogueID, invokeID = _InvokeID,
		lastComponent = true, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID, dha = DHA, cco = CCO,
		scf = SCF, ac = AC} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_InitialDPArg', Argument) of
		{ok, InitialDPArg} ->
			NewData = Data#statedata{},
			BCSMEvents = [#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = routeSelectFailure,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = oCalledPartyBusy,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = oNoAnswer,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = oAnswer,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = oDisconnect,
							monitorMode = notifyAndContinue,
							legID = {sendingSideID, ?leg1}},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = oDisconnect,
							monitorMode = notifyAndContinue,
							legID = {sendingSideID, ?leg2}},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = oAbandon,
							monitorMode = notifyAndContinue}],
			{ok, RequestReportBCSMEventArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg',
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg'{bcsmEvents = BCSMEvents}),
			Invoke1 = #'TC-INVOKE'{operation = ?'opcode-requestReportBCSMEvent',
					invokeID = 1, dialogueID = DialogueID, class = 1,
					parameters = RequestReportBCSMEventArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke1}),
			{ok, CallInformationRequestArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_CallInformationRequestArg',
					#'GenericSCF-gsmSSF-PDUs_CallInformationRequestArg'{
					requestedInformationTypeList = [callAttemptElapsedTime,
					callStopTime, callConnectedElapsedTime, releaseCause]}),
			Invoke2 = #'TC-INVOKE'{operation = ?'opcode-callInformationRequest',
					invokeID = 2, dialogueID = DialogueID, class = 1,
					parameters = CallInformationRequestArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke2}),
			TimeDurationCharging = #'PduAChBillingChargingCharacteristics_timeDurationCharging'{
					maxCallPeriodDuration = 300},
			{ok, PduAChBillingChargingCharacteristics} = 'CAMEL-datatypes':encode(
					'PduAChBillingChargingCharacteristics', {timeDurationCharging, TimeDurationCharging}),
			{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ApplyChargingArg',
					#'GenericSCF-gsmSSF-PDUs_ApplyChargingArg'{
					aChBillingChargingCharacteristics = PduAChBillingChargingCharacteristics,
					partyToCharge = {sendingSideID, ?leg1}}),
			Invoke3 = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
					invokeID = 3, dialogueID = DialogueID, class = 1,
					parameters = ApplyChargingArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke3}),
			Invoke4 = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = 4, dialogueID = DialogueID, class = 1},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke4}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					origAddress = SCF, componentsPresent = true},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, analyse_information, NewData};
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
analyse_information(enter, _State, _Data) ->
	keep_state_and_data;
analyse_information(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, lastComponent = LastComponent,
		parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAbandon}} ->
			case LastComponent of
				true ->
					{next_state, null, Data};
				false ->
					keep_state_and_data
			end;
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAnswer}} ->
			case LastComponent of
				true ->
					{next_state, null, Data};
				false ->
					keep_state_and_data
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
analyse_information(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
		dialogueID = DialogueID, lastComponent = LastComponent,
		parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, ChargingResultArg} ->
			case 'CAMEL-datatypes':decode('PduCallResult', ChargingResultArg) of
				{timeDurationChargingResult,
						#'PduCallResult_timeDurationChargingResult'{}} ->
					case LastComponent of
						true ->
							{next_state, null, Data};
						false ->
							keep_state_and_data
					end;
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
analyse_information(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
		dialogueID = DialogueID, lastComponent = LastComponent,
		parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{}} ->
			case LastComponent of
				true ->
					{next_state, null, Data};
				false ->
					keep_state_and_data
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
analyse_information(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	{next_state, null, Data};
analyse_information(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	{next_state, null, Data}.

-spec routing(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>routing</em> state.
%% @private
routing(enter, _State, _Data) ->
	keep_state_and_data;
routing(_EventType, _EventContent, #statedata{} = _Data) ->
	keep_state_and_data.

-spec o_alerting(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_alerting</em> state.
%% @private
o_alerting(enter, _State, _Data) ->
	keep_state_and_data;
o_alerting(_EventType, _EventContent, #statedata{} = _Data) ->
	keep_state_and_data.

-spec o_active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_active</em> state.
%% @private
o_active(enter, _State, _Data) ->
	keep_state_and_data;
o_active(_EventType, _EventContent, #statedata{} = _Data) ->
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
%%  internal functions
%%----------------------------------------------------------------------

