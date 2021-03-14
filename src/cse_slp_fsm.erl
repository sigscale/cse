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
		routing/3, o_alerting/3, o_active/3, disconnect/3,
		abandon/3, terminating_call_handling/3, t_alerting/3,
		t_active/3, exception/3]).
%% export the private api
-export([nrf_start_reply/2, nrf_update_reply/2, nrf_release_reply/2]).

-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("cap/include/CAP-operationcodes.hrl").
-include_lib("cap/include/CAP-datatypes.hrl").
-include_lib("cap/include/CAP-gsmSSF-gsmSCF-pkgs-contracts-acs.hrl").
-include_lib("cap/include/CAMEL-datatypes.hrl").
-include_lib("kernel/include/logger.hrl").
-include("cse_codec.hrl").

-type state() :: null | collect_information | analyse_information
		| routing | o_alerting | o_active | disconnect | abandon
		| terminating_call_handling | t_alerting | t_active
		| exception.

%% the cse_slp_fsm state data
-record(statedata,
		{dha :: pid() | undefined,
		cco :: pid() | undefined,
		did :: 0..4294967295 | undefined,
		iid = 0 :: 0..127,
		ac :: tuple() | undefined,
		scf :: sccp_codec:party_address() | undefined,
		ssf :: sccp_codec:party_address() | undefined,
		imsi :: [$0..$9] | undefined,
		msisdn :: [$0..$9] | undefined,
		called ::  [$0..$9] | undefined,
		calling ::  [$0..$9] | undefined,
		call_ref :: binary() | undefined,
		msc :: binary() | undefined,
		nrf_profile :: atom(),
		nrf_uri :: string(),
		nrf_location :: string() | undefined,
		nrf_reqid :: reference() | undefined}).
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
	{ok, Profile} = application:get_env(nrf_profile),
	{ok, URI} = application:get_env(nrf_uri),
	process_flag(trap_exit, true),
	Data = #statedata{nrf_profile = Profile, nrf_uri = URI},
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
null(enter, _OldState,
		#statedata{iid = 0, did = DialogueID, ac = AC, dha = DHA}) ->
	End = #'TC-END'{dialogueID = DialogueID,
			appContextName = AC, qos = {true, true},
			termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	keep_state_and_data;
null(enter, _OldState, #statedata{did = DialogueID, dha = DHA}) ->
	End = #'TC-END'{dialogueID = DialogueID,
			qos = {true, true}, termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	keep_state_and_data;
null(cast, {register_csl, DHA, CCO}, Data) ->
	link(DHA),
	NewData = Data#statedata{dha = DHA, cco = CCO},
	{next_state, collect_information, NewData};
null(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
null(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

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
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_InitialDPArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{eventTypeBCSM = collectedInfo,
				callingPartyNumber = CallingPartyNumber,
				calledPartyBCDNumber = CalledPartyBCDNumber,
				iMSI = IMSI, callReferenceNumber = CallReferenceNumber,
				mscAddress = MscAddress} = _InitialDPArg} ->
			#calling_party{nai = 4, npi = 1, address = CallingAddress}
					= cse_codec:calling_party(CallingPartyNumber),
			MSISDN = lists:flatten([integer_to_list(D) || D <- CallingAddress]),
			#called_party_bcd{address = CalledNumber}
					= cse_codec:called_party_bcd(CalledPartyBCDNumber),
			DN = lists:flatten([integer_to_list(D) || D <- CalledNumber]),
			NewData = Data#statedata{imsi = cse_codec:tbcd(IMSI),
					msisdn = MSISDN, called = DN, calling = MSISDN,
					call_ref = CallReferenceNumber, msc = MscAddress},
			nrf_start(NewData);
		{ok, #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{eventTypeBCSM = termAttemptAuthorized,
				callingPartyNumber = CallingPartyNumber,
				calledPartyNumber = CalledPartyNumber,
				iMSI = IMSI, callReferenceNumber = CallReferenceNumber,
				mscAddress = MscAddress} = _InitialDPArg} ->
			#calling_party{nai = 4, npi = 1, address = CallingAddress}
					= cse_codec:calling_party(CallingPartyNumber),
			#called_party{nai = 4, npi = 1, address = CalledAddress}
					= cse_codec:called_party(CalledPartyNumber),
			MSISDN = lists:flatten([integer_to_list(D) || D <- CalledAddress]),
			DN = lists:flatten([integer_to_list(D) || D <- CallingAddress]),
			NewData = Data#statedata{imsi = cse_codec:tbcd(IMSI),
					msisdn = MSISDN, called = MSISDN, calling = DN,
					call_ref = CallReferenceNumber, msc = MscAddress},
			nrf_start(NewData);
		{ok, #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{
				eventTypeBCSM = EventType} = InitialDPArg} ->
			?LOG_WARNING([{state, collect_information}, {eventTypeBCSM, EventType},
					{slpi, self()}, {initalDPArg, InitialDPArg}]),
			{keep_state, Data}
	end;
