%%% cse_slp_postpaid_diameter_ims_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% 	transitions, in the CDF finite state machine (FSM):
%%%
%%% 	<img alt="state machine" src="postpaid-cdf.svg" />
%%%
%%% 	== Configuration ==
%%% 	Extra start arguments supported with
%%% 	{@link //cse/cse:add_context/4. cse:add_context/4} include:
%%% 	<dl>
%%% 		<dt>`interim_interval'</dt>
%%% 			<dd>A value to use for the `Acct-Interim-Interval' AVP
%%% 			in an `Accounting-Answer' (ACA).</dd>
%%% 		<dt>`bx_summary'</dt>
%%% 			<dd>Log only on ACR STOP. (default: `true')</dd>
%%% 		<dt>`bx_log'</dt>
%%% 			<dd>Name of the Bx interface log. (default: `cdr')</dd>
%%% 		<dt>`bx_logger'</dt>
%%% 			<dd>The module and function for logging on the Bx interface.
%%% 					(default: `{cse_log, blog}')</dd>
%%% 		<dt>`bx_codec'</dt>
%%% 			<dd>The module and function for encoding on the Bx interface.
%%% 					(default: `{cse_log_codec_bx, csv}')</dd>
%%% 		<dt>`idle_timeout'</dt>
%%% 			<dd>The idle time after which an SLPI will be shutdown:
%%% 					`{seconds | minutes | hours | days, N :: pos_integer()}'
%%% 					(default: `infinity')</dd>
%%% 	</dl>
%%%
-module(cse_slp_postpaid_diameter_ims_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
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
-define(IDLE_TIMEOUT(Data), {timeout, maps:get(idle, Data), idle}).

-type state() :: null | active.

-type statedata() :: #{start := pos_integer(),
		idle := erlang:timeout(),
		from => pid(),
		session_id => binary(),
		context => string(),
		record_type => pos_integer(),
		record_number => integer(),
		ohost => binary(),
		orealm => binary(),
		drealm => binary(),
		imsi => [$0..$9],
		msisdn => [$0..$9],
		sip_uri => string(),
		start_time => calendar:datetime(),
		end_time => calendar:datetime(),
		serving_plmn => [$0..$9],
		duration => non_neg_integer(),
		volume_in => non_neg_integer(),
		volume_out => non_neg_integer(),
		charging_id => 0..4294967295,
		close_cause => 0..4294967295,
		interim_interval := [pos_integer()],
		bx_summary := boolean(),
		bx_log := atom(),
		bx_logger := {Module :: atom(), Function :: atom()},
		bx_codec := {Module :: atom(), Function :: atom()}}.

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
		Args :: [Property],
		Property :: {interim_interval, pos_integer()}
				| {bx_summary, boolean()}
				| {bx_log, atom()}
				| {bx_logger, {Module, Function}}
				| {bx_codec, {Module, Function}}
				| {idle_timeout, pos_integer()},
		Module :: atom(),
		Function :: atom(),
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
	Logger = proplists:get_value(bx_logger, Args, {cse_log, blog}),
	LogCodec = proplists:get_value(bx_codec, Args, {cse_log_codec_bx, csv}),
	IdleTime = case proplists:get_value(idle_timeout, Args) of
		{days, Days} when is_integer(Days), Days > 0 ->
			Days * 86400000;
		{hours, Hours} when is_integer(Hours), Hours > 0 ->
			Hours * 3600000;
		{minutes, Minutes} when is_integer(Minutes), Minutes > 0 ->
			Minutes * 60000;
		{seconds, Seconds} when is_integer(Seconds), Seconds > 0 ->
			Seconds * 1000;
		_ ->
			infinity
	end,
	Data = #{start => erlang:system_time(millisecond),
			idle => IdleTime,
			volume_in => 0, volume_out => 0, bx_summary => Summary,
			bx_log => Log, bx_logger => Logger, bx_codec => LogCodec},
	NewData = case proplists:get_value(interim_interval, Args) of
		Interval when is_integer(Interval), Interval > 0 ->
			Data#{interim_interval => [Interval]};
		undefined ->
			Data#{interim_interval => []}
	end,
	{ok, null, NewData, ?IDLE_TIMEOUT(Data)}.

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
	catch log_fsm(OldState, Data),
	{stop, shutdown};
null({call, _From}, #'3gpp_rf_ACR'{}, Data) ->
	{next_state, active, Data, postpone};
null(timeout, idle, _Data) ->
	{stop, shutdown}.

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
				'Service-Context-Id' = [SvcContextId],
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum,
				'User-Name' = _UserName,
				'Event-Timestamp' = EventTimestamp,
				'Service-Information' = [ServiceInformation]} = ACR, Data)
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
	ResultCode = case log_cdr(ACR, NewData) of
		ok ->
			?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
		{error, _Reason} ->
			?'DIAMETER_BASE_RESULT-CODE_OUT_OF_SPACE'
	end,
	Reply = diameter_answer(ResultCode, NewData),
	Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
	{keep_state, NewData, Actions};
active({call, From},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = [SvcContextId],
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum,
				'Service-Information' = [ServiceInformation]} = ACR,
		#{session_id := SessionId, context := SvcContextId} = Data)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD' ->
	Data1 = Data#{from => From,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			record_number => RecordNum, record_type => RecordType},
	NewData = service_info(ServiceInformation, Data1),
	ResultCode = case log_cdr(ACR, NewData) of
		ok ->
			?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
		{error, _Reason} ->
			?'DIAMETER_BASE_RESULT-CODE_OUT_OF_SPACE'
	end,
	Reply = diameter_answer(ResultCode, NewData),
	Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
	{keep_state, NewData, Actions};
active({call, From},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = [SvcContextId],
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum,
				'Event-Timestamp' = EventTimestamp,
				'Service-Information' = [ServiceInformation]} = ACR,
		#{session_id := SessionId, context := SvcContextId} = Data)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' ->
	TS = case EventTimestamp of
		[DateTime] ->
			DateTime;
		[] ->
			calendar:universal_time()
	end,
	Data1 = Data#{from => From, end_time => TS,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			record_number => RecordNum, record_type => RecordType},
	NewData = service_info(ServiceInformation, Data1),
	ResultCode = case log_cdr(ACR, NewData) of
		ok ->
			?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
		{error, _Reason} ->
			?'DIAMETER_BASE_RESULT-CODE_OUT_OF_SPACE'
	end,
	Reply = diameter_answer(ResultCode, NewData),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
active(timeout, idle, Data) ->
	{next_state, null, Data}.

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
service_info(#'3gpp_rf_Service-Information'{'IMS-Information' = IMS,
		'Subscription-Id' = SubScriptionId}, Data) ->
	IMSI = imsi(SubScriptionId),
	MSISDN = msisdn(SubScriptionId),
	SIPURI = sip_uri(SubScriptionId),
	NewData = Data#{imsi => IMSI, msisdn => MSISDN, sip_uri => SIPURI},
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

%% @hidden
sip_uri([#'3gpp_rf_Subscription-Id'{
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_SIP_URI',
		'Subscription-Id-Data' = SIPURI} | _]) ->
	binary_to_list(SIPURI);
sip_uri([_H | T]) ->
	sip_uri(T);
sip_uri([]) ->
	undefined.

%% hidden
ims_info(#'3gpp_rf_IMS-Information'{} = _IMS, Data) ->
	Data;
ims_info(_IMS, Data) ->
	Data.

-spec diameter_answer(ResultCode, Data) -> Result
	when
		ResultCode :: pos_integer(),
		Data :: statedata(),
		Result :: #'3gpp_rf_ACA'{}.
%% @doc Build ACA response.
%% @hidden
diameter_answer(ResultCode,
		#{record_type := RecordType,
				record_number := RecordNum,
				interim_interval := AcctInterimInterval}) ->
	#'3gpp_rf_ACA'{'Acct-Application-Id' = [?RF_APPLICATION_ID],
			'Accounting-Record-Type' = RecordType,
			'Accounting-Record-Number' = RecordNum,
			'Acct-Interim-Interval' = AcctInterimInterval,
			'Result-Code' = ResultCode}.

