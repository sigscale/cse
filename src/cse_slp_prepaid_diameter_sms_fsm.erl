%%% cse_slp_prepaid_diameter_sms_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2023 SigScale Global Inc.
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
%%% 	for DIAMETER Ro application within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This Service Logic Program (SLP) implements a 3GPP Online
%%% 	Charging Function (OCF) interfacing across the <i>Re</i> reference
%%% 	point interafce, using the
%%% 	<a href="https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0">
%%% 	Nrf_Rating</a> API, with a remote <i>Rating Function</i>.
%%%
%%% 	This SLP specifically handles Short Message Service (SMS)
%%% 	service usage with `Service-Context-Id' of `32274@3gpp.org'.
%%%
%%% 	== Message Sequence ==
%%% 	The diagram below depicts the normal sequence of exchanged
%%% 	messages for Immediate Event Charging (IEC):
%%%
%%% 	<img alt="message sequence chart" src="ocf-nrf-iec-msc.svg" />
%%%
%%% 	The diagram below depicts the normal sequence of exchanged
%%% 	messages for Event Charging with Unit Reservation (ECUR):
%%%
%%% 	<img alt="message sequence chart" src="ocf-nrf-msc.svg" />
%%%
%%% 	== State Transitions ==
%%% 	The following diagram depicts the states, and events which drive state
%%% 	transitions, in the OCF finite state machine (FSM):
%%%
%%% 	<img alt="state machine" src="prepaid-diameter-event.svg" />
%%%
-module(cse_slp_prepaid_diameter_sms_fsm).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Refath Wadood <refath@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, authorize_event_attempt/3,
		collect_information/3, analyse_information/3,
		active/3]).
%% export the private api
-export([nrf_start_reply/2, nrf_update_reply/2, nrf_release_reply/2]).

-include_lib("kernel/include/logger.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("cse_codec.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_cc_application_rfc4006.hrl").

-define(RO_APPLICATION_ID, 4).
-define(IANA_PEN_SigScale, 50386).
-define(SMS_CONTEXTID, "32274@3gpp.org").
-define(SERVICENAME, "Prepaid Messaging").
-define(FSM_LOGNAME, prepaid).
-define(NRF_LOGNAME, rating).

-type state() :: null
		| authorize_event_attempt | collect_information
		| analyse_information | active.

-type statedata() :: #{start := pos_integer(),
		from => pid(),
		session_id => binary(),
		context => string(),
		mscc => [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		req_type => pos_integer(),
		reqno => integer(),
		one_time => boolean(),
		action => direct_debiting | refund_account
				| check_balance | price_enquiry,
		ohost => binary(),
		orealm => binary(),
		drealm => binary(),
		imsi => [$0..$9],
		msisdn => string(),
		recipient => string(),
		originator => string(),
		nrf_profile => atom(),
		nrf_address => inet:ip_address(),
		nrf_port => non_neg_integer(),
		nrf_uri => string(),
		nrf_http_options => httpc:http_options(),
		nrf_headers => httpc:headers(),
		nrf_location => string(),
		nrf_start => pos_integer(),
		nrf_req_url => string(),
		nrf_http => map(),
		nrf_reqid => reference()}.

%%----------------------------------------------------------------------
%%  The cse_slp_prepaid_diameter_sms_fsm gen_statem callbacks
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
	{ok, Profile} = application:get_env(cse, nrf_profile),
	{ok, URI} = application:get_env(cse, nrf_uri),
	{ok, HttpOptions} = application:get_env(nrf_http_options),
	{ok, Headers} = application:get_env(nrf_headers),
	Data = #{nrf_profile => Profile, nrf_uri => URI,
			nrf_http_options => HttpOptions, nrf_headers => Headers,
			start => erlang:system_time(millisecond)},
	case httpc:get_options([ip, port], Profile) of
		{ok, Options} ->
			init1(Options, Data);
		{error, Reason} ->
			{stop, Reason}
	end.