collect_information(cast, {nrf_start,
		{RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#statedata{nrf_reqid = RequestId, msisdn = MSISDN, calling = MSISDN,
		nrf_profile = Profile, nrf_uri = URI, did = DialogueID, iid = IID,
		dha = DHA, cco = CCO, scf = SCF, ac = AC} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := [#{"resultCode" := "SUCCESS",
				"grantedUnit" := #{"time" := GrantedTime}}]}},
				{_, Location}} when is_list(Location) ->
			NewData = Data#statedata{iid = IID + 4,
						nrf_reqid = undefined, nrf_location = Location},
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
					invokeID = IID + 1, dialogueID = DialogueID, class = 2,
					parameters = RequestReportBCSMEventArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke1}),
			{ok, CallInformationRequestArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_CallInformationRequestArg',
					#'GenericSCF-gsmSSF-PDUs_CallInformationRequestArg'{
					requestedInformationTypeList = [callAttemptElapsedTime,
					callStopTime, callConnectedElapsedTime, releaseCause]}),
			Invoke2 = #'TC-INVOKE'{operation = ?'opcode-callInformationRequest',
					invokeID = IID + 2, dialogueID = DialogueID, class = 2,
					parameters = CallInformationRequestArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke2}),
			TimeDurationCharging = #'PduAChBillingChargingCharacteristics_timeDurationCharging'{
					maxCallPeriodDuration = GrantedTime * 10},
			{ok, PduAChBillingChargingCharacteristics} = 'CAMEL-datatypes':encode(
					'PduAChBillingChargingCharacteristics',
					{timeDurationCharging, TimeDurationCharging}),
			{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ApplyChargingArg',
					#'GenericSCF-gsmSSF-PDUs_ApplyChargingArg'{
					aChBillingChargingCharacteristics = PduAChBillingChargingCharacteristics,
					partyToCharge = {sendingSideID, ?leg1}}),
			Invoke3 = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
					invokeID = IID + 3, dialogueID = DialogueID, class = 2,
					parameters = ApplyChargingArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke3}),
			Invoke4 = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = IID + 4, dialogueID = DialogueID, class = 4},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke4}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					origAddress = SCF, componentsPresent = true},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, analyse_information, NewData};
		{{ok, #{"serviceRating" := [#{"resultCode" := _}]}}, {_, Location}}
				when is_list(Location) ->
			NewData = Data#statedata{nrf_reqid = undefined,
					nrf_location = Location},
			{next_state, exception, NewData};
		{{ok, JSON}, {_, Location}} when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			NewData = Data#statedata{nrf_reqid = undefined,
					nrf_location = Location},
			{next_state, exception, NewData};
		{{error, Partial, Remaining}, {_, Location}} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			NewData = Data#statedata{nrf_reqid = undefined,
					nrf_location = Location},
			{next_state, exception, NewData};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {missing, "Location:"},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData}
	end;