-spec log_fsm(OldState, Data) -> ok
	when
		OldState :: atom(),
		Data :: statedata().
%% @doc Write an event to a log.
%% @hidden
log_fsm(State, #{start := Start} = Data) ->
	IMSI = maps:get(imsi, Data, []),
	MSISDN = maps:get(msisdn, Data, []),
	Context = maps:get(context, Data, []),
	SessionId = maps:get(session_id, Data, []),
	Stop = erlang:system_time(millisecond),
	Subscriber = #{imsi => IMSI, msisdn => MSISDN},
	Call = #{},
	Network = #{context => Context, session_id => SessionId},
	cse_log:blog(?FSM_LOGNAME, {Start, Stop, ?SERVICENAME,
			State, Subscriber, Call, Network}).

-spec log_cdr(ACR, Data) -> Result
	when
		ACR :: #'3gpp_rf_ACR'{},
		Data :: statedata(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Write a CDR to a log.
%% @hidden
log_cdr(#'3gpp_rf_ACR'{'Accounting-Record-Type' = RecordType,
			'Service-Information' = [#'3gpp_rf_Service-Information'{
					'IMS-Information' = [IMS]}]},
		#{bx_summary := false, bx_logger := {M1, F1},
				bx_log := Log, bx_codec := {M2, F2}} = Data) ->
	M1:F1(Log, M2:F2(bx(RecordType, IMS, Data, #{})));
log_cdr(#'3gpp_rf_ACR'{'Accounting-Record-Type' = RecordType},
		#{bx_summary := true})
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD';
		RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD' ->
	ok;
log_cdr(#'3gpp_rf_ACR'{'Accounting-Record-Type' = RecordType,
			'Service-Information' = [#'3gpp_rf_Service-Information'{
					'IMS-Information' = [IMS]}]},
		#{bx_summary := true, bx_logger := {M1, F1},
				bx_log := Log, bx_codec := {M2, F2}} = Data)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' ->
	% @todo: subsititute ACR values for accumulated counts from statedata()
	M1:F1(Log, M2:F2(bx(RecordType, IMS, Data, #{}))).

%% @hidden
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 0} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"sCSCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 1} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"pCSCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 2} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"iCSCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 3} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"mRFCRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 4} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"mGCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 5} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"bGCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 6} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"aSRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 7} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"iBCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 11} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"eCSCFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 13} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"tRFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 14} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"tFRecord">>});
bx(RecordType,
		#'3gpp_rf_IMS-Information'{'Node-Functionality' = 15} = IMS,
		Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR#{recordType => <<"aTCFRecord">>});
bx(RecordType, IMS, Data, CDR) ->
	bx1(RecordType, IMS, Data, CDR).
%% @hidden
bx1(RecordType,
		#'3gpp_rf_IMS-Information'{'Role-Of-Node' = [0]} = IMS,
		Data, CDR) ->
	bx2(RecordType, IMS, Data, CDR#{'role-of-Node' => <<"originating">>});
bx1(RecordType,
		#'3gpp_rf_IMS-Information'{'Role-Of-Node' = [1]} = IMS,
		Data, CDR) ->
	bx2(RecordType, IMS, Data, CDR#{'role-of-Node' => <<"terminating">>});
bx1(RecordType, IMS, Data, CDR) ->
	bx2(RecordType, IMS, Data, CDR).
%% @hidden
bx2(RecordType, IMS, #{ohost := NodeAddress} = Data, CDR) ->
	bx3(RecordType, IMS, Data, CDR#{nodeAddress => NodeAddress}).
%% @hidden
bx3(RecordType,
		#'3gpp_rf_IMS-Information'{'User-Session-Id' = [Value]} = IMS,
		Data, CDR) ->
	bx4(RecordType, IMS, Data,
			CDR#{'session-Id' => <<$", Value/binary, $">>});
bx3(RecordType, IMS, Data, CDR) ->
	bx4(RecordType, IMS, Data, CDR).
%% @hidden
bx4(RecordType,
		#'3gpp_rf_IMS-Information'{'Outgoing-Session-Id' = [Value]} = IMS,
		Data, CDR) ->
	bx5(RecordType, IMS, Data,
			CDR#{outgoingSessionId => <<$", Value/binary, $">>});
bx4(RecordType, IMS, Data, CDR) ->
	bx5(RecordType, IMS, Data, CDR).
%% @hidden
bx5(RecordType, #'3gpp_rf_IMS-Information'{
				'Event-Type' = [#'3gpp_rf_Event-Type'{
						'SIP-Method' = [Value]}]} = IMS,
		Data, CDR) ->
	bx6(RecordType, IMS, Data, CDR#{'sIP-Method' => Value});
bx5(RecordType, IMS, Data, CDR) ->
	bx6(RecordType, IMS, Data, CDR).
%% @hidden
bx6(RecordType, #'3gpp_rf_IMS-Information'{
				'Calling-Party-Address' = [Calling]} = IMS,
		Data, CDR) ->
	bx7(RecordType, IMS, Data,
			CDR#{'list-Of-Calling-Party-Address' => <<$", Calling/binary, $">>});
bx6(RecordType,
		#'3gpp_rf_IMS-Information'{'Calling-Party-Address' = [H | T]} = IMS,
		Data, CDR) ->
	bx7(RecordType, IMS, Data, CDR#{'list-Of-Calling-Party-Address'
			=> iolist_to_binary([$", H, [[$,, A] || A <- T], $"])});
bx6(RecordType, IMS, Data, CDR) ->
	bx7(RecordType, IMS, Data, CDR).
%% @hidden
bx7(RecordType,
		#'3gpp_rf_IMS-Information'{'Called-Party-Address' = [Called]} = IMS,
		Data, CDR) ->
	bx8(RecordType, IMS, Data,
			CDR#{'called-Party-Address' => <<$", Called/binary, $">>});
bx7(RecordType, IMS, Data, CDR) ->
	bx8(RecordType, IMS, Data, CDR).
%% @hidden
bx8(RecordType, IMS, #{sip_uri := SIPURI} = Data, CDR)
		when SIPURI /= undefined ->
	bx9(RecordType, IMS, Data, CDR, ["sip-" ++ SIPURI]);
bx8(RecordType, IMS, Data, CDR) ->
	bx9(RecordType, IMS, Data, CDR, []).
%% @hidden
bx9(RecordType, IMS, #{msisdn := MSISDN} = Data, CDR, Acc)
		when MSISDN /= undefined ->
	bx10(RecordType, IMS, Data, CDR, ["msisdn-" ++ MSISDN | Acc]);
bx9(RecordType, IMS, Data, CDR, Acc) ->
	bx10(RecordType, IMS, Data, CDR, Acc).
%% @hidden
bx10(RecordType, IMS, #{imsi := IMSI} = Data, CDR, Acc)
		when IMSI /= undefined ->
	bx11(RecordType, IMS, Data, CDR, ["imsi-" ++ IMSI | Acc]);
bx10(RecordType, IMS, Data, CDR, Acc) ->
	bx11(RecordType, IMS, Data, CDR, Acc).
%% @hidden
bx11(RecordType, IMS, Data, CDR, [ID]) ->
	Subs = iolist_to_binary([$", ID, $"]),
	bx12(RecordType, IMS, Data, CDR#{'list-of-subscription-ID' => Subs});
bx11(RecordType, IMS, Data, CDR, [H | T]) ->
	Subs = iolist_to_binary([$", H, [[$,, S] || S <- T], $"]),
	bx12(RecordType, IMS, Data, CDR#{'list-of-subscription-ID' => Subs});
bx11(RecordType, IMS, Data, CDR, []) ->
	bx12(RecordType, IMS, Data, CDR).
%% @hidden
bx12('3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD' = RecordType,
			#'3gpp_rf_IMS-Information'{
					'Time-Stamps' = [#'3gpp_rf_Time-Stamps'{
							'SIP-Request-Timestamp' = [TS]}]} = IMS,
		Data, CDR) ->
	Timestamp = cse_log:iso8601(cse_log:date(TS)),
	bx13(RecordType, IMS, Data,
			CDR#{serviceRequestTimeStamp => Timestamp});
bx12('3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' = RecordType,
			#'3gpp_rf_IMS-Information'{
					'Time-Stamps' = [#'3gpp_rf_Time-Stamps'{
							'SIP-Request-Timestamp' = [TS]}]} = IMS,
		Data, CDR) ->
	Timestamp = cse_log:iso8601(cse_log:date(TS)),
	bx13(RecordType, IMS, Data,
			CDR#{serviceDeliveryEndTimeStamp => Timestamp});
bx12(RecordType, IMS, Data, CDR) ->
	bx14(RecordType, IMS, Data, CDR).
%% @hidden
bx13('3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD' = RecordType,
		#'3gpp_rf_IMS-Information'{
				'Time-Stamps' = [#'3gpp_rf_Time-Stamps'{
							'SIP-Request-Timestamp-Fraction' = [N]}]} = IMS,
		Data, CDR) ->
	bx14(RecordType, IMS, Data,
			CDR#{serviceRequestTimeStampFraction => integer_to_binary(N)});
bx13('3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' = RecordType,
		#'3gpp_rf_IMS-Information'{
				'Time-Stamps' = [#'3gpp_rf_Time-Stamps'{
							'SIP-Request-Timestamp-Fraction' = [N]}]} = IMS,
		Data, CDR) ->
	bx14(RecordType, IMS, Data,
			CDR#{serviceDeliveryEndTimeStampFraction => integer_to_binary(N)});
bx13(RecordType, IMS, Data, CDR) ->
	bx14(RecordType, IMS, Data, CDR).
%% @hidden
bx14(RecordType, IMS, #{start_time := DateTime} = Data, CDR) ->
	Timestamp = cse_log:iso8601(cse_log:date(DateTime)),
	bx15(RecordType, IMS, Data, CDR#{recordOpeningTime => Timestamp});
bx14(RecordType, IMS, Data, CDR) ->
	bx15(RecordType, IMS, Data, CDR).
%% @hidden
bx15(RecordType, IMS, #{end_time := DateTime} = Data, CDR) ->
	Timestamp = cse_log:iso8601(cse_log:date(DateTime)),
	bx16(RecordType, IMS, Data, CDR#{recordClosureTime => Timestamp});
bx15(RecordType, IMS, Data, CDR) ->
	bx16(RecordType, IMS, Data, CDR).
%% @hidden
bx16(RecordType, #'3gpp_rf_IMS-Information'{
		'Inter-Operator-Identifier' = [#'3gpp_rf_Inter-Operator-Identifier'{
				'Originating-IOI' = [Orig], 'Terminating-IOI' = [Term]}]} = IMS,
		Data, CDR) ->
	IOIs = <<$", Orig/binary, $,, Term/binary, $">>,
	bx17(RecordType, IMS, Data, CDR#{interOperatorIdentifiers => IOIs});
bx16(RecordType, #'3gpp_rf_IMS-Information'{
		'Inter-Operator-Identifier' = [#'3gpp_rf_Inter-Operator-Identifier'{
				'Originating-IOI' = [Orig]}]} = IMS,
		Data, CDR) ->
	IOIs = <<$", Orig/binary, $,, $">>,
	bx17(RecordType, IMS, Data, CDR#{interOperatorIdentifiers => IOIs});
bx16(RecordType, #'3gpp_rf_IMS-Information'{
		'Inter-Operator-Identifier' = [#'3gpp_rf_Inter-Operator-Identifier'{
				'Terminating-IOI' = [Term]}]} = IMS,
		Data, CDR) ->
	IOIs = <<$", $,, Term/binary, $">>,
	bx17(RecordType, IMS, Data, CDR#{interOperatorIdentifiers => IOIs});
bx16(RecordType, IMS, Data, CDR) ->
	bx17(RecordType, IMS, Data, CDR).
%% @hidden
bx17(RecordType, IMS, #{record_number := RecordNumber} = Data, CDR) ->
	bx18(RecordType, IMS, Data,
			CDR#{recordSequenceNumber => integer_to_binary(RecordNumber)}).
%% @hidden
bx18(RecordType, IMS, #{close_cause := Cause} = Data, CDR) ->
	bx19(RecordType, IMS, Data,
			CDR#{causeForRecordClosing => integer_to_binary(Cause)});
bx18(RecordType, IMS, Data, CDR) ->
	bx19(RecordType, IMS, Data, CDR).
%% @hidden
bx19(RecordType,
		#'3gpp_rf_IMS-Information'{'IMS-Charging-Identifier' = [ICCID]} = IMS,
		Data, CDR) ->
	bx20(RecordType, IMS, Data, CDR#{'iMS-Charging-Identifier' => ICCID});
bx19(RecordType, IMS, Data, CDR) ->
	bx20(RecordType, IMS, Data, CDR).
%% @hidden
bx20(RecordType, IMS, #{context := Context} = Data, CDR) ->
	bx21(RecordType, IMS, Data, CDR#{serviceContextID => Context}).
%% @hidden
bx21(_RecordType,
		#'3gpp_rf_IMS-Information'{'IMS-Visited-Network-Identifier' = [Visited]},
		_Data, CDR) ->
	CDR#{iMSVisitedNetworkIdentifier => Visited};
bx21(_RecordType, _IMS, _Data, CDR) ->
	CDR.

