%%% cse_slp_inap_fsm.erl
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
%%% 	module implements a Service Logic Program (SLP) instance for ETSI
%%% 	Intelligent Network Application Part (INAP) within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This Finite State Machine (FSM) includes states and transitions
%%% 	from the INAP originating and terminating basic call state machines
%%% 	(BCSM) given in ITU-T Q.1224.
%%%
%%% 	==O-BCSM==
%%% 	<img alt="o-bcsm state diagram" src="o-bcsm-inap.png" />
%%%
%%% 	==T-BCSM==
%%% 	<img alt="t-bcsm state diagram" src="t-bcsm-inap.png" />
%%%

-module(cse_slp_inap_fsm).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
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
-include_lib("kernel/include/logger.hrl").
-include_lib("inap/include/CS2-operationcodes.hrl").
-include_lib("inap/include/CS2-errorcodes.hrl").
-include("cse_codec.hrl").

-type state() :: null | authorize_attempt | collect_information
		| analyse_information | select_route | select_facility
		| authorize_call_setup | send_call | present_call
		| o_alerting | t_alerting | o_active | t_active
		| o_suspended | t_suspended | disconnect | abandon
		| exception.
-type event_type() :: orig_attempt | term_attempt
		| orig_authorized | term_authorized | collected_info
		| analyzed_info | facility_selected | call_accepted
		| term_seize | answer | suspend | busy | no_answer
		| answer | mid_call | disconnect1 | disconnect2
		| route_failure | orig_denied | present_fail
		| call_rejected | active_fail | suspend_fail.
-type monitor_mode() :: interrupted | notifyAndContinue | transparent.

%% the cse_slp_inap_fsm state data
-record(statedata,
		{dha :: pid() | undefined,
		cco :: pid() | undefined,
		did :: 0..4294967295 | undefined,
		iid = 0 :: 0..127,
		ac :: tuple() | undefined,
		scf :: sccp_codec:party_address() | undefined,
		ssf :: sccp_codec:party_address() | undefined,
		direction :: originating | terminating | undefined,
		called ::  [$0..$9] | undefined,
		calling :: [$0..$9] | undefined,
		call_ref :: binary() | undefined,
		edp :: #{event_type() => monitor_mode()} | undefined,
		call_info :: #{attempt | connect | stop | cause =>
				non_neg_integer() | string() | cse_codec:cause()} | undefined,
		call_start :: string() | undefined,
		charging_start :: string() | undefined,
		consumed = 0 :: non_neg_integer(),
		pending = 0 :: non_neg_integer(),
		nrf_profile :: atom(),
		nrf_uri :: string(),
		nrf_location :: string() | undefined,
		nrf_reqid :: reference() | undefined}).
-type statedata() :: #statedata{}.

-define(Pkgs, 'CS2-SSF-SCF-pkgs-contracts-acs').

%%----------------------------------------------------------------------
%%  The cse_slp_inap_fsm gen_statem callbacks
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
		#statedata{iid = IID, did = DialogueID, ac = AC, dha = DHA})
		when IID < 4 ->
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
	{next_state, auth_attempt, NewData};
null(cast, {'TC', 'L-CANCEL', indication,
		#'TC-L-CANCEL'{dialogueID = DialogueID}} = _EventContent,
		#statedata{did = DialogueID}) ->
	keep_state_and_data;
null(info, {'EXIT', DHA, Reason}, #statedata{dha = DHA} = _Data) ->
	{stop, Reason}.

-spec authorize_attempt(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_attempt</em> state.
%% @private
authorize_attempt(enter, _State, _Data) ->
	keep_state_and_data;
authorize_attempt(cast, {'TC', 'BEGIN', indication,
		#'TC-BEGIN'{appContextName = AC,
		dialogueID = DialogueID, qos = _QoS,
		destAddress = DestAddress, origAddress = OrigAddress,
		componentsPresent = true, userInfo = _UserInfo}} = _EventContent,
		#statedata{did = undefined} = Data) ->
	NewData = Data#statedata{did = DialogueID, ac = AC,
			scf = DestAddress, ssf = OrigAddress},
	{keep_state, NewData};
authorize_attempt(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-initialDP',
		dialogueID = DialogueID, invokeID = _InvokeID,
		lastComponent = true, parameters = Argument}} = _EventContent,
		#statedata{did = DialogueID} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_InitialDPArg', Argument) of
		{ok, #{serviceKey := ServiceKey,
				callingPartysCategory := CallingPartyCategory,
				callingPartyNumber := CallingPartyNumber,
				calledPartyNumber := CalledPartyNumber} = InitialDPArg} ->
			CallingDN = calling_number(CallingPartyNumber),
			CalledDN = called_number(CalledPartyNumber),
			NewData = Data#statedata{calling = CallingDN, called = CalledDN,
					call_start = cse_log:iso8601(erlang:system_time(millisecond))},
			?LOG_INFO([{state, authorize_attempt}, {slpi, self()},
					{service_key, ServiceKey}, {category, CallingPartyCategory},
					{calling, CallingDN}, {called, CalledDN},
					{initalDPArg, InitialDPArg}]),
			{keep_state, NewData};
		{ok, InitialDPArg} ->
			?LOG_WARNING([{state, authorize_attempt},
					{slpi, self()}, {initalDPArg, InitialDPArg}]),
			{keep_state, Data}
	end.

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
analyse_information(enter, _State, _Data) ->
	keep_state_and_data;