collect_information(cast, {nrf_start,
		{RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#statedata{nrf_reqid = RequestId, msisdn = MSISDN, called = MSISDN,
		nrf_profile = Profile, nrf_uri = URI, did = DialogueID, iid = IID,
		dha = DHA, cco = CCO, scf = SCF, ac = AC} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := [#{"resultCode" := "SUCCESS",
				"grantedUnit" := #{"time" := GrantedTime}}]}},
				{_, Location}} when is_list(Location) ->
			NewData = Data#statedata{iid = IID + 4,
						nrf_reqid = undefined, nrf_location = Location},
			BCSMEvents = [#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = tBusy,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = tNoAnswer,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = tAnswer,
							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = tAbandon,
							monitorMode = notifyAndContinue},
%					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
%							eventTypeBCSM = callAccepted, % Alerting DP is a Phase 4 feature
%							monitorMode = notifyAndContinue},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = tDisconnect,
							monitorMode = notifyAndContinue,
							legID = {sendingSideID, ?leg1}},
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg_bcsmEvents_SEQOF'{
							eventTypeBCSM = tDisconnect,
							monitorMode = notifyAndContinue,
							legID = {sendingSideID, ?leg2}}],
			{ok, RequestReportBCSMEventArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg',
					#'GenericSCF-gsmSSF-PDUs_RequestReportBCSMEventArg'{bcsmEvents = BCSMEvents}),
			Invoke1 = #'TC-INVOKE'{operation = ?'opcode-requestReportBCSMEvent',
					invokeID = IID + 1, dialogueID = DialogueID, class = 2,
					parameters = RequestReportBCSMEventArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke1}),
			{ok, CallInformationRequestArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_CallInformationRequestArg',
					#'GenericSCF-gsmSSF-PDUs_CallInformationRequestArg'{
					requestedInformationTypeList = [callAttemptElapsedTime,
					callStopTime, callConnectedElapsedTime, releaseCause]}),
			Invoke2 = #'TC-INVOKE'{operation = ?'opcode-callInformationRequest',
					invokeID = IID + 2, dialogueID = DialogueID, class = 2,
					parameters = CallInformationRequestArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke2}),
			TimeDurationCharging = #'PduAChBillingChargingCharacteristics_timeDurationCharging'{
					maxCallPeriodDuration = GrantedTime * 10},
			{ok, PduAChBillingChargingCharacteristics} = 'CAMEL-datatypes':encode(
					'PduAChBillingChargingCharacteristics',
					{timeDurationCharging, TimeDurationCharging}),
			{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ApplyChargingArg',
					#'GenericSCF-gsmSSF-PDUs_ApplyChargingArg'{
					aChBillingChargingCharacteristics = PduAChBillingChargingCharacteristics,
					partyToCharge = {sendingSideID, ?leg2}}),
			Invoke3 = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
					invokeID = IID + 3, dialogueID = DialogueID, class = 2,
					parameters = ApplyChargingArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke3}),
			Invoke4 = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = IID + 4, dialogueID = DialogueID, class = 4},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke4}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					origAddress = SCF, componentsPresent = true},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, terminating_call_handling, NewData};
		{{ok, #{"serviceRating" := [#{"resultCode" := _}]}}, {_, Location}}
				when is_list(Location) ->
			NewData = Data#statedata{nrf_reqid = undefined,
					nrf_location = Location},
			{next_state, exception, NewData};
		{{ok, JSON}, {_, Location}} when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			NewData = Data#statedata{nrf_reqid = undefined,
					nrf_location = Location},
			{next_state, exception, NewData};
		{{error, Partial, Remaining}, {_, Location}} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			NewData = Data#statedata{nrf_reqid = undefined,
					nrf_location = Location},
			{next_state, exception, NewData};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {missing, "Location:"},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData}
	end;