%% @hidden
init1([{ip, Address} | T], Data) ->
	init1(T, Data#{nrf_address => Address});
init1([{port, Port} | T], Data) ->
	init1(T, Data#{nrf_port => Port});
init1([], Data) ->
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
	log_fsm(OldState,Data),
	{stop, shutdown};
null({call, _From}, #'3gpp_ro_CCR'{} = _EventContent, Data) ->
	{next_state, authorize_event_attempt, Data, postpone}.

-spec authorize_event_attempt(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_event_attempt</em> state.
%% @private
authorize_event_attempt(enter, _EventContent, _Data) ->
	keep_state_and_data;
authorize_event_attempt({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'CC-Request-Type' = RequestType,
				'Requested-Action' = [Action],
				'Service-Context-Id' = SvcContextId,
				'CC-Request-Number' = RequestNum,
				'Subscription-Id' = SubscriptionId,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation}, Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_EVENT_REQUEST' ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	{Originator, Recipient} = message_parties(ServiceInformation),
	NewData = Data#{from => From,
			one_time => true, action => requested_action(Action),
			imsi => IMSI, msisdn => MSISDN,
			originator => Originator, recipient => Recipient,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, drealm => DRealm, reqno => RequestNum,
			req_type => RequestType},
	nrf_start(NewData);
authorize_event_attempt({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'CC-Request-Type' = RequestType,
				'Service-Context-Id' = SvcContextId,
				'CC-Request-Number' = RequestNum,
				'Subscription-Id' = SubscriptionId,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation}, Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST' ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	{Originator, Recipient} = message_parties(ServiceInformation),
	NewData = Data#{from => From, one_time => false,
			imsi => IMSI, msisdn => MSISDN,
			originator => Originator, recipient => Recipient,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, drealm => DRealm, reqno => RequestNum,
			req_type => RequestType},
	nrf_start(NewData);
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := LogHTTP, session_id := SessionId,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType, mscc := MSCC,
				recipient := Recipient, one_time := OneTime} = Data) ->
	log_nrf(ecs_http(Version, 201, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := ServiceRating}}, {_, Location}}
				when is_list(Location) ->
			try
				NewData1 = NewData#{nrf_location => Location},
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {ResultCode, OneTime, Recipient} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true, _} ->
						{next_state, null, NewData1, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false, Destination}
							when length(Destination) > 0 ->
						{next_state, analyse_information, NewData1, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false, _} ->
						{next_state, collect_information, NewData1, Actions};
					{_, _, _} ->
						{next_state, null, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, authorize_event_attempt}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{{error, Partial, Remaining}, Location} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_event_attempt}]),
			Reply2 = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions2 = [{reply, From, Reply2}],
			{next_state, null, NewData, Actions2}
	end;
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := LogHTTP, session_id := SessionId,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, nrf_start},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_release, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, session_id := SessionId,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, nrf_release},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data) ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_release, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				session_id := SessionId, ohost := OHost,
				orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data) ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions}.

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
collect_information({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location)  ->
	{Originator, Recipient} = message_parties(ServiceInformation),
	NewData = Data#{from => From, mscc => MSCC,
			originator => Originator, recipient => Recipient,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
collect_information({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				is_list(Location)  ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_release(NewData);
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{nrf_update, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC, recipient := Recipient} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {ResultCode, is_usu(MSCC), Recipient} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true, _} ->
						{next_state, active, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false, Destination}
							when length(Destination) > 0 ->
						{next_state, analyse_information, NewData, Actions};
					{_, _, _} ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, collect_information}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, collect_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
collect_information(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, collect_information}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, collect_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, session_id := SessionId,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, collect_information}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				session_id := SessionId, ohost := OHost,
				orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, collect_information}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end.

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
analyse_information({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
analyse_information({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_release(NewData);
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{nrf_update, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {ResultCode, is_usu(MSCC)} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true} ->
						{next_state, active, NewData, Actions};
					{_, _} ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, analyse_information}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, analyse_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
analyse_information(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, analyse_information}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, analyse_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, session_id := SessionId,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, analyse_information}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				session_id := SessionId, ohost := OHost,
				orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, analyse_information}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end.

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
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
active({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_release(NewData);
active(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{nrf_update, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{keep_state, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, active}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
active(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, active}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, session_id := SessionId,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, active}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				session_id := SessionId, ohost := OHost,
				orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, active}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end.

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
		Result :: {keep_state, Data} | {keep_state, Data, Actions},
		Actions :: [{reply, From, #'3gpp_ro_CCA'{}}],
		From :: {pid(), reference()}.
%% @doc Start rating a session.
%% @hidden
nrf_start(#{one_time := OneTime, mscc := MSCC,
		context := ServiceContextId} = Data) ->
	ServiceRating = service_rating(OneTime, MSCC, ServiceContextId),
	nrf_start1(OneTime, ServiceRating, Data).
%% @hidden
nrf_start1(true, ServiceRating, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"oneTimeEvent" => true,
			"oneTimeEventType" => "IEC",
			"serviceRating" => ServiceRating},
	nrf_start2(Now, JSON, Data);
nrf_start1(false, ServiceRating, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"serviceRating" => ServiceRating},
	nrf_start2(Now, JSON, Data).
%% @hidden
nrf_start2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	% @todo synchronous start
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"accept", "application/json"} | Headers],
	Body = zj:encode(JSON),
	ContentType = "application/json",
	RequestURL = URI ++ "/ratingdata",
	LogHTTP = ecs_http(ContentType, Body),
	Request = {RequestURL, Headers1, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_start => Now, nrf_reqid => RequestId,
					nrf_req_url => RequestURL, nrf_http => LogHTTP},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{origin_host, OHost}, {origin_realm, ORealm},
					{slpi, self()}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, Data, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, Data, Actions}
	end.

-spec nrf_update(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {keep_state, Data, Actions},
		Actions :: [{reply, From, #'3gpp_ro_CCA'{}}],
		From :: {pid(), reference()}.
%% @doc Update rating a session.
nrf_update(#{mscc := MSCC, context := ServiceContextId} = Data) ->
	ServiceRating = service_rating(false, MSCC, ServiceContextId),
	nrf_update1(ServiceRating, Data).
%% @hidden
nrf_update1(ServiceRating, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"serviceRating" => ServiceRating},
	nrf_update2(Now, JSON, Data).
%% @hidden
nrf_update2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, session_id := SessionId,
				ohost := OHost, orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"accept", "application/json"} | Headers],
	Body = zj:encode(JSON),
	ContentType = "application/json",
	RequestURL = URI ++ Location ++ "/update",
	LogHTTP = ecs_http(ContentType, Body),
	Request = {RequestURL, Headers1, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_start => Now, nrf_reqid => RequestId,
					nrf_req_url => RequestURL, nrf_http => LogHTTP},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end.

-spec nrf_release(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {keep_state, Data, Actions},
		Actions :: [{reply, From, #'3gpp_ro_CCA'{}}],
		From :: {pid(), reference()}.
%% @doc Finish rating a session.
nrf_release(#{mscc := MSCC, context := ServiceContextId} = Data) ->
	ServiceRating = service_rating(false, MSCC, ServiceContextId),
	nrf_release1(ServiceRating,  Data).
%% @hidden
nrf_release1(ServiceRating, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"serviceRating" => ServiceRating},
	nrf_release2(Now, JSON, Data).
%% @hidden
nrf_release2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, session_id := SessionId,
				ohost := OHost, orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"accept", "application/json"} | Headers],
	Body = zj:encode(JSON),
	ContentType = "application/json",
	RequestURL = URI ++ Location ++ "/release",
	LogHTTP = ecs_http(ContentType, Body),
	Request = {RequestURL, Headers1, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_start => Now, nrf_reqid => RequestId,
					nrf_req_url => RequestURL, nrf_http => LogHTTP},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_release}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end.

%% @hidden
rsu(#'3gpp_ro_Requested-Service-Unit'{'CC-Service-Specific-Units' = [CCSpecUnits]}) ->
	#{"serviceSpecificUnit" => CCSpecUnits};
rsu(#'3gpp_ro_Requested-Service-Unit'{}) ->
	#{}.

%% @hidden
is_usu([#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [_USU]} | _]) ->
	true;
is_usu([#'3gpp_ro_Multiple-Services-Credit-Control'{} | T]) ->
	is_usu(T);
is_usu([]) ->
	false.

%% @hidden
usu(#'3gpp_ro_Used-Service-Unit'{'CC-Service-Specific-Units' = [CCSpecUnits]}) ->
	#{"serviceSpecificUnit" => CCSpecUnits};
usu(#'3gpp_ro_Used-Service-Unit'{}) ->
	#{}.

%% @hidden
gsu({ok, #{"serviceSpecificUnit" := CCSpecUnits}})
		when CCSpecUnits > 0 ->
	[#'3gpp_ro_Granted-Service-Unit'{'CC-Service-Specific-Units' = [CCSpecUnits]}];
gsu(_) ->
	[].

-spec service_rating(OneTime, MSCC, ServiceContextId) -> ServiceRating
	when
		OneTime :: boolean(),
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		ServiceContextId :: string(),
		ServiceRating :: [map()].
%% @doc Build a `serviceRating' object.
%% @hidden
service_rating(OneTime, MSCC, ServiceContextId) ->
	service_rating(OneTime, MSCC, ServiceContextId, []).
%% @hidden
service_rating(true, [MSCC | T], ServiceContextId, Acc) ->
	SR1 = service_rating_si(MSCC, #{"serviceContextId" => ServiceContextId}),
	SR2 = service_rating_rg(MSCC, SR1),
	Acc1 = service_rating_reserve(true, MSCC, SR2, Acc),
	service_rating(true, T, ServiceContextId, Acc1);
service_rating(false, [MSCC | T], ServiceContextId, Acc) ->
	SR1 = service_rating_si(MSCC, #{"serviceContextId" => ServiceContextId}),
	SR2 = service_rating_rg(MSCC, SR1),
	Acc1 = service_rating_reserve(false, MSCC, SR2, Acc),
	Acc2 = service_rating_debit(MSCC, SR2, Acc1),
	service_rating(false, T, ServiceContextId, Acc2);
service_rating(_OneTime, [], _ServiceContextId, Acc) ->
	lists:reverse(Acc).

%% @hidden
service_rating_si(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Service-Identifier' = [SI]}, ServiceRating) ->
	ServiceRating#{"serviceId" => SI};
service_rating_si(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Service-Identifier' = []}, ServiceRating) ->
	ServiceRating.

%% @hidden
service_rating_rg(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Rating-Group' = [RG]}, ServiceRating) ->
	ServiceRating#{"ratingGroup" => RG};
service_rating_rg(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Rating-Group' = []}, ServiceRating) ->
	ServiceRating.

%% @hidden
service_rating_reserve(true, #'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [RSU]}, ServiceRating, Acc) ->
	case rsu(RSU) of
		ResquestedUnit when map_size(ResquestedUnit) > 0 ->
			[ServiceRating#{"requestSubType" => "DEBIT",
					"requestedUnit" => ResquestedUnit} | Acc];
		_ResquestedUnit ->
			[ServiceRating#{"requestSubType" => "DEBIT"} | Acc]
	end;
service_rating_reserve(false, #'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [RSU]}, ServiceRating, Acc) ->
	case rsu(RSU) of
		ResquestedUnit when map_size(ResquestedUnit) > 0 ->
			[ServiceRating#{"requestSubType" => "RESERVE",
					"requestedUnit" => ResquestedUnit} | Acc];
		_ResquestedUnit ->
			[ServiceRating#{"requestSubType" => "RESERVE"} | Acc]
	end;
service_rating_reserve(_Onetime, #'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = []}, _ServiceRating, Acc) ->
	Acc.

%% @hidden
service_rating_debit(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [USU]}, ServiceRating, Acc) ->
	case usu(USU) of
		UsedUnit when map_size(UsedUnit) > 0 ->
			[ServiceRating#{"requestSubType" => "DEBIT",
					"consumedUnit" => usu(USU)} | Acc];
		_UsedUnit ->
			Acc
	end;
service_rating_debit(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = []}, _ServiceRating, Acc) ->
	Acc.

%% @hidden
subscription_id(Data) ->
	subscription_id1(Data, []).
%% @hidden
subscription_id1(#{msisdn := MSISDN} = Data, Acc)
		when is_list(MSISDN) ->
	subscription_id2(Data, ["msisdn-" ++ MSISDN | Acc]);
subscription_id1(Data, Acc) ->
	subscription_id2(Data, Acc).
%% @hidden
subscription_id2(#{imsi := IMSI} = _Data, Acc)
		when is_list(IMSI) ->
	["imsi-" ++ IMSI | Acc];
subscription_id2(_Data, Acc) ->
	Acc.

%% @hidden
imsi([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Data' = IMSI,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI'} | _]) ->
	binary_to_list(IMSI);
imsi([_H | T]) ->
	imsi(T);
imsi([]) ->
	undefined.

%% @hidden
msisdn([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Data' = MSISDN,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164'} | _]) ->
	binary_to_list(MSISDN);
msisdn([_H | T]) ->
	msisdn(T);
msisdn([]) ->
	undefined.

-spec build_mscc(MSCC, ServiceRating) -> Result
	when
		ServiceRating :: [map()],
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		Result :: {ResultCode, MSCC},
		ResultCode :: pos_integer().
%% @doc Build CCA `MSCC' from Nrf `ServoceRating'.
build_mscc(MSCC, ServiceRating) ->
	FailRC = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	build_mscc(MSCC, ServiceRating, {FailRC, []}).
%% @hidden
build_mscc([#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Service-Identifier' = SI, 'Rating-Group' = RG} | T] = _MSCC,
		ServiceRating, Acc) ->
	build_mscc(T, ServiceRating, build_mscc1(SI, RG, ServiceRating, Acc));
build_mscc([], _ServiceRating, {FinalRC, Acc}) ->
	{FinalRC, lists:reverse(Acc)}.
%% @hidden
build_mscc1([SI], [RG], [#{"serviceId" := SI, "ratingGroup" := RG,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Granted-Service-Unit' = GSU,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([SI], [], [#{"serviceId" := SI,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Granted-Service-Unit' = GSU,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([], [RG], [#{"ratingGroup" := RG,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Rating-Group' = [RG],
			'Granted-Service-Unit' = GSU,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([], [], [#{"resultCode" := ResultCode} = ServiceRating | _],
		{FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = GSU,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1(SI, RG, [_ | T], Acc) ->
	build_mscc1(SI, RG, T, Acc);
build_mscc1(_, _, [], Acc) ->
	Acc.

%% @hidden
final_result(_, ?'DIAMETER_BASE_RESULT-CODE_SUCCESS') ->
	?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
final_result(RC, _) ->
	RC.

-spec diameter_answer(SessionId, MSCC, ResultCode,
		OriginHost, OriginRealm, RequestType, RequestNum) -> Result
	when
		SessionId :: binary(),
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		ResultCode :: pos_integer(),
		OriginHost :: binary(),
		OriginRealm :: binary(),
		RequestType :: integer(),
		RequestNum :: integer(),
		Result :: #'3gpp_ro_CCA'{}.
%% @doc Build CCA response.
%% @hidden
diameter_answer(SessionId, MSCC, ResultCode,
		OHost, ORealm, RequestType, RequestNum) ->
	#'3gpp_ro_CCA'{'Session-Id' = SessionId,
			'Multiple-Services-Credit-Control' = MSCC,
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNum,
			'Result-Code' = ResultCode}.

-spec diameter_error(SessionId, ResultCode, OriginHost,
		OriginRealm, RequestType, RequestNum) -> Reply
	when
		SessionId :: binary(),
		ResultCode :: pos_integer(),
		OriginHost :: binary(),
		OriginRealm :: binary(),
		RequestType :: integer(),
		RequestNum :: integer(),
		Reply :: #'3gpp_ro_CCA'{}.
%% @doc Build CCA response indicating an operation failure.
%% @hidden
diameter_error(SessionId, ResultCode, OHost,
		ORealm, RequestType, RequestNum) ->
	#'3gpp_ro_CCA'{'Session-Id' = SessionId,
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Result-Code' = ResultCode,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNum}.

-spec result_code(ResultCode) -> Result
	when
		ResultCode :: string(),
		Result :: pos_integer().
%% @doc Convert a Nrf ResultCode to a Diameter ResultCode
%% @hidden
result_code("SUCCESS") ->
	?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
result_code("END_USER_SERVICE_DENIED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("QUOTA_LIMIT_REACHED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED';
result_code("USER_UNKNOWN") ->
	?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN';
result_code("RATING_FAILED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED'.

-spec message_parties(ServiceInformation) -> Result
	when
		ServiceInformation :: [#'3gpp_ro_Service-Information'{}],
		Result :: {Originator, Recipient},
		Originator :: string(),
		Recipient :: string().
%% @doc Extract message party addresses.
%% @hidden
message_parties([#'3gpp_ro_Service-Information'{
		'SMS-Information' = [#'3gpp_ro_SMS-Information'{
				'Originator-Received-Address' = OriginatorAddress,
				'Recipient-Info' = RecipientInfo}]}]) ->
	{address(OriginatorAddress), address(RecipientInfo)};
message_parties([#'3gpp_ro_Service-Information'{
		'SMS-Information' = []}]) ->
	{[], []};
message_parties([]) ->
	{[], []}.

%% @hidden
address([#'3gpp_ro_Originator-Received-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
		'Address-Data' = [Data]} | _T]) ->
	"msisdn-" ++ binary_to_list(Data);
address([#'3gpp_ro_Originator-Received-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_IMSI'],
		'Address-Data' = [Data]} | _T]) ->
	"imsi-" ++ binary_to_list(Data);
address([#'3gpp_ro_Originator-Received-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_EMAIL_ADDRESS'],
		'Address-Data' = [Data]} | _T]) ->
	"nai-" ++ binary_to_list(Data);
address([#'3gpp_ro_Recipient-Info'{
		'Recipient-Address' = [#'3gpp_ro_Recipient-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
				'Address-Data' = [Data]} | _]} | _]) ->
	"msisdn-" ++ binary_to_list(Data);
address([#'3gpp_ro_Recipient-Info'{
		'Recipient-Address' = [#'3gpp_ro_Recipient-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_IMSI'],
				'Address-Data' = [Data]} | _]} | _]) ->
	"imsi-" ++ binary_to_list(Data);
address([#'3gpp_ro_Recipient-Info'{
		'Recipient-Address' = [#'3gpp_ro_Recipient-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_EMAIL_ADDRESS'],
				'Address-Data' = [Data]} | _]} | _]) ->
	"nai-" ++ binary_to_list(Data);
address([_H | T]) ->
	address(T);
address([]) ->
	[].

%% @hidden
requested_action(?'3GPP_REQUESTED-ACTION_DIRECT_DEBITING') ->
	direct_debiting;
requested_action(?'3GPP_REQUESTED-ACTION_REFUND_ACCOUNT') ->
	refund_account;
requested_action(?'3GPP_REQUESTED-ACTION_CHECK_BALANCE') ->
	check_balance;
requested_action(?'3GPP_REQUESTED-ACTION_PRICE_ENQUIRY') ->
	price_enquiry.

-spec ecs_http(MIME, Body) -> HTTP
	when
		MIME :: string(),
		Body :: binary() | iolist(),
		HTTP :: map().
%% @doc Construct ECS JSON `map()' for Nrf request.
%% @hidden
ecs_http(MIME, Body) ->
	Body1 = #{"bytes" => iolist_size(Body),
			%"content" => cse_rest:stringify(zj:encode(Body))},
			"content" => zj:encode(Body)},
	Request = #{"method" => "post",
			"mime_type" => MIME,
			"body" => Body1},
	#{"request" => Request}.

-spec ecs_http(Version, StatusCode, Headers, Body, HTTP) -> HTTP
	when
		Version :: string(),
		StatusCode :: pos_integer(),
		Headers :: [HttpHeader],
		HttpHeader :: {Field, Value},
		Field :: [byte()],
		Value :: binary() | iolist(),
		Body :: binary() | iolist(),
		HTTP :: map().
%% @doc Construct ECS JSON `map()' for Nrf request.
%% @hidden
ecs_http(Version, StatusCode, Headers, Body, HTTP) ->
	Response = case {lists:keyfind("content-length", 1, Headers),
			lists:keyfind("content-type", 1, Headers)} of
		{{_, Bytes}, {_, MIME}} ->
			Body1 = #{"bytes" => Bytes,
					"content" => zj:encode(Body)},
			#{"status_code" => StatusCode,
					"mime_type" => MIME, "body" => Body1};
		{{_, Bytes}, false} ->
			Body1 = #{"bytes" => Bytes,
					"content" => zj:encode(Body)},
			#{"status_code" => StatusCode, "body" => Body1};
		_ ->
			#{"status_code" => StatusCode}
	end,
	HTTP#{"version" => Version, "response" => Response}.

-spec log_nrf(HTTP, Data) -> ok
	when
		HTTP :: map(),
		Data :: statedata().
%% @doc Write an event to a log.
%% @hidden
log_nrf(HTTP,
		#{nrf_start := Start,
		imsi := IMSI,
		msisdn := MSISDN,
		nrf_address := Address,
		nrf_port := Port,
		nrf_req_url := URL} = _Data) ->
	Stop = erlang:system_time(millisecond),
	Subscriber = #{imsi => IMSI, msisdn => MSISDN},
	Client = case {Address, Port} of
		{Address, Port} when is_tuple(Address), is_integer(Port) ->
			{Address, Port};
		{Address, _} when is_tuple(Address) ->
			{Address, 0};
		{_, Port} when is_integer(Port) ->
			{[], Port};
		{_, _} ->
			{[], 0}
	end,
	cse_log:blog(?NRF_LOGNAME,
			{Start, Stop, ?SERVICENAME, Subscriber, Client, URL, HTTP}).

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
		originator := Originator,
		recipient :=  Recipient,
		context := Context,
		session_id := SessionId} = Data) ->
	Stop = erlang:system_time(millisecond),
	Subscriber = #{imsi => IMSI, msisdn => MSISDN},
	Event = #{originator => Originator, recipient => Recipient},
	Network = #{context => Context, session_id => SessionId},
	OCS = #{nrf_location => maps:get(nrf_location, Data, [])},
	cse_log:blog(?FSM_LOGNAME, {Start, Stop, ?SERVICENAME,
			State, Subscriber, Event, Network, OCS}).

%% @hidden
remove_nrf(Data) ->
	Data1 = maps:remove(from, Data),
	Data2 = maps:remove(nrf_start, Data1),
	Data3 = maps:remove(nrf_req_uri, Data2),
	Data4 = maps:remove(nrf_http, Data3),
	maps:remove(nrf_reqid, Data4).