analyse_information(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec select_route(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>select_route</em> state.
%% @private
select_route(enter, _State, _Data) ->
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
select_facility(enter, _State, _Data) ->
	keep_state_and_data;
select_facility(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec authorize_call_setup(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_call_setup</em> state.
%% @private
authorize_call_setup(enter, _State, _Data) ->
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
send_call(enter, _State, _Data) ->
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
present_call(enter, _State, _Data) ->
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
o_alerting(enter, _State, _Data) ->
	keep_state_and_data;
o_alerting(_Event, _EventContent, _Data) ->
	keep_state_and_data.

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
t_alerting(_Event, _EventContent, _Data) ->
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
o_active(_Event, _EventContent, _Data) ->
	keep_state_and_data.

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
t_active(_Event, _EventContent, _Data) ->
	keep_state_and_data.

-spec o_suspended(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>o_suspended</em> state.
%% @private
o_suspended(enter, _State, _Data) ->
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
t_suspended(enter, _State, _Data) ->
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
abandon(enter, _State, _Data) ->
	keep_state_and_data;
abandon(_Event, _EventContent, _Data) ->
	keep_state_and_data.

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
disconnect(_Event, _EventContent, _Data) ->
	keep_state_and_data.

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
exception(_Event, _EventContent, _Data) ->
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
nrf_start(#statedata{call_start = CallStart,
		charging_start = ChargingStart} = Data)
		when is_list(CallStart), is_list(ChargingStart) ->
	nrf_start1(#{"startTime" => CallStart,
			"startOfCharging" => ChargingStart}, Data);
nrf_start(#statedata{call_start = CallStart} = Data)
		when is_list(CallStart) ->
	nrf_start1(#{"startTime" => CallStart}, Data).
%% @hidden
nrf_start1(ServiceInformation,
		#statedata{direction = originating, called = CalledNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"destinationId" => [#{"destinationIdType" => "DN",
					"destinationIdData" => CalledNumber}],
			"serviceInformation" => ServiceInformation,
			"requestSubType" => "RESERVE"},
	nrf_start2(ServiceRating, Data);
nrf_start1(ServiceInformation,
		#statedata{direction = terminating, calling = CallingNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"originationId" => [#{"originationIdType" => "DN",
					"originationIdData" => CallingNumber}],
			"serviceInformation" => ServiceInformation,
			"requestSubType" => "RESERVE"},
	nrf_start2(ServiceRating, Data).
%% @hidden
nrf_start2(ServiceRating,
		#statedata{direction = originating, calling = CallingNumber} = Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CallingNumber],
			"serviceRating" => [ServiceRating]},
	nrf_start3(JSON, Data);
nrf_start2(ServiceRating,
		#statedata{direction = terminating, called = CalledNumber} = Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => ["msisdn-" ++ CalledNumber],
			"serviceRating" => [ServiceRating]},
	nrf_start3(JSON, Data).
%% @hidden
nrf_start3(JSON, #statedata{nrf_profile = Profile, nrf_uri = URI} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
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
nrf_update(Consumed, #statedata{call_start = CallStart,
		charging_start = ChargingStart} = Data)
		when is_list(CallStart), is_list(ChargingStart) ->
	nrf_update1(Consumed, #{"startTime" => CallStart,
			"startOfCharging" => ChargingStart}, Data);
