%%% cse_slp_prepaid_inap_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
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
%%% @reference <a href="https://www.etsi.org/deliver/etsi_i_ets/300300_300399/30037401/01_60/ets_30037401e01p.pdf">
%%% 	ETS 300 374-1</a> Core Intelligent Network Application Protocol (INAP);
%%% 	Capability Set 1 (CS1)
%%% @reference <a href="https://www.etsi.org/deliver/etsi_en/301100_301199/30114001/01.03.04_60/en_30114001v010304p.pdf">
%%%	ETSI EN 301 140-1</a> Intelligent Network Application Protocol (INAP);
%%% 	Capability Set 2 (CS2)
%%% @reference <a href="https://www.itu.int/rec/T-REC-Q.1224-199709-I">Q.1224</a>
%%% 	Distributed Functional Plane for Intelligent Network Capability Set 2
%%%
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements a Service Logic Processing Program (SLP)
%%% 	for ETSI Intelligent Network Application Part (INAP) within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This Finite State Machine (FSM) includes states and transitions
%%% 	from the INAP originating and terminating basic call state machines
%%% 	(BCSM) given in ITU-T Q.1224.
%%%
%%% 	==O-BCSM==
%%% 	<img alt="o-bcsm state diagram" src="o-bcsm-inap.svg" />
%%%
%%% 	==T-BCSM==
%%% 	<img alt="t-bcsm state diagram" src="t-bcsm-inap.svg" />
%%%
%%% 	This module is not intended to be started directly but rather
%%% 	pushed onto the callback stack of the
%%% 	{@link //cse/cse_slp_inap_fsm. cse_slp_inap_fsm}
%%% 	{@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module which handles initialization, dialog `BEGIN' and the
%%% 	first `Invoke' with `InitialDP'.  The Service Key is used to
%%% 	lookup the SLP implementation module (this) and push it onto
%%% 	the callback stack.
%%%
-module(cse_slp_prepaid_inap_fsm).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, authorize_attempt/3, collect_information/3,
		analyse_information/3, select_route/3, select_facility/3,
		authorize_call_setup/3, send_call/3, present_call/3,
		o_alerting/3, t_alerting/3, o_active/3, t_active/3,
		o_suspended/3, t_suspended/3, disconnect/3, abandon/3,
		exception/3]).
%% export the private api
-export([nrf_start_reply/2, nrf_update_reply/2, nrf_release_reply/2]).

-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("inap/include/CS2-operationcodes.hrl").
-include_lib("inap/include/CS2-errorcodes.hrl").
-include("cse_codec.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: null | authorize_attempt | collect_information
		| analyse_information | select_route | select_facility
		| authorize_call_setup | send_call | present_call
		| o_alerting | t_alerting | o_active | t_active
		| o_suspended | t_suspended | disconnect | abandon
		| exception.
-type event_type() :: collected_info | analysed_info | route_fail
		| busy | no_answer | answer | mid_call | disconnect1 | disconnect2
		| abandon | term_attempt.
-type monitor_mode() :: interrupted | notifyAndContinue | transparent.

-type statedata() :: #{dha => pid() | undefined,
		cco => pid() | undefined,
		did => 0..4294967295 | undefined,
		iid => 0..127,
		ac => tuple() | undefined,
		tr_state => idle | init_sent | init_received | active,
		scf => sccp_codec:party_address() | undefined,
		ssf => sccp_codec:party_address() | undefined,
		direction => originating | terminating | undefined,
		called =>  [$0..$9] | undefined,
		calling => [$0..$9] | undefined,
		call_ref => binary() | undefined,
		edp => #{event_type() => monitor_mode()} | undefined,
		call_info => #{attempt | connect | stop | cause =>
				non_neg_integer() | string() | cse_codec:cause()} | undefined,
		call_start => string() | undefined,
		charging_start => string() | undefined,
		consumed => non_neg_integer(),
		pending => non_neg_integer(),
		nrf_profile => atom(),
		nrf_uri => string(),
		nrf_location => string() | undefined,
		nrf_reqid => reference() | undefined}.

-define(Pkgs, 'CS2-SSF-SCF-pkgs-contracts-acs').
-define('leg1', <<1>>).
-define('leg2', <<2>>).

%%----------------------------------------------------------------------
%%  The cse_slp_prepaid_inap_fsm gen_statem callbacks
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
	ignore.

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
null(enter, _EventContent,
		#{tr_state := active, did := DialogueID, dha := DHA} = Data) ->
	End = #'TC-END'{dialogueID = DialogueID,
			qos = {true, true}, termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	NewData = Data#{tr_state => idle},
	{keep_state, NewData};
null(enter, _EventContent,
		#{tr_state := init_received, did := DialogueID,
				ac := AC, dha := DHA} = Data) ->
	End = #'TC-END'{dialogueID = DialogueID,
			appContextName = AC, qos = {true, true},
			termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	NewData = Data#{tr_state => idle},
	{keep_state, NewData};
null(internal, {#'TC-INVOKE'{operation = ?'opcode-initialDP',
				dialogueID = DialogueID},
				#{eventTypeBCSM := analysedInformation}} = EventContent,
		#{did := DialogueID} = Data) ->
	{ok, Profile} = application:get_env(nrf_profile),
	{ok, URI} = application:get_env(nrf_uri),
	NewData = Data#{iid => 0, pending => 0, consumed => 0,
			nrf_profile => Profile, nrf_uri => URI},
	Actions = [{next_event, internal, EventContent}],
	{next_state, analyse_information, NewData, Actions};