collect_information(cast, {nrf_start,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI} = Data) ->
	NewData = Data#statedata{nrf_reqid = undefined},
	?LOG_WARNING([{nrf_start, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {slpi, self()}]),
	{next_state, exception, NewData};
collect_information(cast, {nrf_start, {RequestId, {error, Reason}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI} = Data) ->
	NewData = Data#statedata{nrf_reqid = undefined},
	?LOG_ERROR([{nrf_start, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {slpi, self()}]),
	{next_state, exception, NewData};
collect_information(info, {'EXIT', DHA, Reason},
		#statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

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
analyse_information(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
analyse_information(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = analyzedInformation}} ->
			{next_state, routing, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAbandon}} ->
			{next_state, abandon, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAnswer}} ->
			{next_state, o_active, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = routeSelectFailure}} ->
			{next_state, exception, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
analyse_information(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
analyse_information(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
analyse_information(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, analyse_information}, {ssf, SSF}]),
	{next_state, exception, Data};
analyse_information(info, {'EXIT', DHA, Reason},
		 #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec terminating_call_handling(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>terminating_call_handling</em> state.
%% @private
terminating_call_handling(enter, _State, _Data) ->
	keep_state_and_data;
terminating_call_handling(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
terminating_call_handling(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tAbandon}} ->
			{next_state, abandon, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tBusy}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = callAccepted}} ->
			{next_state, t_alerting, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tAnswer}} ->
			{next_state, t_active, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
terminating_call_handling(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
terminating_call_handling(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
terminating_call_handling(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, terminating_call_handling}, {ssf, SSF}]),
	{next_state, exception, Data};
terminating_call_handling(info, {'EXIT', DHA, Reason},
		 #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

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
routing(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
routing(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = routeSelectFailure}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oNoAnswer}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oCalledPartyBusy}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAnswer}} ->
			{next_state, o_active, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
routing(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, routing}, {ssf, SSF}]),
	{next_state, exception, Data};
routing(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
routing(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
routing(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

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
o_alerting(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
o_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = routeSelectFailure}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAbandon}} ->
			{next_state, abandon, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oNoAnswer}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oCalledPartyBusy}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oAnswer}} ->
			{next_state, o_active, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
o_alerting(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
o_alerting(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
o_alerting(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, o_alerting}, {ssf, SSF}]),
	{next_state, exception, Data};
o_alerting(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec t_alerting(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>t_alerting</em> state.
%% @private
t_alerting(enter, _State, _Data) ->
	keep_state_and_data;
t_alerting(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
t_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tAbandon}} ->
			{next_state, abandon, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tNoAnswer}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tBusy}} ->
			{next_state, exception, Data};
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tAnswer}} ->
			{next_state, t_active, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
t_alerting(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
t_alerting(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
t_alerting(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, t_alerting}, {ssf, SSF}]),
	{next_state, exception, Data};
t_alerting(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

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
o_active(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
o_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = oDisconnect}} ->
			{next_state, disconnect, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
o_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			case 'CAMEL-datatypes':decode('PduCallResult', ChargingResultArg) of
				{ok, {timeDurationChargingResult,
						#'PduCallResult_timeDurationChargingResult'{
						timeInformation = {timeIfNoTariffSwitch, Time}}}} ->
					nrf_update(Time div 10, Data);
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
o_active(cast, {nrf_update,
		{RequestId, {{_, 200, _}, _Headers, Body}}},
		#statedata{nrf_reqid = RequestId, nrf_uri = URI,
		nrf_profile = Profile, nrf_location = Location,
		did = DialogueID, iid = IID, dha = DHA, cco = CCO,
		scf = SCF} = Data) ->
	case zj:decode(Body) of
		{ok, #{"serviceRating" := [#{"resultCode" := "SUCCESS"},
				#{"resultCode" := "SUCCESS"}] = ServiceRating} = JSON} ->
			Fold = fun(#{"grantedUnit" := #{"time" := GU}}, undefined)
							when is_integer(GU) ->
						GU;
					(#{"grantedUnit" := #{"time" := GU}}, _)
							when is_integer(GU) ->
						multiple;
					(#{"grantedUnit" := _}, undefined) ->
						invalid;
					(#{}, Acc) ->
						Acc
			end,
			case lists:foldl(Fold, undefined, ServiceRating) of
				GrantedTime when is_integer(GrantedTime) ->
					NewIID = IID + 1,
					NewData = Data#statedata{nrf_reqid = undefined, iid = NewIID},
					TimeDurationCharging = #'PduAChBillingChargingCharacteristics_timeDurationCharging'{
							maxCallPeriodDuration = GrantedTime * 10},
					{ok, PduAChBillingChargingCharacteristics} = 'CAMEL-datatypes':encode(
							'PduAChBillingChargingCharacteristics',
							{timeDurationCharging, TimeDurationCharging}),
					{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ApplyChargingArg',
							#'GenericSCF-gsmSSF-PDUs_ApplyChargingArg'{
							aChBillingChargingCharacteristics = PduAChBillingChargingCharacteristics,
							partyToCharge = {sendingSideID, ?leg1}}),
					Invoke = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
							invokeID = NewIID, dialogueID = DialogueID, class = 2,
							parameters = ApplyChargingArg},
					gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
					Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
							qos = {true, true}, origAddress = SCF,
							componentsPresent = true},
					gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
					{keep_state, NewData};
				Other when is_atom(Other) ->
					?LOG_ERROR([{?MODULE, nrf_update}, {Other, "grantedUnit"},
							{profile, Profile}, {uri, URI}, {location, Location},
							{slpi, self()}, {json, JSON}]),
					NewData = Data#statedata{nrf_reqid = undefined},
					{next_state, exception, NewData}
			end;
		{{ok, #{"serviceRating" := [#{"resultCode" := _},
				#{"resultCode" := _}]}}, {_, Location}} when is_list(Location) ->
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData};
		{{ok, JSON}, {_, Location}} when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData};
		{{error, Partial, Remaining}, {_, Location}} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {missing, "Location:"},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData}
	end;