nrf_update(Consumed, #statedata{call_start = CallStart} = Data)
		when is_list(CallStart) ->
	nrf_update1(Consumed, #{"startTime" => CallStart}, Data).
%% @hidden
nrf_update1(Consumed, ServiceInformation,
		#statedata{direction = originating, called = CalledNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"destinationId" => [#{"destinationIdType" => "DN",
					"destinationIdData" => CalledNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_update2(Consumed, ServiceRating, Data);
nrf_update1(Consumed, ServiceInformation,
		#statedata{direction = terminating, calling = CallingNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"originationId" => [#{"originationIdType" => "DN",
					"originationIdData" => CallingNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_update2(Consumed, ServiceRating, Data).
%% @hidden
nrf_update2(Consumed, ServiceRating,
		#statedata{direction = originating, calling = CallingNumber} = Data)
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
		#statedata{direction = terminating, called = CalledNumber} = Data)
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
nrf_update3(JSON, #statedata{nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/update", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{nrf_reqid = RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_location = undefined},
			{next_state, exception, NewData};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			NewData = Data#statedata{nrf_location = undefined},
			{next_state, exception, NewData}
	end.

-spec nrf_release(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {next_state, exception, Data}.
%% @doc Final update to release a rating session.
nrf_release(#statedata{call_start = CallStart,
		charging_start = ChargingStart} = Data)
		when is_list(CallStart), is_list(ChargingStart) ->
	nrf_release1(#{"startTime" => CallStart,
			"startOfCharging" => ChargingStart}, Data);
nrf_release(#statedata{call_start = CallStart} = Data)
		when is_list(CallStart) ->
	nrf_release1(#{"startTime" => CallStart}, Data).
%% @hidden
nrf_release1(SI, #statedata{call_info = #{stop := DateTime}} = Data) ->
	nrf_release2(SI#{"stopTime" => DateTime}, Data);
nrf_release1(SI, Data) ->
	nrf_release2(SI, Data).
%% @hidden
nrf_release2(SI, #statedata{call_info = #{cause := Cause}} = Data) ->
	case Cause of
		#{value := Value, location := Location, diagnostic := Diagnostic} ->
			IsupCause = #{"causeValue" => Value,
					"causeLocation" => atom_to_list(Location),
					"causeDiagnostics" => base64:encode(Diagnostic)},
			nrf_release3(SI#{"isupCause" => IsupCause}, Data);
		#{value := Value, location := Location} ->
			IsupCause = #{"causeValue" => Value,
					"causeLocation" => atom_to_list(Location)},
			nrf_release3(SI#{"isupCause" => IsupCause}, Data)
	end;
nrf_release2(SI, Data) ->
	nrf_release3(SI, Data).
%% @hidden
nrf_release3(ServiceInformation,
		#statedata{direction = originating, called = CalledNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"destinationId" => [#{"destinationIdType" => "DN",
					"destinationIdData" => CalledNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_release4(ServiceRating, Data);
nrf_release3(ServiceInformation,
		#statedata{direction = terminating, calling = CallingNumber} = Data) ->
	ServiceContextId = "32276@3gpp.org",
	ServiceRating = #{"serviceContextId" => ServiceContextId,
			"originationId" => [#{"originationIdType" => "DN",
					"originationIdData" => CallingNumber}],
			"serviceInformation" => ServiceInformation},
	nrf_release4(ServiceRating, Data).
%% @hidden
nrf_release4(ServiceRating,
		#statedata{direction = originating, calling = CallingNumber,
      pending = Consumed} = Data) ->
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
		#statedata{direction = terminating, called = CalledNumber,
      pending = Consumed} = Data) ->
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
nrf_release5(JSON, #statedata{nrf_profile = Profile,
		nrf_uri = URI, nrf_location = Location} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/release", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#statedata{nrf_reqid = RequestId,
					nrf_location = undefined, pending = 0},
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
			NewData = Data#statedata{nrf_location = undefined},
			{next_state, null, NewData}
	end.

-spec calling_number(Address) -> Number
	when
		Address :: binary() | asn1_NOVALUE,
		Number :: string() | undefined.
%% @doc Convert Calling Party Address to E.164 string.
%% @hidden
calling_number(Address) when is_binary(Address) ->
	#calling_party{nai = 4, npi = 1,
			address = A} = cse_codec:calling_party(Address),
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