null(internal, {#'TC-INVOKE'{operation = ?'opcode-initialDP',
				dialogueID = DialogueID},
				#{eventTypeBCSM := termAttemptAuthorized}} = EventContent,
		#{did := DialogueID} = Data) ->
	{ok, Profile} = application:get_env(nrf_profile),
	{ok, URI} = application:get_env(nrf_uri),
	NewData = Data#{iid => 0, pending => 0, consumed => 0,
			nrf_profile => Profile, nrf_uri => URI},
	Actions = [{next_event, internal, EventContent}],
	{next_state, select_facility, NewData, Actions};
null(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
null(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec authorize_attempt(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_attempt</em> state.
%% @private
authorize_attempt(enter, _EventContent, _Data) ->
	keep_state_and_data;
authorize_attempt(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec collect_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>collect_information</em> state.
%% @private
collect_information(enter, _EventContent, _Data) ->
	keep_state_and_data;
collect_information(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec analyse_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>analyse_information</em> state.
%% @private
analyse_information(enter, _EventContent, _Data) ->
	keep_state_and_data;
analyse_information(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
analyse_information(internal, {#'TC-INVOKE'{operation = ?'opcode-initialDP',
		dialogueID = DialogueID, invokeID = _InvokeID, lastComponent = true},
		#{eventTypeBCSM := analysedInformation = EventTypeBCSM,
				serviceKey := ServiceKey,
				callingPartysCategory := CallingPartyCategory,
				callingPartyNumber := CallingPartyNumber,
				calledPartyNumber := CalledPartyNumber} = InitialDPArg},
		#{did := DialogueID} = Data) ->
	CallingDN = calling_number(CallingPartyNumber),
	CalledDN = called_number(CalledPartyNumber),
?LOG_INFO([{state, analyse_information}, {slpi, self()}, {service_key, ServiceKey}, {event, EventTypeBCSM}, {category, CallingPartyCategory}, {calling, CallingDN}, {called, CalledDN}, {initalDPArg, InitialDPArg}]),
	NewData = Data#{direction => originating,
			calling => CallingDN, called => CalledDN,
			call_start => cse_log:iso8601(erlang:system_time(millisecond))},
	nrf_start(NewData);
analyse_information(cast, {nrf_start,
		{RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#{direction := originating, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI,  edp := EDP,
				did := DialogueID, iid := IID, dha := DHA,
				cco := CCO, scf := SCF, ac := AC} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := [#{"resultCode" := "SUCCESS",
				"grantedUnit" := #{"time" := GrantedTime}}]}},
				{_, Location}} when is_list(Location) ->
			Data1 = maps:remove(nrf_reqid, Data),
			Data2 = maps:remove(nrf_location, Data1),
			NewData = Data2#{iid => IID + 4,
					call_info => #{}, tr_state => active},
			BCSMEvents = [#{eventTypeBCSM => routeSelectFailure,
							monitorMode => map_get(route_fail, EDP)},
					#{eventTypeBCSM => oCalledPartyBusy,
							monitorMode => map_get(busy, EDP)},
					#{eventTypeBCSM => oNoAnswer,
							monitorMode => map_get(no_answer, EDP)},
					#{eventTypeBCSM => oAbandon,
							monitorMode => map_get(abandon, EDP)},
					#{eventTypeBCSM => oAnswer,
							monitorMode => map_get(answer, EDP)},
					#{eventTypeBCSM => oDisconnect,
							monitorMode => map_get(disconnect1, EDP),
							legID => {sendingSideID, ?leg1}},
					#{eventTypeBCSM => oDisconnect,
							monitorMode => map_get(disconnect2, EDP),
							legID => {sendingSideID, ?leg2}}],
			{ok, RequestReportBCSMEventArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_RequestReportBCSMEventArg',
					#{bcsmEvents => BCSMEvents}),
			Invoke1 = #'TC-INVOKE'{operation = ?'opcode-requestReportBCSMEvent',
					invokeID = IID + 1, dialogueID = DialogueID, class = 2,
					parameters = RequestReportBCSMEventArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke1}),
			{ok, CallInformationRequestArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_CallInformationRequestArg',
					#{requestedInformationTypeList => [callStopTime, releaseCause]}),
			Invoke2 = #'TC-INVOKE'{operation = ?'opcode-callInformationRequest',
					invokeID = IID + 2, dialogueID = DialogueID, class = 2,
					parameters = CallInformationRequestArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke2}),
			{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_ApplyChargingArg',
					#{aChBillingChargingCharacteristics => <<0>>,
					sendCalculationToSCPIndication => true,
					partyToCharge => {sendingSideID, ?leg1}}),
			Invoke3 = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
					invokeID = IID + 3, dialogueID = DialogueID, class = 2,
					parameters = ApplyChargingArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke3}),
			Invoke4 = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = IID + 4, dialogueID = DialogueID, class = 4},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke4}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true}, origAddress = SCF},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, o_alerting, NewData};
		{{ok, #{"serviceRating" := [#{"resultCode" := _}]}}, {_, Location}}
				when is_list(Location) ->
			NewIID = IID + 1,
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{nrf_location => Location, iid => NewIID},
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = NewIID, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, NewData, 0};
		{{ok, JSON}, {_, Location}} when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{nrf_location => Location},
			{next_state, exception, NewData};
		{{error, Partial, Remaining}, {_, Location}} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{nrf_location => Location},
			{next_state, exception, NewData};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {missing, "Location:"},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = maps:remove(nrf_reqid, Data),
			{next_state, exception, NewData}
	end;
analyse_information(cast, {nrf_start,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{nrf_start, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {slpi, self()}]),
	{next_state, exception, NewData};
analyse_information(cast, {nrf_start, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{nrf_start, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {slpi, self()}]),
	{next_state, exception, NewData};
analyse_information(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, analyse_information}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, exception, Data};
analyse_information(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
analyse_information(info, {'EXIT', DHA, Reason},
		#{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec select_route(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>select_route</em> state.
%% @private
select_route(enter, _EventContent, _Data) ->
	keep_state_and_data;
select_route(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec select_facility(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>select_facility</em> state.
%% @private
select_facility(enter, _EventContent, _Data) ->
	keep_state_and_data;
select_facility(internal, {#'TC-INVOKE'{operation = ?'opcode-initialDP',
		dialogueID = DialogueID, invokeID = _InvokeID, lastComponent = true},
		#{eventTypeBCSM := termAttemptAuthorized = EventTypeBCSM,
				serviceKey := ServiceKey,
				callingPartysCategory := CallingPartyCategory,
				callingPartyNumber := CallingPartyNumber,
				calledPartyNumber := CalledPartyNumber} = InitialDPArg},
		#{did := DialogueID} = Data) ->
	CallingDN = calling_number(CallingPartyNumber),
	CalledDN = called_number(CalledPartyNumber),
?LOG_INFO([{state, analyse_information}, {slpi, self()}, {service_key, ServiceKey}, {event, EventTypeBCSM}, {category, CallingPartyCategory}, {calling, CallingDN}, {called, CalledDN}, {initalDPArg, InitialDPArg}]),
	NewData = Data#{direction => terminating,
			calling => CallingDN, called => CalledDN,
			call_start => cse_log:iso8601(erlang:system_time(millisecond))},
	nrf_start(NewData);
select_facility(cast, {nrf_start,
		{RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#{direction := terminating, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI,  edp := EDP,
				did := DialogueID, iid := IID, dha := DHA, cco := CCO,
				scf := SCF, ac := AC} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := [#{"resultCode" := "SUCCESS",
				"grantedUnit" := #{"time" := GrantedTime}}]}},
				{_, Location}} when is_list(Location) ->
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{iid => IID + 4, call_info => #{},
					nrf_location => Location, tr_state => active},
			BCSMEvents = [#{eventTypeBCSM => routeSelectFailure,
							monitorMode => map_get(route_fail, EDP)},
					#{eventTypeBCSM => oCalledPartyBusy,
							monitorMode => map_get(busy, EDP)},
					#{eventTypeBCSM => oNoAnswer,
							monitorMode => map_get(no_answer, EDP)},
					#{eventTypeBCSM => oAbandon,
							monitorMode => map_get(abandon, EDP)},
					#{eventTypeBCSM => oAnswer,
							monitorMode => map_get(answer, EDP)},
					#{eventTypeBCSM => oDisconnect,
							monitorMode => map_get(disconnect1, EDP),
							legID => {sendingSideID, ?leg1}},
					#{eventTypeBCSM => oDisconnect,
							monitorMode => map_get(disconnect2, EDP),
							legID => {sendingSideID, ?leg2}}],
			{ok, RequestReportBCSMEventArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_RequestReportBCSMEventArg',
					#{bcsmEvents => BCSMEvents}),
			Invoke1 = #'TC-INVOKE'{operation = ?'opcode-requestReportBCSMEvent',
					invokeID = IID + 1, dialogueID = DialogueID, class = 2,
					parameters = RequestReportBCSMEventArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke1}),
			{ok, CallInformationRequestArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_CallInformationRequestArg',
					#{requestedInformationTypeList => [callStopTime, releaseCause]}),
			Invoke2 = #'TC-INVOKE'{operation = ?'opcode-callInformationRequest',
					invokeID = IID + 2, dialogueID = DialogueID, class = 2,
					parameters = CallInformationRequestArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke2}),
			{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_ApplyChargingArg',
					#{aChBillingChargingCharacteristics => <<0>>,
					sendCalculationToSCPIndication => true,
					partyToCharge => {sendingSideID, ?leg2}}),
			Invoke3 = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
					invokeID = IID + 3, dialogueID = DialogueID, class = 2,
					parameters = ApplyChargingArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke3}),
			Invoke4 = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = IID + 4, dialogueID = DialogueID, class = 4},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke4}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true}, origAddress = SCF},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, t_alerting, NewData};
		{{ok, #{"serviceRating" := [#{"resultCode" := _}]}}, {_, Location}}
				when is_list(Location) ->
			NewIID = IID + 1,
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{nrf_location => Location, iid => NewIID},
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSSF-SCF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = NewIID, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, NewData, 0};
		{{ok, JSON}, {_, Location}} when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{nrf_location => Location},
			{next_state, exception, NewData};
		{{error, Partial, Remaining}, {_, Location}} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{nrf_location => Location},
			{next_state, exception, NewData};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {missing, "Location:"},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = maps:remove(nrf_reqid, Data),
			{next_state, exception, NewData}
	end;
select_facility(cast, {nrf_start,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{nrf_start, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {slpi, self()}]),
	{next_state, exception, NewData};
select_facility(cast, {nrf_start, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{nrf_start, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {slpi, self()}]),
	{next_state, exception, NewData};
select_facility(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, analyse_information}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, exception, Data};
select_facility(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
select_facility(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec authorize_call_setup(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_call_setup</em> state.
%% @private
authorize_call_setup(enter, _EventContent, _Data) ->
	keep_state_and_data;
authorize_call_setup(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec send_call(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>send_call</em> state.
%% @private
send_call(enter, _EventContent, _Data) ->
	keep_state_and_data;
send_call(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec present_call(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>present_call</em> state.
%% @private
present_call(enter, _EventContent, _Data) ->
	keep_state_and_data;
present_call(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec o_alerting(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_alerting</em> state.
%% @private
o_alerting(enter, _EventContent, _Data) ->
	keep_state_and_data;
o_alerting(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
o_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, edp := EDP, iid := IID,
				dha := DHA, cco := CCO} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #{eventTypeBCSM := routeSelectFailure}}
				when map_get(route_fail, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := routeSelectFailure}} ->
			{next_state, exception, Data};
		{ok, #{eventTypeBCSM := oAbandon}}
				when map_get(abandon, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, abandon, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := oAbandon}} ->
			{next_state, abandon, Data};
		{ok, #{eventTypeBCSM := oNoAnswer}}
				when map_get(no_answer, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := oNoAnswer}} ->
			{next_state, exception, Data};
		{ok, #{eventTypeBCSM := oCalledPartyBusy}}
				when map_get(busy, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := oCalledPartyBusy}} ->
			{next_state, exception, Data};
		{ok, #{eventTypeBCSM := oAnswer}}
				when map_get(answer, EDP) == interrupted ->
			Invoke = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID, qos = {true, true}},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, o_active, Data#{iid => IID + 1, tr_state => active}};
		{ok, #{eventTypeBCSM := oAnswer}} ->
			{next_state, o_active, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
o_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
?LOG_INFO([{state, o_alerting}, {slpi, self()}, {chargingResultArg, ChargingResultArg}]),
			keep_state_and_data;
		{error, Reason} ->
			{stop, Reason}
	end;
o_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
?LOG_INFO([{state, o_alerting}, {slpi, self()}, {requestedInformationList, CallInfo}]),
			{keep_state, call_info(CallInfo, Data)};
		{error, Reason} ->
			{stop, Reason}
	end;
o_alerting(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
o_alerting(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{next_state, exception, Data, 0};
o_alerting(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, o_alerting}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, exception, Data};
o_alerting(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec t_alerting(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>t_alerting</em> state.
%% @private
t_alerting(enter, _EventContent, _Data) ->
	keep_state_and_data;
t_alerting(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
t_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, edp := EDP, iid := IID,
				dha := DHA, cco := CCO} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #{eventTypeBCSM := tAbandon}}
				when map_get(abandon, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, abandon, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := tAbandon}} ->
			{next_state, abandon, Data};
		{ok, #{eventTypeBCSM := tNoAnswer}}
				when map_get(no_answer, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := tNoAnswer}} ->
			{next_state, exception, Data};
		{ok, #{eventTypeBCSM := tBusy}}
				when map_get(busy, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := tBusy}} ->
			{next_state, exception, Data};
		{ok, #{eventTypeBCSM := tAnswer}}
				when map_get(answer, EDP) == interrupted ->
			Invoke = #'TC-INVOKE'{operation = ?'opcode-continue',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			Continue = #'TC-CONTINUE'{dialogueID = DialogueID, qos = {true, true}},
			gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
			{next_state, t_active, Data#{iid => IID + 1, tr_state => active}};
		{ok, #{eventTypeBCSM := tAnswer}} ->
			{next_state, t_active, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
t_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			keep_state_and_data;
		{error, Reason} ->
			{stop, Reason}
	end;
t_alerting(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			{keep_state, call_info(CallInfo, Data)};
		{error, Reason} ->
			{stop, Reason}
	end;
t_alerting(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
t_alerting(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{next_state, exception, Data, 0};
t_alerting(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, t_alerting}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, exception, Data};
t_alerting(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec o_active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_active</em> state.
%% @private
o_active(enter, _EventContent, Data) ->
	StartCharging = cse_log:iso8601(erlang:system_time(millisecond)),
	{keep_state, Data#{charging_start => StartCharging}};
o_active(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
o_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, edp := EDP, iid := IID, cco := CCO} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #{eventTypeBCSM := oDisconnect, legID := {receivingSideID, ?leg1}}}
				when map_get(disconnect1, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, disconnect, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := oDisconnect, legID := {receivingSideID, ?leg2}}}
				when map_get(disconnect2, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, disconnect, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := oDisconnect}} ->
			{next_state, disconnect, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
o_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, consumed := Consumed} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			% @todo Parse network operator specific CallResult
			Time = 0,
			NewData = Data#{consumed => Time},
			nrf_update((Time - Consumed) div 10, NewData);
		{error, Reason} ->
			{stop, Reason}
	end;
o_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			{keep_state, call_info(CallInfo, Data)};
		{error, Reason} ->
			{stop, Reason}
	end;
o_active(cast, {nrf_update,
		{RequestId, {{_, 200, _}, _Headers, Body}}},
		#{nrf_reqid := RequestId, nrf_uri := URI, nrf_profile := Profile,
				nrf_location := Location, did := DialogueID, iid := IID,
				dha := DHA, cco := CCO, scf := SCF} = Data) ->
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
					Data1 = maps:remove(nrf_reqid, Data),
					NewData = Data1#{iid => NewIID, tr_state => active},
					{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ApplyChargingArg',
							#{aChBillingChargingCharacteristics => <<0>>,
							partyToCharge => {sendingSideID, ?leg1}}),
					Invoke = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
							invokeID = NewIID, dialogueID = DialogueID, class = 2,
							parameters = ApplyChargingArg},
					gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
					Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
							qos = {true, true}, origAddress = SCF},
					gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
					{keep_state, NewData};
				Other when is_atom(Other) ->
					?LOG_ERROR([{?MODULE, nrf_update}, {Other, "grantedUnit"},
							{profile, Profile}, {uri, URI}, {location, Location},
							{slpi, self()}, {json, JSON}]),
					NewIID = IID + 1,
					Data1 = maps:remove(nrf_reqid, Data),
					NewData = Data1#{iid := NewIID},
					Cause = #cause{location = local_public, value = 31},
					{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
							{allCallSegments, cse_codec:cause(Cause)}),
					Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
							invokeID = NewIID, dialogueID = DialogueID, class = 4,
							parameters = ReleaseCallArg},
					gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
					{next_state, exception, NewData, 0}
			end;
		{ok, #{"serviceRating" := [#{"resultCode" := _},
				#{"resultCode" := _}]}} ->
			NewIID = IID + 1,
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{iid := NewIID},
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = NewIID, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, NewData, 0};
		{ok, JSON} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			NewData = maps:remove(nrf_reqid, Data),
			{next_state, exception, NewData};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			NewData = maps:remove(nrf_reqid, Data),
			{next_state, exception, NewData}
	end;
o_active(cast, {nrf_update,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile, nrf_uri := URI,
				nrf_location := Location} = Data) ->
	?LOG_WARNING([{nrf_update, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, exception, NewData};
o_active(cast, {nrf_update, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile, nrf_uri := URI,
				nrf_location := Location} = Data) ->
	?LOG_ERROR([{nrf_update, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = maps:remove(nrf_location, Data1),
	{next_state, exception, NewData};
o_active(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
o_active(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{next_state, exception, Data, 0};
o_active(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, o_active}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, exception, Data};
o_active(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec t_active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>t_active</em> state.
%% @private
t_active(enter, _EventContent, Data) ->
	StartCharging = cse_log:iso8601(erlang:system_time(millisecond)),
	{keep_state, Data#{charging_start => StartCharging}};
t_active(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
t_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, edp := EDP, iid := IID, cco := CCO} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #{eventTypeBCSM := tDisconnect, legID := {receivingSideID, ?leg1}}}
				when map_get(disconnect1, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, disconnect, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := tDisconnect, legID := {receivingSideID, ?leg2}}}
				when map_get(disconnect2, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, disconnect, Data#{iid => IID + 1}};
		{ok, #{eventTypeBCSM := tDisconnect}} ->
			{next_state, disconnect, Data};
		{error, Reason} ->
			{stop, Reason}
	end;
t_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, consumed := Consumed} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			% @todo Parse network operator specific CallResult
			Time = 0,
			NewData = Data#{consumed => Time},
			nrf_update((Time - Consumed) div 10, NewData);
		{error, Reason} ->
			{stop, Reason}
	end;
t_active(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			{keep_state, call_info(CallInfo, Data)};
		{error, Reason} ->
			{stop, Reason}
	end;
t_active(cast, {nrf_update,
		{RequestId, {{_, 200, _}, _Headers, Body}}},
		#{nrf_reqid := RequestId, nrf_uri := URI, nrf_profile := Profile,
				nrf_location := Location, did := DialogueID, iid := IID,
				dha := DHA, cco := CCO, scf := SCF} = Data) ->
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
					Data1 = maps:remove(nrf_reqid, Data),
					NewData = Data1#{iid => NewIID, tr_state => active},
					{ok, ApplyChargingArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ApplyChargingArg',
							#{aChBillingChargingCharacteristics => <<0>>,
							partyToCharge => {sendingSideID, ?leg2}}),
					Invoke = #'TC-INVOKE'{operation = ?'opcode-applyCharging',
							invokeID = NewIID, dialogueID = DialogueID, class = 2,
							parameters = ApplyChargingArg},
					gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
					Continue = #'TC-CONTINUE'{dialogueID = DialogueID,
							qos = {true, true}, origAddress = SCF},
					gen_statem:cast(DHA, {'TC', 'CONTINUE', request, Continue}),
					{keep_state, NewData};
				Other when is_atom(Other) ->
					?LOG_ERROR([{?MODULE, nrf_update}, {Other, "grantedUnit"},
							{profile, Profile}, {uri, URI}, {location, Location},
							{slpi, self()}, {json, JSON}]),
					NewIID = IID + 1,
					Data1 = maps:remove(nrf_reqid, Data),
					NewData = Data1#{iid => NewIID},
					Cause = #cause{location = local_public, value = 31},
					{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
							{allCallSegments, cse_codec:cause(Cause)}),
					Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
							invokeID = NewIID, dialogueID = DialogueID, class = 4,
							parameters = ReleaseCallArg},
					gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
					{next_state, exception, NewData, 0}
			end;
		{ok, #{"serviceRating" := [#{"resultCode" := _},
				#{"resultCode" := _}]}} ->
			NewIID = IID + 1,
			Data1 = maps:remove(nrf_reqid, Data),
			NewData = Data1#{iid => NewIID},
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = NewIID, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{next_state, exception, NewData, 0};
		{ok, JSON} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_syntax},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {json, JSON}]),
			NewData = maps:remove(nrf_reqid, Data),
			{next_state, exception, NewData};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{profile, Profile}, {uri, URI}, {location, Location},
					{slpi, self()}, {partial, Partial}, {remaining, Remaining}]),
			NewData = maps:remove(nrf_reqid, Data),
			{next_state, exception, NewData}
	end;
t_active(cast, {nrf_update,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_WARNING([{nrf_update, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, exception, NewData};
t_active(cast, {nrf_update, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_ERROR([{nrf_update, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = maps:remove(nrf_location, Data1),
	{next_state, exception, NewData};
t_active(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
t_active(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{next_state, exception, Data, 0};
t_active(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, t_active}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, exception, Data};
t_active(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec o_suspended(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_suspended</em> state.
%% @private
o_suspended(enter, _EventContent, _Data) ->
	keep_state_and_data;
o_suspended(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec t_suspended(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>t_suspended</em> state.
%% @private
t_suspended(enter, _EventContent, _Data) ->
	keep_state_and_data;
t_suspended(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec abandon(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>abandon</em> state.
%% @private
abandon(enter, _EventContent, #{call_info := #{}} = _Data) ->
	keep_state_and_data;
abandon(enter, _EventContent, _Data) ->
	{keep_state_and_data, 0};
abandon(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
abandon(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			keep_state_and_data;
		{error, Reason} ->
			{stop, Reason}
	end;
abandon(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) when not is_map_key(nrf_location, Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			{next_state, null, call_info(CallInfo, Data)};
		{error, Reason} ->
			{stop, Reason}
	end;
abandon(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			nrf_release(call_info(CallInfo, Data));
		{error, Reason} ->
			{stop, Reason}
	end;
abandon(timeout, _EventContent,
		#{nrf_location := Location} = Data) when is_list(Location) ->
	nrf_release(Data);
abandon(timeout, _EventContent, Data) ->
	{next_state, null, Data};
abandon(cast, {nrf_release,
		{RequestId, {{_Version, 200, _Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
abandon(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_WARNING([{nrf_release, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
abandon(cast, {nrf_release, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_ERROR([{nrf_release, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
abandon(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
abandon(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	nrf_release(Data);
abandon(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, abandon}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, null, Data};
abandon(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec disconnect(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>disconnect</em> state.
%% @private
disconnect(enter, _EventContent, #{call_info := #{}} = _Data) ->
	keep_state_and_data;
disconnect(enter, _EventContent, _Data) ->
	{keep_state_and_data, 0};
disconnect(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = _Data) ->
	keep_state_and_data;
disconnect(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, consumed := Consumed, pending := Pending} = _Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
			keep_state_and_data;
		{error, Reason} ->
			{stop, Reason}
	end;
disconnect(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) when not is_map_key(nrf_location, Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			{next_state, null, call_info(CallInfo, Data)};
		{error, Reason} ->
			{stop, Reason}
	end;
disconnect(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			nrf_release(call_info(CallInfo, Data));
		{error, Reason} ->
			{stop, Reason}
	end;
disconnect(timeout, _EventContent, Data) ->
	nrf_release(Data);
disconnect(cast, {nrf_release,
		{RequestId, {{_Version, 200, _Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
disconnect(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_WARNING([{nrf_release, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
disconnect(cast, {nrf_release, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_ERROR([{nrf_release, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
disconnect(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID}) ->
	keep_state_and_data;
disconnect(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	nrf_release(Data);
disconnect(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, disconnect}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, null, Data};
disconnect(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec exception(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>exception</em> state.
%% @private
exception(enter, _OldState,  _Data)->
	keep_state_and_data;
exception(cast, {'TC', 'CONTINUE', indication,
		#'TC-CONTINUE'{dialogueID = DialogueID,
				componentsPresent = true}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{keep_state, Data, 400};
exception(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-eventReportBCSM',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, edp := EDP, iid := IID, cco := CCO} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_EventReportBCSMArg', Argument) of
		{ok, #{eventTypeBCSM := oDisconnect,
				legID := {receivingSideID, ?leg1}}}
				when map_get(disconnect1, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{keep_state, Data#{iid => IID + 1}, 400};
		{ok, #{eventTypeBCSM := oDisconnect,
				legID := {receivingSideID, ?leg2}}}
				when map_get(disconnect2, EDP) == interrupted ->
			Cause = #cause{location = local_public, value = 31},
			{ok, ReleaseCallArg} = ?Pkgs:encode('GenericSCF-SSF-PDUs_ReleaseCallArg',
					{allCallSegments, cse_codec:cause(Cause)}),
			Invoke = #'TC-INVOKE'{operation = ?'opcode-releaseCall',
					invokeID = IID + 1, dialogueID = DialogueID, class = 4,
					parameters = ReleaseCallArg},
			gen_statem:cast(CCO, {'TC', 'INVOKE', request, Invoke}),
			{keep_state, Data#{iid => IID + 1}, 400};
		{ok, #{eventTypeBCSM := _}} ->
			{keep_state, Data, 400};
		{error, Reason} ->
			{stop, Reason}
	end;
exception(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-applyChargingReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID, pending := Pending, consumed := Consumed} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_ApplyChargingReportArg', Argument) of
		{ok, ChargingResultArg} ->
?LOG_INFO([{state, exception}, {slpi, self()}, {chargingResultArg, ChargingResultArg}]),
			{keep_state, Data, 400};
		{error, Reason} ->
			{stop, Reason}
	end;
exception(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-callInformationReport',
				dialogueID = DialogueID, parameters = Argument}} = _EventContent,
		#{did := DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_CallInformationReportArg', Argument) of
		{ok, #{requestedInformationList := CallInfo}} ->
			nrf_release(call_info(CallInfo, Data));
		{error, Reason} ->
			{stop, Reason}
	end;
exception(timeout, _EventContent,
		#{nrf_location := _Location} = Data) ->
	nrf_release(Data);
exception(timeout, _EventContent, Data) ->
	{next_state, null, Data};
exception(cast, {nrf_release,
		{RequestId, {{_Version, 200, _Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
exception(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{nrf_release, RequestId}, {code, Code}, {reason, Phrase},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	{next_state, null, NewData};
exception(cast, {nrf_release, {RequestId, {error, Reason}}},
		#{nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location} = Data) ->
	?LOG_ERROR([{nrf_release, RequestId}, {error, Reason},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}]),
	NewData = maps:remove(nrf_reqid, Data),
	{next_state, null, NewData};
exception(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{keep_state, Data, 400};
exception(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID, nrf_location := _Location} = Data) ->
	nrf_release(Data);
exception(cast, {'TC', 'END', indication,
		#'TC-END'{dialogueID = DialogueID,
				componentsPresent = false}} = _EventContent,
		#{did := DialogueID} = Data) ->
	{next_state, null, Data};
exception(cast, {'TC', 'U-ERROR', indication,
		#'TC-U-ERROR'{dialogueID = DialogueID, invokeID = InvokeID,
				error = Error, parameters = Parameters}} = _EventContent,
		#{did := DialogueID, ssf := SSF} = Data) ->
	?LOG_WARNING([{'TC', 'U-ERROR'},
			{error, cse_codec:error_code(Error)},
			{parameters, Parameters}, {dialogueID, DialogueID},
			{invokeID, InvokeID}, {slpi, self()},
			{state, exception}, {ssf, sccp_codec:party_address(SSF)}]),
	{next_state, null, Data};
exception(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
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
nrf_start(#{call_start := CallStart,
		charging_start := ChargingStart} = Data)
		when is_list(CallStart), is_list(ChargingStart) ->
	nrf_start1(#{"startTime" => CallStart,
			"startOfCharging" => ChargingStart}, Data);
nrf_start(#{call_start := CallStart} = Data)
		when is_list(CallStart) ->
	nrf_start1(#{"startTime" => CallStart}, Data).
%% @hidden
nrf_start1(ServiceInformation,
		#{direction := originating, called := CalledNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"destinationId" => [#{"destinationIdType" => "DN",
					"destinationIdData" => CalledNumber}],
			"serviceInformation" => ServiceInformation,
			"requestSubType" => "RESERVE"},
	nrf_start2(ServiceRating, Data);
nrf_start1(ServiceInformation,
		#{direction := terminating, calling := CallingNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"originationId" => [#{"originationIdType" => "DN",
					"originationIdData" => CallingNumber}],
			"serviceInformation" => ServiceInformation,
			"requestSubType" => "RESERVE"},
	nrf_start2(ServiceRating, Data).
%% @hidden
nrf_start2(ServiceRating,
		#{direction := originating, calling := CallingNumber} = Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CallingNumber],
			"serviceRating" => [ServiceRating]},
	nrf_start3(JSON, Data);
nrf_start2(ServiceRating,
		#{direction := terminating, called := CalledNumber} = Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CalledNumber],
			"serviceRating" => [ServiceRating]},
	nrf_start3(JSON, Data).
%% @hidden
nrf_start3(JSON, #{nrf_profile := Profile, nrf_uri := URI} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"Authorization", "Basic YWRtaW46b2NzMTIzNDU2Nzg="},
			{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ "/ratingdata", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_reqid => RequestId},
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
nrf_update(Consumed, #{call_start := CallStart,
		charging_start := ChargingStart} = Data)
		when is_list(CallStart), is_list(ChargingStart) ->
	nrf_update1(Consumed, #{"startTime" => CallStart,
			"startOfCharging" => ChargingStart}, Data);
nrf_update(Consumed, #{call_start := CallStart} = Data)
		when is_list(CallStart) ->
	nrf_update1(Consumed, #{"startTime" => CallStart}, Data).
%% @hidden
nrf_update1(Consumed, ServiceInformation,
		#{direction := originating, called := CalledNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"destinationId" => [#{"destinationIdType" => "DN",
					"destinationIdData" => CalledNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_update2(Consumed, ServiceRating, Data);
nrf_update1(Consumed, ServiceInformation,
		#{direction := terminating, calling := CallingNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"originationId" => [#{"originationIdType" => "DN",
					"originationIdData" => CallingNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_update2(Consumed, ServiceRating, Data).
%% @hidden
nrf_update2(Consumed, ServiceRating,
		#{direction := originating, calling := CallingNumber} = Data)
		when is_integer(Consumed), Consumed >= 0 ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	Debit = ServiceRating#{"consumedUnit" => #{"time" => Consumed},
			"requestSubType" => "DEBIT"},
	Reserve = ServiceRating#{"requestSubType" => "RESERVE"},
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CallingNumber],
			"serviceRating" => [Debit, Reserve]},
	nrf_update3(JSON, Data);
nrf_update2(Consumed, ServiceRating,
		#{direction := terminating, called := CalledNumber} = Data)
		when is_integer(Consumed), Consumed >= 0 ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	Debit = ServiceRating#{"consumedUnit" => #{"time" => Consumed},
			"requestSubType" => "DEBIT"},
	Reserve = ServiceRating#{"requestSubType" => "RESERVE"},
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CalledNumber],
			"serviceRating" => [Debit, Reserve]},
	nrf_update3(JSON, Data).
%% @hidden
nrf_update3(JSON, #{nrf_profile := Profile,
		nrf_uri := URI, nrf_location := Location} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"Authorization", "Basic YWRtaW46b2NzMTIzNDU2Nzg="},
			{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/update", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_reqid => RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = maps:remove(nrf_location, Data),
			{next_state, exception, NewData};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = maps:remove(nrf_location, Data),
			{next_state, exception, NewData}
	end.

-spec nrf_release(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {next_state, exception, Data}.
%% @doc Final update to release a rating session.
nrf_release(#{call_start := CallStart,
		charging_start := ChargingStart} = Data)
		when is_list(CallStart), is_list(ChargingStart) ->
	nrf_release1(#{"startTime" => CallStart,
			"startOfCharging" => ChargingStart}, Data);
nrf_release(#{call_start := CallStart} = Data)
		when is_list(CallStart) ->
	nrf_release1(#{"startTime" => CallStart}, Data).
%% @hidden
nrf_release1(SI, #{call_info := #{stop := DateTime}} = Data) ->
	nrf_release2(SI#{"stopTime" => DateTime}, Data);
nrf_release1(SI, Data) ->
	nrf_release2(SI, Data).
%% @hidden
nrf_release2(SI, #{call_info := #{cause := Cause}} = Data) ->
	case Cause of
		#cause{value = Value, location = Location, diagnostic = undefined} ->
			IsupCause = #{"causeValue" => Value,
					"causeLocation" => atom_to_list(Location)},
			nrf_release3(SI#{"isupCause" => IsupCause}, Data);
		#cause{value = Value, location = Location, diagnostic = Diagnostic} ->
			IsupCause = #{"causeValue" => Value,
					"causeLocation" => atom_to_list(Location),
					"causeDiagnostics" => base64:encode(Diagnostic)},
			nrf_release3(SI#{"isupCause" => IsupCause}, Data)
	end;
nrf_release2(SI, Data) ->
	nrf_release3(SI, Data).
%% @hidden
nrf_release3(ServiceInformation,
		#{direction := originating, called := CalledNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"destinationId" => [#{"destinationIdType" => "DN",
					"destinationIdData" => CalledNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_release4(ServiceRating, Data);
nrf_release3(ServiceInformation,
		#{direction := terminating, calling := CallingNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"originationId" => [#{"originationIdType" => "DN",
					"originationIdData" => CallingNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_release4(ServiceRating, Data).
%% @hidden
nrf_release4(ServiceRating,
		#{direction := originating, calling := CallingNumber,
      		pending := Consumed} = Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	Debit = ServiceRating#{"consumedUnit" => #{"time" => Consumed},
			"requestSubType" => "DEBIT"},
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CallingNumber],
			"serviceRating" => [Debit]},
	nrf_release5(JSON, Data);
nrf_release4(ServiceRating,
		#{direction := terminating, called := CalledNumber,
      		pending := Consumed} = Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	Debit = ServiceRating#{"consumedUnit" => #{"time" => Consumed},
			"requestSubType" => "DEBIT"},
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CalledNumber],
			"serviceRating" => [Debit]},
	nrf_release5(JSON, Data).
%% @hidden
nrf_release5(JSON, #{nrf_profile := Profile,
		nrf_uri := URI, nrf_location := Location} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"Authorization", "Basic YWRtaW46b2NzMTIzNDU2Nzg="},
			{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/release", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			Data1 = maps:remove(nrf_location, Data),
			NewData = Data1#{nrf_reqid => RequestId, pending => 0},
			{keep_state, NewData};
		{error, Reason} ->
			case Reason of
				{failed_connect, _} ->
					?LOG_WARNING([{?MODULE, nrf_release}, {error, Reason},
							{profile, Profile}, {uri, URI}, {slpi, self()}]);
				_ ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{profile, Profile}, {uri, URI}, {slpi, self()}])
			end,
			NewData = maps:remove(nrf_location, Data),
			{next_state, null, NewData}
	end.

-spec calling_number(Address) -> Number
	when
		Address :: binary() | asn1_NOVALUE,
		Number :: string() | undefined.
%% @doc Convert Calling Party Address to E.164 string.
%% @hidden
calling_number(Address) when is_binary(Address) ->
	#calling_party{address = A} = cse_codec:calling_party(Address),
	lists:flatten([integer_to_list(D) || D <- A]);
calling_number(asn1_NOVALUE) ->
	undefined.

-spec called_number(Address) -> Number
	when
		Address :: binary() | asn1_NOVALUE,
		Number :: string() | undefined.
%% @doc Convert Called Party Address to E.164 string.
%% @hidden
called_number(Address) when is_binary(Address) ->
	#called_party{address = A}
			= cse_codec:called_party(Address),
	lists:flatten([integer_to_list(D) || D <- A]);
called_number(asn1_NOVALUE) ->
	undefined.

-spec call_info(RequestedInformationTypeList, Data) -> Data
	when
		RequestedInformationTypeList :: [map()],
		Data :: statedata().
%% @doc Update state data with call information.
call_info([#{requestedInformationType := callAttemptElapsedTime,
		requestedInformationValue := {callAttemptElapsedTimeValue, Time}}
		| T] = _RequestedInformationTypeList, #{call_info := CallInfo} = Data) ->
	NewData = Data#{call_info => CallInfo#{attempt => Time}},
	call_info(T, NewData);
call_info([#{requestedInformationType := callConnectedElapsedTime,
		requestedInformationValue := {callConnectedElapsedTimeValue, Time}}
		| T] = _RequestedInformationTypeList, #{call_info := CallInfo} = Data) ->
	NewData = Data#{call_info => CallInfo#{connect => Time}},
	call_info(T, NewData);
call_info([#{requestedInformationType := callStopTime,
		requestedInformationValue := {callStopTimeValue, Time}}
		| T] = _RequestedInformationTypeList, #{call_info := CallInfo} = Data) ->
	MilliSeconds = cse_log:date(cse_codec:date_time(Time)),
	NewData = Data#{call_info => CallInfo#{stop => cse_log:iso8601(MilliSeconds)}},
	call_info(T, NewData);
call_info([#{requestedInformationType := releaseCause,
		requestedInformationValue := {releaseCauseValue, Cause}}
		| T] = _RequestedInformationTypeList, #{call_info := CallInfo} = Data) ->
	NewData = Data#{call_info => CallInfo#{cause => cse_codec:cause(Cause)}},
	call_info(T, NewData);
call_info([], Data) ->
	Data.

