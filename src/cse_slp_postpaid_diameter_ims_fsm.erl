%%% cse_slp_postpaid_diameter_ims_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2024 SigScale Global Inc.
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
%%% 	module implements a Service Logic Processing Program (SLP)
%%% 	for DIAMETER Rf application within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This Service Logic Program (SLP) implements a 3GPP Charging Data
%%% 	Function (CDF) interfacing with a Charging Trigger Function across
%%% 	the Rf interface.
%%%
%%% 	This SLP specifically handles IP Multimedia Subsystem (IMS) voice
%%% 	service usage with `Service-Context-Id' of `32260@3gpp.org', and
%%% 	Circuit Switched (CS) Voice Call Service (VCS) (through a proxy)
%%% 	service usage with `Service-Context-Id' of `32276@3gpp.org'.
%%%
%%% 	== Message Sequence ==
%%% 	The diagram below depicts the normal sequence of exchanged messages:
%%%
%%% 	<img alt="message sequence chart" src="ctf-cdf-msc.svg" />
%%%
%%% 	== State Transitions ==
%%% 	The following diagram depicts the states, and events which drive state
%%% 	transitions, in the OCF finite state machine (FSM):
%%%
%%% 	<img alt="state machine" src="postpaid-diameter-data.svg" />
%%%
-module(cse_slp_postpaid_diameter_ims_fsm).
-copyright('Copyright (c) 2021-2024 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, active/3]).

-include_lib("kernel/include/logger.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("cse_codec.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_rf_application.hrl").

-define(RF_APPLICATION_ID, 3).
-define(IANA_PEN_SigScale, 50386).
-define(IMS_CONTEXTID, "32260@3gpp.org").
-define(VCS_CONTEXTID, "32276@3gpp.org").
-define(SERVICENAME, "Postpaid Voice").
-define(FSM_LOGNAME, postpaid).

-type state() :: null | active.

-type statedata() :: #{start := pos_integer(),
		from => pid(),
		session_id => binary(),
		context => string(),
		service_info => [#'3gpp_rf_Service-Information'{}],
		record_type => pos_integer(),
		record_number =>  integer(),
		ohost => binary(),
		orealm => binary(),
		drealm => binary(),
		imsi => [$0..$9],
		msisdn => string(),
		start_time => calendar:date_time(),
		end_time => calendar:date_time(),
		serving_plmn => [$0..$9],
		duration => non_neg_integer(),
		volume_in => non_neg_integer(),
		volume_out => non_neg_integer(),
		charging_id => 0..4294967295,
		close_cause => 0..4294967295,
		bx_format => csv | ipdr | ber | per | uper | xer,
		bx_codec := {Module :: atom(), Function :: atom()},
		bx_log => atom()}.

%%----------------------------------------------------------------------
%%  The cse_slp_postpaid_diameter_ims_fsm gen_statem callbacks
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
init(Args) when is_list(Args) ->
	Summary = proplists:get_value(bx_summary, Args, true),
	Log = proplists:get_value(bx_log, Args, cdr),
	Logger = proplists:get_value(bx_logger, Args, {ocs_log, log}),
	Data = #{start => erlang:system_time(millisecond),
			data_volume => 0, bx_summary => Summary,
			bx_log => Log, bx_logger => Logger},
	{ok, null, Data}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(enter = _EventType, null = _EventContent, _Data) ->
	keep_state_and_data;
null(enter = _EventType, OldState, Data) ->
	log_fsm(OldState, Data),
	{stop, shutdown};
null({call, _From}, #'3gpp_rf_ACR'{}, Data) ->
	{next_state, active, Data, postpone}.

-spec active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>active</em> state.
%% @private
active(enter, _EventContent, _Data) ->
	keep_state_and_data;
active({call, From},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = SvcContextId,
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum,
				'User-Name' = _UserName,
				'Event-Timestamp' = EventTimestamp,
				'Service-Information' = ServiceInformation}, Data)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD' ->
	TS = case EventTimestamp of
		[DateTime] ->
			DateTime;
		[] ->
			calendar:universal_time()
	end,
	Data1 = Data#{from => From, session_id => SessionId,
			start_time => TS, context => SvcContextId,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			record_number => RecordNum, record_type => RecordType},
	NewData = service_info(ServiceInformation, Data1),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	Reply = diameter_answer(ResultCode, RecordType, RecordNum),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