o_active(cast, {nrf_update,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data) ->
	?LOG_WARNING([{nrf_update, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = Data#statedata{nrf_reqid = undefined},
	{next_state, exception, NewData};
o_active(cast, {nrf_update, {RequestId, {error, Reason}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data) ->
	?LOG_ERROR([{nrf_update, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined},
	{next_state, exception, NewData};
o_active(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
o_active(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
o_active(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, o_active}, {ssf, SSF}]),
	{next_state, exception, Data};
o_active(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec t_active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>t_active</em> state.
%% @private
t_active(enter, _State, _Data) ->
	keep_state_and_data;
t_active(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
t_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{eventTypeBCSM = tDisconnect}} ->
			{next_state, disconnect, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
t_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			case 'CAMEL-datatypes':decode('PduCallResult', ChargingResultArg) of
				{ok, {timeDurationChargingResult,
						#'PduCallResult_timeDurationChargingResult'{
						timeInformation = {timeIfNoTariffSwitch, Time}}}} ->
					nrf_update(Time div 10, Data);
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
t_active(cast, {nrf_update,
		{RequestId, {{_, 200, _}, _Headers, Body}}},
		#statedata{nrf_reqid = RequestId, nrf_uri = URI,
		nrf_profile = Profile, nrf_location = Location,
		did = DialogueID, iid = IID, dha = DHA, cco = CCO,
		scf = SCF} = Data) ->
	case zj:decode(Body) of
		{ok, #{"serviceRating" := [#{"resultCode" := "SUCCESS"},
				#{"resultCode" := "SUCCESS"}] = ServiceRating} = JSON} ->
			Fold = fun(#{"grantedUnit" := #{"time" := GU}}, undefined)
							when is_integer(GU) ->
						GU;
					(#{"grantedUnit" := #{"time" := GU}}, _)
							when is_integer(GU) ->
						multiple;
					(#{"grantedUnit" := _}, undefined) ->
						invalid;
					(#{}, Acc) ->
						Acc
			end,
			case lists:foldl(Fold, undefined, ServiceRating) of
				GrantedTime when is_integer(GrantedTime) ->
					NewIID = IID + 1,
					NewData = Data#statedata{nrf_reqid = undefined, iid = NewIID},
					TimeDurationCharging = #'PduAChBillingChargingCharacteristics_timeDurationCharging'{
							maxCallPeriodDuration = GrantedTime * 10},
					{ok, PduAChBillingChargingCharacteristics} = 'CAMEL-datatypes':encode(
							'PduAChBillingChargingCharacteristics',
							{timeDurationCharging, TimeDurationCharging}),
					{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ApplyChargingArg',
							#'GenericSCF-gsmSSF-PDUs_ApplyChargingArg'{
							aChBillingChargingCharacteristics = PduAChBillingChargingCharacteristics,
							partyToCharge = {sendingSideID, ?leg2}}),
					Invoke = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
							invokeID = NewIID, dialogueID = DialogueID, class = 2,
							parameters = ApplyChargingArg},
					gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
					Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
							qos = {true, true}, origAddress = SCF,
							componentsPresent = true},
					gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
					{keep_state, NewData};
				Other when is_atom(Other) ->
					?LOG_ERROR([{?MODULE, nrf_update}, {Other, "grantedUnit"},
							{profile, Profile}, {uri, URI}, {location, Location},
							{slpi, self()}, {json, JSON}]),
					NewData = Data#statedata{nrf_reqid = undefined},
					{next_state, exception, NewData}
			end;
		{{ok, #{"serviceRating" := [#{"resultCode" := _},
				#{"resultCode" := _}]}}, {_, Location}} when is_list(Location) ->
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData};
		{{ok, JSON}, {_, Location}} when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData};
		{{error, Partial, Remaining}, {_, Location}} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {missing, "Location:"},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_reqid = undefined},
			{next_state, exception, NewData}
	end;
t_active(cast, {nrf_update,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data) ->
	?LOG_WARNING([{nrf_update, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = Data#statedata{nrf_reqid = undefined},
	{next_state, exception, NewData};
t_active(cast, {nrf_update, {RequestId, {error, Reason}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data) ->
	?LOG_ERROR([{nrf_update, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined},
	{next_state, exception, NewData};
t_active(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
t_active(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
t_active(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, t_active}, {ssf, SSF}]),
	{next_state, exception, Data};
t_active(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec abandon(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>abandon</em> state.
%% @private
abandon(enter, _State, _Data) ->
	keep_state_and_data;
abandon(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
abandon(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			case 'CAMEL-datatypes':decode('PduCallResult', ChargingResultArg) of
				{ok, {timeDurationChargingResult,
						#'PduCallResult_timeDurationChargingResult'{}}} ->
					nrf_release(0, Data);
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
abandon(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID}) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{}} ->
			keep_state_and_data;
		{error, Reason} ->
			{stop, Reason}
	end;
abandon(cast, {nrf_release,
		{RequestId, {{_Version, 200, _Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, did = DialogueID,
		iid = IID, cco = CCO} = Data) ->
	NewIID = IID + 1,
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined, iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
abandon(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location,
		did = DialogueID, iid = IID, cco = CCO} = Data) ->
	?LOG_WARNING([{nrf_release, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewIID = IID + 1,
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined, iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
abandon(cast, {nrf_release, {RequestId, {error, Reason}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location,
		did = DialogueID, iid = IID, cco = CCO} = Data) ->
	?LOG_ERROR([{nrf_release, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewIID = IID + 1,
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined, iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
abandon(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
abandon(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
abandon(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, abandon}, {ssf, SSF}]),
	{next_state, null, Data};
abandon(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec disconnect(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>disconnect</em> state.
%% @private
disconnect(enter, _State, _Data) ->
	keep_state_and_data;
disconnect(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
disconnect(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			case 'CAMEL-datatypes':decode('PduCallResult', ChargingResultArg) of
				{ok, {timeDurationChargingResult,
						#'PduCallResult_timeDurationChargingResult'{
						timeInformation = {timeIfNoTariffSwitch, Time}}}} ->
					nrf_release(Time div 10, Data);
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
disconnect(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID}) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{}} ->
			keep_state_and_data;
		{error, Reason} ->
			{stop, Reason}
	end;
disconnect(cast, {nrf_release,
		{RequestId, {{_Version, 200, _Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, did = DialogueID,
		iid = IID, cco = CCO} = Data) ->
	NewIID = IID + 1,
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined, iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
disconnect(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location,
		did = DialogueID, iid = IID, cco = CCO} = Data) ->
	?LOG_WARNING([{nrf_release, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewIID = IID + 1,
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined, iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
disconnect(cast, {nrf_release, {RequestId, {error, Reason}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location,
		did = DialogueID, iid = IID, cco = CCO} = Data) ->
	?LOG_ERROR([{nrf_release, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewIID = IID + 1,
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined, iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
disconnect(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
disconnect(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
disconnect(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, disconnect}, {ssf, SSF}]),
	{next_state, null, Data};
disconnect(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec exception(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>exception</em> state.
%% @private
exception(enter, _OldState,
		#statedata{nrf_reqid = undefined, nrf_location = Location,
		did = DialogueID, iid = IID, cco = CCO} = Data)
		when is_list(Location) ->
	NewIID = IID + 1,
	NewData = Data#statedata{iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	nrf_release(0, NewData);
exception(enter, _OldState,
		#statedata{did = DialogueID, iid = IID, cco = CCO} = Data)->
	NewIID = IID + 1,
	NewData = Data#statedata{iid = NewIID},
	Cause = #cause{location = local_public, value = 31},
	{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
			{allCallSegments, cse_codec:cause(Cause)}),
	Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
			invokeID = NewIID, dialogueID = DialogueID, class = 4,
			parameters = ReleaseCallArg},
	gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
	{next_state, null, NewData};
exception(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
		componentsPresent = true}} = _EventContent,
		#statedata{did = DialogueID} = _Data) ->
	keep_state_and_data;
exception(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{}} ->
			{next_state, null, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
exception(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
		dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-gsmSCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			case 'CAMEL-datatypes':decode('PduCallResult', ChargingResultArg) of
				{ok, {timeDurationChargingResult,
						#'PduCallResult_timeDurationChargingResult'{
						timeInformation = {timeIfNoTariffSwitch, Time}}}} ->
					nrf_release(Time div 10, Data);
				{error, Reason} ->
					{stop, Reason}
			end;
		{error, Reason} ->
			{stop, Reason}
	end;
exception(cast, {nrf_release,
		{RequestId, {{_Version, 200, _Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId} = Data) ->
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined},
	{next_state, null, NewData};
exception(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data) ->
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined},
	?LOG_WARNING([{nrf_release, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	{next_state, null, NewData};
exception(cast, {nrf_release, {RequestId, {error, Reason}}},
		#statedata{nrf_reqid = RequestId, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data) ->
	?LOG_ERROR([{nrf_release, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = Data#statedata{nrf_reqid = undefined,
			nrf_location = undefined},
	{next_state, null, NewData};
exception(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
exception(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
		componentsPresent = false}} = _EventContent,
		#statedata{did = DialogueID}) ->
	{stop, normal};
exception(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
		error = Error, parameters = Parameters}} = _EventContent,
		#statedata{did = DialogueID, ssf = SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, exception}, {ssf, SSF}]),
	{next_state, null, Data};
exception(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
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
%%  private api
%%----------------------------------------------------------------------

-spec nrf_start_reply(ReplyInfo, Fsm) -> ok
	when
		ReplyInfo :: {RequestId, Result} | {RequestId, {error, Reason}},
		RequestId :: reference(),
		Result :: {httpc:status_line(), httpc:headers(), Body},
		Body :: binary(),
		Reason :: term(),
		Fsm :: pid().
%% @doc Handle sending a reply to {@link nrf_start/1}.
%% @private
nrf_start_reply(ReplyInfo, Fsm) ->
	gen_statem:cast(Fsm, {nrf_start, ReplyInfo}).

-spec nrf_update_reply(ReplyInfo, Fsm) -> ok
	when
		ReplyInfo :: {RequestId, Result} | {RequestId, {error, Reason}},
		RequestId :: reference(),
		Result :: {httpc:status_line(), httpc:headers(), Body},
		Body :: binary(),
		Reason :: term(),
		Fsm :: pid().
%% @doc Handle sending a reply to {@link nrf_update/1}.
%% @private
nrf_update_reply(ReplyInfo, Fsm) ->
	gen_statem:cast(Fsm, {nrf_update, ReplyInfo}).

-spec nrf_release_reply(ReplyInfo, Fsm) -> ok
	when
		ReplyInfo :: {RequestId, Result} | {RequestId, {error, Reason}},
		RequestId :: reference(),
		Result :: {httpc:status_line(), httpc:headers(), Body},
		Body :: binary(),
		Reason :: term(),
		Fsm :: pid().
%% @doc Handle sending a reply to {@link nrf_release/1}.
%% @private
nrf_release_reply(ReplyInfo, Fsm) ->
	gen_statem:cast(Fsm, {nrf_release, ReplyInfo}).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec nrf_start(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {next_state, exception, Data}.
%% @doc Start rating a session.
nrf_start(#statedata{imsi = IMSI, msisdn = MSISDN,
		called = CalledNumber, nrf_profile = Profile,
		nrf_uri = URI} = Data) ->
	Now = erlang:system_time(millisecond),
	MFA = {?MODULE, nrf_start_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Sequence = ets:update_counter(counters, nrf_seq, 1),
	ServiceContextId = "32276@3gpp.org",
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["imsi-" ++ IMSI, "msisdn-" ++ MSISDN],
			"serviceRating" => [#{"serviceContextId" => ServiceContextId,
					"destinationId" => [#{"destinationIdType" => "DN",
							"destinationIdData" => CalledNumber}],
					"requestSubType" => "RESERVE"}]},
	Body = zj:encode(JSON),
	Request = {URI ++ "/ratingdata", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{nrf_reqid = RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			{next_state, exception, Data};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			{next_state, exception, Data}
	end.

-spec nrf_update(Consumed, Data) -> Result
	when
		Consumed :: non_neg_integer(),
		Data ::  statedata(),
		Result :: {keep_state, Data} | {next_state, exception, Data}.
%% @doc Interim update during a rating session.
nrf_update(Consumed, #statedata{imsi = IMSI, msisdn = MSISDN,
		called = CalledNumber, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data)
		when is_list(Location) ->
	Now = erlang:system_time(millisecond),
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Sequence = ets:update_counter(counters, nrf_seq, 1),
	ServiceContextId = "32276@3gpp.org",
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["imsi-" ++ IMSI, "msisdn-" ++ MSISDN],
			"serviceRating" => [#{"serviceContextId" => ServiceContextId,
					"destinationId" => [#{"destinationIdType" => "DN",
							"destinationIdData" => CalledNumber}],
					"consumedUnit" => #{"time" => Consumed},
					"requestSubType" => "DEBIT"},
					#{"serviceContextId" => ServiceContextId,
					"destinationId" => [#{"destinationIdType" => "DN",
							"destinationIdData" => CalledNumber}],
					"requestSubType" => "RESERVE"}]},
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/update", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{nrf_reqid = RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_location = undefined},
			{next_state, exception, NewData};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_location = undefined},
			{next_state, exception, NewData}
	end.

-spec nrf_release(Consumed, Data) -> Result
	when
		Consumed :: non_neg_integer(),
		Data ::  statedata(),
		Result :: {keep_state, Data} | {next_state, exception, Data}.
%% @doc Final update to release a rating session.
nrf_release(Consumed, #statedata{imsi = IMSI, msisdn = MSISDN,
		called = CalledNumber, nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location,
		did = DialogueID, iid = IID, cco = CCO} = Data)
		when is_list(Location) ->
	Now = erlang:system_time(millisecond),
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Sequence = ets:update_counter(counters, nrf_seq, 1),
	ServiceContextId = "32276@3gpp.org",
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["imsi-" ++ IMSI, "msisdn-" ++ MSISDN],
			"serviceRating" => [#{"serviceContextId" => ServiceContextId,
					"destinationId" => [#{"destinationIdType" => "DN",
							"destinationIdData" => CalledNumber}],
					"consumedUnit" => #{"time" => Consumed},
					"requestSubType" => "DEBIT"}]},
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/release", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{nrf_reqid = RequestId},
			{keep_state, NewData};
		{error, Reason} ->
			case Reason of
				{failed_connect, _} ->
					?LOG_WARNING([{?MODULE, nrf_start}, {error, Reason},
							{profile, Profile}, {uri, URI}, {slpi, self()}]);
				_ ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{profile, Profile}, {uri, URI}, {slpi, self()}])
			end,
			NewIID = IID + 1,
			NewData = Data#statedata{nrf_location = undefined, iid = NewIID},
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-gsmSSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = NewIID, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, null, NewData}
	end.