active({call, From},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = SvcContextId,
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, context := SvcContextId} = Data)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD' ->
	Data1 = Data#{from => From,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			record_number => RecordNum, record_type => RecordType},
	NewData = service_info(ServiceInformation, Data1),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	Reply = diameter_answer(ResultCode, RecordType, RecordNum),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
active({call, From},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = SvcContextId,
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, context := SvcContextId} = Data)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' ->
	Data1 = Data#{from => From,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			record_number => RecordNum, record_type => RecordType},
	NewData = service_info(ServiceInformation, Data1),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	Reply = diameter_answer(ResultCode, RecordType, RecordNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions}.

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

%% @hidden
service_info([#'3gpp_rf_Service-Information'{'IMS-Information' = IMS,
		'Subscription-Id' = SubScriptionId}], Data) ->
	IMSI = imsi(SubScriptionId),
	MSISDN = msisdn(SubScriptionId),
	NewData = Data#{imsi => IMSI, msisdn => MSISDN},
	ims_info(IMS, NewData).

%% @hidden
imsi([#'3gpp_rf_Subscription-Id'{
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
		'Subscription-Id-Data' = IMSI} | _]) ->
	binary_to_list(IMSI);
imsi([_H | T]) ->
	imsi(T);
imsi([]) ->
	undefined.

%% @hidden
msisdn([#'3gpp_rf_Subscription-Id'{
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
		'Subscription-Id-Data' = MSISDN} | _]) ->
	binary_to_list(MSISDN);
msisdn([_H | T]) ->
	msisdn(T);
msisdn([]) ->
	undefined.

%% hidden
ims_info(#'3gpp_rf_IMS-Information'{} = _IMS, Data) ->
	Data;
ims_info(_IMS, Data) ->
	Data.

-spec diameter_answer(ResultCode, RecordType, RecordNum) -> Result
	when
		ResultCode :: pos_integer(),
		RecordType :: pos_integer(),
		RecordNum :: non_neg_integer(),
		Result :: #'3gpp_rf_ACA'{}.
%% @doc Build ACA response.
%% @hidden
diameter_answer(ResultCode, RecordType, RecordNum) ->
	#'3gpp_rf_ACA'{'Acct-Application-Id' = ?RF_APPLICATION_ID,
			'Accounting-Record-Type' = RecordType,
			'Accounting-Record-Number' = RecordNum,
			'Result-Code' = ResultCode}.

-spec log_fsm(OldState, Data) -> ok
	when
		OldState :: atom(),
		Data :: statedata().
%% @doc Write an event to a log.
%% @hidden
log_fsm(State,
		#{start := Start,
		imsi := IMSI,
		msisdn := MSISDN,
		context := Context,
		session_id := SessionId} = _Data) ->
	Stop = erlang:system_time(millisecond),
	Subscriber = #{imsi => IMSI, msisdn => MSISDN},
	Call = #{},
	Network = #{context => Context, session_id => SessionId},
	cse_log:blog(?FSM_LOGNAME, {Start, Stop, ?SERVICENAME,
			State, Subscriber, Call, Network}).

-spec log_cdr(LogName, Data) -> ok
	when
		LogName :: atom(),
		Data :: statedata().
%% @doc Write an event to a log.
%% @hidden
log_cdr(LogName, #{start := Start}) ->
	Stop = erlang:system_time(millisecond),
	State = active,
	cse_log:blog(LogName, {Start, Stop, ?SERVICENAME,
			State, undefined, undefined, undefined}).

