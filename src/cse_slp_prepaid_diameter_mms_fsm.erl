%%% cse_slp_prepaid_diameter_mms_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% 	point interface, using the
%%% 	<a href="https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0">
%%% 	Nrf_Rating</a> API, with a remote <i>Rating Function</i>.
%%%
%%% 	This SLP specifically handles Multimedia Messaging Service (MMS)
%%% 	service usage with `Service-Context-Id' of `32270@3gpp.org'.
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
-module(cse_slp_prepaid_diameter_mms_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
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
-define(MMS_CONTEXTID, "32270@3gpp.org").
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
		sequence => pos_integer(),
		mscc => [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		service_info => [#'3gpp_ro_Service-Information'{}],
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
%%  The cse_slp_prepaid_diameter_mms_fsm gen_statem callbacks
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
			start => erlang:system_time(millisecond),
			sequence => 1},
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
	catch log_fsm(OldState,Data),
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
	NewData = Data#{from => From, session_id => SessionId,
			one_time => true, action => requested_action(Action),
			imsi => IMSI, msisdn => MSISDN,
			originator => Originator, recipient => Recipient,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, service_info => ServiceInformation,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			reqno => RequestNum, req_type => RequestType},
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
	NewData = Data#{from => From, session_id => SessionId,
			one_time => false,
			imsi => IMSI, msisdn => MSISDN,
			originator => Originator, recipient => Recipient,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, service_info => ServiceInformation,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			reqno => RequestNum, req_type => RequestType},
	nrf_start(NewData);
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := LogHTTP,
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
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
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
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
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
			ResultCode1 = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
			Actions1 = [{reply, From, Reply1}],
			{next_state, null, NewData, Actions1}
	end;
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := LogHTTP, nrf_uri := URI,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case {zj:decode(Body), lists:keyfind("content-type", 1, Headers)} of
		{{ok, #{"cause" := Cause}}, {_, "application/problem+json" ++ _}} ->
			ResultCode = result_code(Cause),
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {status, 403}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := LogHTTP,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, nrf_start},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_release, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, nrf_release},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_start, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_event_attempt(cast,
		{nrf_release, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_event_attempt}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			originator => Originator, recipient => Recipient,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
collect_information({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				is_list(Location)  ->
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			reqno => RequestNum, req_type => RequestType},
	nrf_release(NewData);
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := LogHTTP, nrf_uri := URI,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	Actions = case {zj:decode(Body),
			lists:keyfind("content-type", 1, Headers)} of
		{{ok, #{"cause" := Cause}}, {_, "application/problem+json" ++ _}} ->
			ResultCode = result_code(Cause),
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}];
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, NrfOperation}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {status, 403}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, collect_information}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC, recipient := Recipient} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
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
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1,
							RequestType, RequestNum),
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
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
collect_information(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, collect_information}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			Reply = diameter_answer([], ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
					RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, collect_information}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, collect_information}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, collect_information}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
analyse_information({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			reqno => RequestNum, req_type => RequestType},
	nrf_release(NewData);
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := LogHTTP, nrf_uri := URI,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	Actions = case {zj:decode(Body),
			lists:keyfind("content-type", 1, Headers)} of
		{{ok, #{"cause" := Cause}}, {_, "application/problem+json" ++ _}} ->
			ResultCode = result_code(Cause),
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}];
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, NrfOperation}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {status, 403}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, analyse_information}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
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
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
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
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
analyse_information(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, analyse_information}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			Reply = diameter_answer([], ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
					RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, analyse_information}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, analyse_information}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, analyse_information}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
active({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			reqno => RequestNum, req_type => RequestType},
	nrf_release(NewData);
active(cast,
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := LogHTTP, nrf_uri := URI,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	Actions = case {zj:decode(Body),
			lists:keyfind("content-type", 1, Headers)} of
		{{ok, #{"cause" := Cause}}, {_, "application/problem+json" ++ _}} ->
			ResultCode = result_code(Cause),
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}];
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, NrfOperation}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {status, 403}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{keep_state, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, active}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
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
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
active(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location, nrf_http := LogHTTP,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, active}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			Reply = diameter_answer([], ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
					RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{Version, Code, Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, Code, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {location, Location},
			{slpi, self()}, {origin_host, OHost}, {origin_realm, ORealm},
			{state, active}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, active}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
nrf_start(Data) ->
	case service_rating(Data) of
		ServiceRating when length(ServiceRating) > 0 ->
			nrf_start1(#{"serviceRating" => ServiceRating}, Data);
		[] ->
			nrf_start1(#{}, Data)
	end.
%% @hidden
nrf_start1(JSON, #{one_time := true, sequence := Sequence} = Data) ->
	Now = erlang:system_time(millisecond),
	JSON1 = JSON#{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"oneTimeEvent" => true,
			"oneTimeEventType" => "IEC"},
	nrf_start2(Now, JSON1, Data);
nrf_start1(JSON, #{one_time := false, sequence := Sequence} = Data) ->
	Now = erlang:system_time(millisecond),
	JSON1 = JSON#{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	nrf_start2(Now, JSON1, Data).
%% @hidden
nrf_start2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	% @todo synchronous start
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"accept", "application/json, application/problem+json"} | Headers],
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
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, Data, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
nrf_update(Data) ->
	case service_rating(Data) of
		ServiceRating when length(ServiceRating) > 0 ->
			nrf_update1(#{"serviceRating" => ServiceRating}, Data);
		[] ->
			nrf_update1(#{}, Data)
	end.
%% @hidden
nrf_update1(JSON, #{sequence := Sequence} = Data) ->
	NewSequence = Sequence + 1,
	Now = erlang:system_time(millisecond),
	JSON1 = JSON#{"invocationSequenceNumber" => NewSequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	NewData = Data#{sequence => NewSequence},
	nrf_update2(Now, JSON1, NewData).
%% @hidden
nrf_update2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"accept", "application/json, application/problem+json"} | Headers],
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
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
nrf_release(Data) ->
	case service_rating(Data) of
		ServiceRating when length(ServiceRating) > 0 ->
			nrf_release1(#{"serviceRating" => ServiceRating}, Data);
		[] ->
			nrf_release1(#{}, Data)
	end.
%% @hidden
nrf_release1(JSON, #{sequence := Sequence} = Data) ->
	NewSequence = Sequence + 1,
	Now = erlang:system_time(millisecond),
	JSON1 = JSON#{"invocationSequenceNumber" => NewSequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	NewData = Data#{sequence => NewSequence},
	nrf_release2(Now, JSON1, NewData).
%% @hidden
nrf_release2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"accept", "application/json, application/problem+json"} | Headers],
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
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end.

%% @hidden
rsu(#'3gpp_ro_Requested-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]}) ->
	#{"serviceSpecificUnit" => CCSpecUnits};
rsu(_RSU) ->
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
usu(#'3gpp_ro_Used-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]}) ->
	#{"serviceSpecificUnit" => CCSpecUnits};
usu(_USU) ->
	#{}.

%% @hidden
gsu({ok, #{"serviceSpecificUnit" := CCSpecUnits}})
		when is_integer(CCSpecUnits), CCSpecUnits > 0 ->
	[#'3gpp_ro_Granted-Service-Unit'{
			'CC-Service-Specific-Units' = [CCSpecUnits]}];
gsu(_) ->
	[].

%% @hidden
quota_threshold(#{"validUnits" := ValidUnits,
		"grantedUnit" := GSU})
		when is_integer(ValidUnits), ValidUnits > 0,
		is_map_key("time", GSU) ->
	{[ValidUnits], [], []};
quota_threshold(#{"validUnits" := ValidUnits,
		"grantedUnit" := GSU})
		when is_integer(ValidUnits), ValidUnits > 0,
		(is_map_key("totalVolume", GSU)
				orelse is_map_key("uplinkVolume", GSU)
				orelse is_map_key("downlinkVolume", GSU)) ->
	{[], [ValidUnits], []};
quota_threshold(#{"validUnits" := ValidUnits,
		"grantedUnit" := GSU})
		when is_integer(ValidUnits), ValidUnits > 0,
		is_map_key("serviceSpecificUnit", GSU) ->
	{[], [], [ValidUnits]};
quota_threshold(_) ->
	{[], [], []}.

%% @hidden
vality_time(#{"expiryTime" := ValidityTime})
		when is_integer(ValidityTime), ValidityTime > 0 ->
	[ValidityTime];
vality_time(_) ->
	[].

-spec service_rating(Data) -> ServiceRating
	when
		Data :: statedata(),
		ServiceRating :: [map()].
%% @doc Build a `serviceRating' object.
%% @hidden
service_rating(#{one_time := OneTime, mscc := MSCC} = Data) ->
	service_rating(OneTime, MSCC, Data, []).
%% @hidden
service_rating(true, [MSCC | T],
		#{context := ServiceContextId,
		service_info := ServiceInformation} = Data, Acc) ->
	SR1 = #{"serviceContextId" => ServiceContextId},
	SR2 = service_rating_si(MSCC, SR1),
	SR3 = service_rating_rg(MSCC, SR2),
	SR4 = service_rating_ps(ServiceInformation, SR3),
	SR5 = service_rating_mms(ServiceInformation, SR4),
	SR6 = service_rating_vcs(ServiceInformation, SR5),
	Acc1 = service_rating_debit(MSCC, SR6, Acc),
	service_rating(true, T, Data, Acc1);
service_rating(false, [MSCC | T],
		#{context := ServiceContextId,
		service_info := ServiceInformation} = Data, Acc) ->
	SR1 = #{"serviceContextId" => ServiceContextId},
	SR2 = service_rating_si(MSCC, SR1),
	SR3 = service_rating_rg(MSCC, SR2),
	SR4 = service_rating_ps(ServiceInformation, SR3),
	SR5 = service_rating_mms(ServiceInformation, SR4),
	SR6 = service_rating_vcs(ServiceInformation, SR5),
	Acc1 = service_rating_reserve(MSCC, SR6, Acc),
	Acc2 = service_rating_debit(MSCC, SR6, Acc1),
	service_rating(false, T, Data, Acc2);
service_rating(_OneTime, [], _Data, Acc) ->
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
service_rating_ps([#'3gpp_ro_Service-Information'{
		'PS-Information' = [PS]}] = _ServiceInformation,
		#{"servicceInformation" := Info} = ServiceRating) ->
	service_rating_ps1(PS, ServiceRating, Info);
service_rating_ps([#'3gpp_ro_Service-Information'{
		'PS-Information' = [PS]}] = _ServiceInformation, ServiceRating) ->
	service_rating_ps1(PS, ServiceRating, #{});
service_rating_ps(_ServiceInformation, ServiceRating) ->
	ServiceRating.
%% @hidden
service_rating_ps1(#'3gpp_ro_PS-Information'{
		'3GPP-SGSN-MCC-MNC' = [MCCMNC]} = PS,
		ServiceRating, Info) ->
	MCC = binary:bin_to_list(MCCMNC, 0, 3),
	MNC = binary:bin_to_list(MCCMNC, 3, byte_size(MCCMNC) - 3),
	SgsnMccMnc = #{"mcc" => MCC, "mnc" => MNC},
	Info1 = Info#{"sgsnMccMnc" => SgsnMccMnc},
	service_rating_ps2(PS, ServiceRating, Info1);
service_rating_ps1(PS, ServiceRating, Info) ->
	service_rating_ps2(PS, ServiceRating, Info).
%% @hidden
service_rating_ps2(#'3gpp_ro_PS-Information'{
		'Serving-Node-Type' = [NodeType]} = PS,
		ServiceRating, Info) ->
	ServingNodeType = case NodeType of
		?'3GPP_RO_SERVING-NODE-TYPE_SGSN' ->
			"SGSN";
		?'3GPP_RO_SERVING-NODE-TYPE_PMIPSGW' ->
			"PMIPSGW";
		?'3GPP_RO_SERVING-NODE-TYPE_GTPSGW' ->
			"GTPSGW";
		?'3GPP_RO_SERVING-NODE-TYPE_EPDG' ->
			"ePDG";
		?'3GPP_RO_SERVING-NODE-TYPE_HSGW' ->
			"hSGW";
		?'3GPP_RO_SERVING-NODE-TYPE_MME' ->
			"MME";
		?'3GPP_RO_SERVING-NODE-TYPE_TWAN' ->
			"TWAN"
	end,
	Info1 = Info#{"servingNodeType" => ServingNodeType},
	service_rating_ps3(PS, ServiceRating, Info1);
service_rating_ps2(PS, ServiceRating, Info) ->
	service_rating_ps3(PS, ServiceRating, Info).
%% @hidden
service_rating_ps3(#'3gpp_ro_PS-Information'{
		'Called-Station-Id' = [APN]} = PS,
		ServiceRating, Info) ->
	Info1 = Info#{"apn" => APN},
	service_rating_ps4(PS, ServiceRating, Info1);
service_rating_ps3(PS, ServiceRating, Info) ->
	service_rating_ps4(PS, ServiceRating, Info).
%% @hidden
service_rating_ps4(#'3gpp_ro_PS-Information'{
		'3GPP-Charging-Characteristics' = [Char]} = PS,
		ServiceRating, Info) ->
	Info1 = Info#{"chargingCharacteristics" => Char},
	service_rating_ps5(PS, ServiceRating, Info1);
service_rating_ps4(PS, ServiceRating, Info) ->
	service_rating_ps5(PS, ServiceRating, Info).
%% @hidden
service_rating_ps5(#'3gpp_ro_PS-Information'{
		'3GPP-RAT-Type' = [RatType]} = PS,
		ServiceRating, Info) ->
	Info1 = Info#{"ratType" => cse_codec:rat_type(RatType)},
	service_rating_ps6(PS, ServiceRating, Info1);
service_rating_ps5(PS, ServiceRating, Info) ->
	service_rating_ps6(PS, ServiceRating, Info).
%% @hidden
service_rating_ps6(#'3gpp_ro_PS-Information'{
		'PDP-Address' = [PdpAddress]} = PS,
		ServiceRating, Info) ->
	Info1 = Info#{"pdpAddress" => inet:ntoa(PdpAddress)},
	service_rating_ps7(PS, ServiceRating, Info1);
service_rating_ps6(PS, ServiceRating, Info) ->
	service_rating_ps7(PS, ServiceRating, Info).
%% @hidden
service_rating_ps7(#'3gpp_ro_PS-Information'{
		'3GPP-User-Location-Info' = [ULI]} = PS,
		ServiceRating, Info) ->
	case cse_diameter:user_location(ULI) of
		{ok, UserLocation} ->
			Info1 = Info#{"userLocationinfo" => UserLocation},
			service_rating_ps8(PS, ServiceRating, Info1);
		{error, undefined} ->
			service_rating_ps8(PS, ServiceRating, Info)
	end;
service_rating_ps7(PS, ServiceRating, Info) ->
	service_rating_ps8(PS, ServiceRating, Info).
%% @hidden
service_rating_ps8(_PS, ServiceRating, Info)
		when map_size(Info) > 0 ->
	ServiceRating#{"serviceInformation" => Info};
service_rating_ps8(_PS, ServiceRating, _Info) ->
	ServiceRating.

%% @hidden
service_rating_mms([#'3gpp_ro_Service-Information'{
		'MMS-Information' = MMS}],
		#{"serviceInformation" := ServiceInfo} = ServiceRating) ->
	service_rating_mms1(MMS, ServiceRating, ServiceInfo);
service_rating_mms([#'3gpp_ro_Service-Information'{
		'MMS-Information' = MMS}], ServiceRating) ->
	service_rating_mms1(MMS, ServiceRating, #{});
service_rating_mms(_ServiceInformation, ServiceRating) ->
	ServiceRating.
%% @hidden
service_rating_mms1([#'3gpp_ro_MMS-Information'{
		'MM-Content-Type' = [#'3gpp_ro_MM-Content-Type'{
				'Type-Number' = Number,
				'Additional-Type-Information' = Info,
				'Content-Size' = Size,
				'Additional-Content-Information' = Add}]}] = MMS,
		ServiceRating, ServiceInfo) ->
	MmContentType1 = case type_number(Number) of
		TypeNumber when length(TypeNumber) > 0 ->
			#{"typeNumber" => TypeNumber};
		[] ->
			#{}
	end,
	MmContentType2 = case Info of
		[I] ->
			MmContentType1#{"additionalTypeInformation" => I};
		[] ->
			MmContentType1
	end,
	MmContentType3 = case Size of
		[S] ->
			MmContentType2#{"contentSize" => S};
		[] ->
			MmContentType2
	end,
	MmContentType4 = case content_info(Add) of
		ACI when length(ACI) > 0 ->
			MmContentType3#{"additionalContentInformation" => ACI};
		[] ->
			MmContentType3
	end,
	ServiceInfo1 = ServiceInfo#{"mmContentType" => MmContentType4},
	service_rating_mms2(MMS, ServiceRating, ServiceInfo1);
service_rating_mms1(MMS, ServiceRating, ServiceInfo) ->
	service_rating_mms2(MMS, ServiceRating, ServiceInfo).
%% @hidden
service_rating_mms2([#'3gpp_ro_MMS-Information'{
		'Content-Class' = [Class]}] = MMS,
		ServiceRating, Info) ->
	ContentClass = case Class of
		?'3GPP_RO_CONTENT-CLASS_TEXT' ->
			"text";
		?'3GPP_RO_CONTENT-CLASS_IMAGE-BASIC' ->
			"image-basic";
		?'3GPP_RO_CONTENT-CLASS_IMAGE-RICH' ->
			"image-rich";
		?'3GPP_RO_CONTENT-CLASS_VIDEO-BASIC' ->
			"video-basic";
		?'3GPP_RO_CONTENT-CLASS_VIDEO-RICH' ->
			"video-rich";
		?'3GPP_RO_CONTENT-CLASS_MEGAPIXEL' ->
			"megapixel";
		?'3GPP_RO_CONTENT-CLASS_CONTENT-BASIC' ->
			"content-basic";
		?'3GPP_RO_CONTENT-CLASS_CONTENT-RICH' ->
			"content-rich"
	end,
	Info1 = Info#{"contentClass" => ContentClass},
	service_rating_mms3(MMS, ServiceRating, Info1);
service_rating_mms2(MMS, ServiceRating, Info) ->
	service_rating_mms3(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms3([#'3gpp_ro_MMS-Information'{
		'Message-ID' = [MessageId]}] = MMS,
		ServiceRating, Info) ->
	Info1 = Info#{"messageId" => MessageId},
	service_rating_mms4(MMS, ServiceRating, Info1);
service_rating_mms3(MMS, ServiceRating, Info) ->
	service_rating_mms4(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms4([#'3gpp_ro_MMS-Information'{
		'Message-Type' = [Type]}] = MMS,
		ServiceRating, Info) ->
	MessageType = case Type of
		?'3GPP_RO_MESSAGE-TYPE_M-SEND-REQ' ->
			"m-send-req";
		?'3GPP_RO_MESSAGE-TYPE_M-SEND-CONF' ->
			"m-send-conf";
		?'3GPP_RO_MESSAGE-TYPE_M-NOTIFICATION-IND' ->
			"m-notification-ind";
		?'3GPP_RO_MESSAGE-TYPE_M-NOTIFYRESP-IND' ->
			"m-notifyresp-ind";
		?'3GPP_RO_MESSAGE-TYPE_M-RETRIEVE-CONF' ->
			"m-retrieve-conf";
		?'3GPP_RO_MESSAGE-TYPE_M-ACKNOWLEDGE-IND' ->
			"m-acknowledge-ind";
		?'3GPP_RO_MESSAGE-TYPE_M-DELIVERY-IND' ->
			"m-delivery-ind";
		?'3GPP_RO_MESSAGE-TYPE_M-READ-REC-IND' ->
			"m-read-rec-ind";
		?'3GPP_RO_MESSAGE-TYPE_M-READ-ORIG-IND' ->
			"m-read-orig-ind";
		?'3GPP_RO_MESSAGE-TYPE_M-FORWARD-REQ' ->
			"m-forward-req";
		?'3GPP_RO_MESSAGE-TYPE_M-FORWARD-CONF'->
			"m-forward-conf";
		?'3GPP_RO_MESSAGE-TYPE_M-MBOX-STORE-CONF' ->
			"m-mbox-store-conf";
		?'3GPP_RO_MESSAGE-TYPE_M-MBOX-VIEW-CONF' ->
			"m-mbox-view-conf";
		?'3GPP_RO_MESSAGE-TYPE_M-MBOX-UPLOAD-CONF' ->
			"m-mbox-upload-conf";
		?'3GPP_RO_MESSAGE-TYPE_M-MBOX-DELETE-CONF' ->
			"m-mbox-delete-conf"
	end,
	Info1 = Info#{"messageType" => MessageType},
	service_rating_mms5(MMS, ServiceRating, Info1);
service_rating_mms4(MMS, ServiceRating, Info) ->
	service_rating_mms5(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms5([#'3gpp_ro_MMS-Information'{
		'Message-Class' = [#'3gpp_ro_Message-Class'{
				'Class-Identifier' = ClassId,
				'Token-Text' = TokenText}]}] = MMS,
		ServiceRating, Info) ->
	MessageClass1 = case ClassId of
		[?'3GPP_RO_CLASS-IDENTIFIER_PERSONAL'] ->
			#{"classIdentifier" => "Personal"};
		[?'3GPP_RO_CLASS-IDENTIFIER_ADVERTISEMENT'] ->
			#{"classIdentifier" => "Advertisement"};
		[?'3GPP_RO_CLASS-IDENTIFIER_INFORMATIONAL'] ->
			#{"classIdentifier" => "Informational"};
		[?'3GPP_RO_CLASS-IDENTIFIER_AUTO'] ->
			#{"classIdentifier" => "Auto"};
		[] ->
			#{}
	end,
	MessageClass2 = case TokenText of
		[Text] ->
			MessageClass1#{"tokenText" => Text};
		[] ->
			MessageClass1
	end,
	Info1 = Info#{"messageClass" => MessageClass2},
	service_rating_mms6(MMS, ServiceRating, Info1);
service_rating_mms5(MMS, ServiceRating, Info) ->
	service_rating_mms6(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms6([#'3gpp_ro_MMS-Information'{
		'Message-Size' = [MessageSize]}] = MMS,
		ServiceRating, Info) ->
	Info1 = Info#{"messageSize" => MessageSize},
	service_rating_mms7(MMS, ServiceRating, Info1);
service_rating_mms6(MMS, ServiceRating, Info) ->
	service_rating_mms7(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms7([#'3gpp_ro_MMS-Information'{
		'Applic-ID' = [ApplicId]}] = MMS,
		ServiceRating, Info) ->
	Info1 = Info#{"applicId" => ApplicId},
	service_rating_mms8(MMS, ServiceRating, Info1);
service_rating_mms7(MMS, ServiceRating, Info) ->
	service_rating_mms8(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms8([#'3gpp_ro_MMS-Information'{
		'VAS-Id' = [VasId]}] = MMS,
		ServiceRating, Info) ->
	Info1 = Info#{"vasId" => VasId},
	service_rating_mms9(MMS, ServiceRating, Info1);
service_rating_mms8(MMS, ServiceRating, Info) ->
	service_rating_mms9(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms9([#'3gpp_ro_MMS-Information'{
		'VASP-Id' = [VaspId]}] = MMS,
		ServiceRating, Info) ->
	Info1 = Info#{"vaspId" => VaspId},
	service_rating_mms10(MMS, ServiceRating, Info1);
service_rating_mms9(MMS, ServiceRating, Info) ->
	service_rating_mms10(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms10([#'3gpp_ro_MMS-Information'{
		'Originator-Address' = [#'3gpp_ro_Originator-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
				'Address-Data' = [MSISDN]}]}] = MMS,
		ServiceRating, Info) ->
	OriginationId = #{"originationIdType" => "DN",
			"originationIdData" => binary_to_list(MSISDN)},
	ServiceRating1 = ServiceRating#{"originationId" => [OriginationId]},
	service_rating_mms11(MMS, ServiceRating1, Info);
service_rating_mms10([#'3gpp_ro_MMS-Information'{
		'Originator-Address' = [#'3gpp_ro_Originator-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_IMSI'],
				'Address-Data' = [IMSI]}]}] = MMS,
		ServiceRating, Info) ->
	OriginationId = #{"originationIdType" => "IMSI",
			"originationIdData" => binary_to_list(IMSI)},
	ServiceRating1 = ServiceRating#{"originationId" => [OriginationId]},
	service_rating_mms11(MMS, ServiceRating1, Info);
service_rating_mms10([#'3gpp_ro_MMS-Information'{
		'Originator-Address' = [#'3gpp_ro_Originator-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_EMAIL_ADDRESS'],
				'Address-Data' = [NAI]}]}] = MMS,
		ServiceRating, Info) ->
	OriginationId = #{"originationIdType" => "NAI",
			"originationIdData" => binary_to_list(NAI)},
	ServiceRating1 = ServiceRating#{"originationId" => [OriginationId]},
	service_rating_mms11(MMS, ServiceRating1, Info);
service_rating_mms10(MMS, ServiceRating, Info) ->
	service_rating_mms11(MMS, ServiceRating, Info).
%% @hidden
service_rating_mms11([#'3gpp_ro_MMS-Information'{
		'Recipient-Address' = RecipientAddress}],
		ServiceRating, Info) ->
	DestinationId = destination(RecipientAddress),
	ServiceRating1 = ServiceRating#{"destinationId" => DestinationId},
	service_rating_mms12(ServiceRating1, Info);
service_rating_mms11(_MMS, ServiceRating, Info) ->
	service_rating_mms12(ServiceRating, Info).
%% @hidden
service_rating_mms12(ServiceRating, Info)
		when map_size(Info) > 0 ->
	ServiceRating#{"serviceInformation" => Info};
service_rating_mms12(ServiceRating, _Info) ->
	ServiceRating.

%% @hidden
service_rating_vcs([#'3gpp_ro_Service-Information'{
		'VCS-Information' = VCS}],
		#{"serviceInformation" := Info} = ServiceRating) ->
	service_rating_vcs1(VCS, ServiceRating, Info);
service_rating_vcs([#'3gpp_ro_Service-Information'{
		'VCS-Information' = VCS}], ServiceRating) ->
	service_rating_vcs1(VCS, ServiceRating, #{});
service_rating_vcs(_ServiceInformation, ServiceRating) ->
	ServiceRating.

%% @hidden
service_rating_vcs1([#'3gpp_ro_VCS-Information'{
		'VLR-Number' = [Number]}] = _VCS,
		ServiceRating, Info) ->
	Info1 = Info#{"vlrNumber" => binary_to_list(Number)},
	ServiceRating#{"serviceInformation" => Info1};
service_rating_vcs1(_VCS, ServiceRating, _Info) ->
	ServiceRating.

%% @hidden
service_rating_reserve(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [RSU]}, ServiceRating, Acc) ->
	case rsu(RSU) of
		ResquestedUnit when map_size(ResquestedUnit) > 0 ->
			[ServiceRating#{"requestSubType" => "RESERVE",
					"requestedUnit" => ResquestedUnit} | Acc];
		_ResquestedUnit ->
			[ServiceRating#{"requestSubType" => "RESERVE"} | Acc]
	end;
service_rating_reserve(#'3gpp_ro_Multiple-Services-Credit-Control'{
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
%% @doc Build CCA `MSCC' from Nrf `ServiceRating'.
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
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([SI], [], [#{"serviceId" := SI,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([], [RG], [#{"ratingGroup" := RG,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Rating-Group' = [RG],
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([], [], [#{"resultCode" := ResultCode} = ServiceRating | _],
		{FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
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

-spec diameter_answer(MSCC, ResultCode, RequestType, RequestNum) -> Result
	when
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		ResultCode :: pos_integer(),
		RequestType :: integer(),
		RequestNum :: integer(),
		Result :: #'3gpp_ro_CCA'{}.
%% @doc Build CCA response.
%% @hidden
diameter_answer(MSCC, ResultCode, RequestType, RequestNum) ->
	#'3gpp_ro_CCA'{'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Multiple-Services-Credit-Control' = MSCC,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNum,
			'Result-Code' = ResultCode}.

-spec diameter_error(ResultCode, RequestType, RequestNum) -> Reply
	when
		ResultCode :: pos_integer(),
		RequestType :: integer(),
		RequestNum :: integer(),
		Reply :: #'3gpp_ro_CCA'{}.
%% @doc Build CCA response indicating an operation failure.
%% @hidden
diameter_error(ResultCode, RequestType, RequestNum) ->
	#'3gpp_ro_CCA'{'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Result-Code' = ResultCode,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNum}.

-spec result_code(ResultCode) -> Result
	when
		ResultCode :: string(),
		Result :: pos_integer().
%% @doc Convert a Nrf ResultCode to a Diameter ResultCode
%% @hidden
% 3GPP TS 32.291 6.1.7.3-1
result_code("CHARGING_FAILED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED';
result_code("RE_AUTHORIZATION_FAILED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("CHARGING_NOT_APPLICABLE") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_CONTROL_NOT_APPLICABLE';
result_code("USER_UNKNOWN") ->
	?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN';
result_code("END_USER_REQUEST_DENIED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("QUOTA_LIMIT_REACHED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED';
% 3GPP TS 32.291 6.1.6.3.14-1
result_code("SUCCESS") ->
	?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
result_code("END_USER_SERVICE_DENIED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("QUOTA_MANAGEMENT_NOT_APPLICABLE") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_CONTROL_NOT_APPLICABLE';
result_code("END_USER_SERVICE_REJECTED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("RATING_FAILED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED';
% 3GPP TS 29.500 5.2.7.2-1
result_code("SYSTEM_FAILURE") ->
	?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY';
result_code(_) ->
	?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY'.

-spec message_parties(ServiceInformation) -> Result
	when
		ServiceInformation :: [#'3gpp_ro_Service-Information'{}],
		Result :: {Originator, Recipient},
		Originator :: string(),
		Recipient :: string().
%% @doc Extract message party addresses.
%% @hidden
message_parties([#'3gpp_ro_Service-Information'{
		'MMS-Information' = [#'3gpp_ro_MMS-Information'{
				'Originator-Address' = OriginatorAddress,
				'Recipient-Address' = RecipientAddress}]}]) ->
	{address(OriginatorAddress), address(RecipientAddress)};
message_parties([#'3gpp_ro_Service-Information'{
		'MMS-Information' = []}]) ->
	{[], []};
message_parties([]) ->
	{[], []}.

%% @hidden
address([#'3gpp_ro_Originator-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
		'Address-Data' = [Data]} | _T]) ->
	"msisdn-" ++ binary_to_list(Data);
address([#'3gpp_ro_Originator-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_IMSI'],
		'Address-Data' = [Data]} | _T]) ->
	"imsi-" ++ binary_to_list(Data);
address([#'3gpp_ro_Originator-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_EMAIL_ADDRESS'],
		'Address-Data' = [Data]} | _T]) ->
	"nai-" ++ binary_to_list(Data);
address([#'3gpp_ro_Recipient-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
		'Address-Data' = [Data]} | _T]) ->
	"msisdn-" ++ binary_to_list(Data);
address([#'3gpp_ro_Recipient-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_IMSI'],
		'Address-Data' = [Data]} | _T]) ->
	"imsi-" ++ binary_to_list(Data);
address([#'3gpp_ro_Recipient-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_EMAIL_ADDRESS'],
		'Address-Data' = [Data]} | _T]) ->
	"nai-" ++ binary_to_list(Data);
address([_H | T]) ->
	address(T);
address([]) ->
	[].

%% @hidden
destination(RecipientAddress) ->
	destination(RecipientAddress, []).
%% @hidden
destination([#'3gpp_ro_Recipient-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
		'Address-Data' = [MSISDN]} | T], Acc) ->
	DestinationId = #{"destinationIdType" => "DN",
			"destinationIdData" => binary_to_list(MSISDN)},
	destination(T, [DestinationId | Acc]);
destination([#'3gpp_ro_Recipient-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_IMSI'],
		'Address-Data' = [IMSI]} | T], Acc) ->
	DestinationId = #{"destinationIdType" => "IMSI",
			"destinationIdData" => binary_to_list(IMSI)},
	destination(T, [DestinationId | Acc]);
destination([#'3gpp_ro_Recipient-Address'{
		'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_EMAIL_ADDRESS'],
		'Address-Data' = [NAI]} | T], Acc) ->
	DestinationId = #{"destinationIdType" => "NAI",
			"destinationIdData" => binary_to_list(NAI)},
	destination(T, [DestinationId | Acc]);
destination([], Acc) ->
	lists:reverse(Acc).

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
	Data3 = maps:remove(nrf_req_url, Data2),
	Data4 = maps:remove(nrf_http, Data3),
	maps:remove(nrf_reqid, Data4).

%% @hidden
type_number([?'3GPP_RO_TYPE-NUMBER_ALL_ALL']) ->
	"*/*";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_ALL']) ->
	"text/*";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_HTML']) ->
	"text/html";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_PLAIN']) ->
	"text/plain";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_X-HDML']) ->
	"text/x-hdml";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_X-TTML']) ->
	"text/x-ttml";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_X-VCALENDAR']) ->
	"text/x-vCalendar";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_X-VCARD']) ->
	"text/x-vCard";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_WML']) ->
	"text/vnd.wap.wml";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_WMLSCRIPT']) ->
	"text/vnd.wap.wmlscript";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_WTA-EVENT']) ->
	"text/vnd.wap.wta-event";
type_number([?'3GPP_RO_TYPE-NUMBER_MULTIPART_MIXED']) ->
	"multipart/mixed";
type_number([?'3GPP_RO_TYPE-NUMBER_MULTIPART_FORM-DATA']) ->
	"multipart/form-data";
type_number([?'3GPP_RO_TYPE-NUMBER_MULTIPART_BYTERANTES']) ->
	"multipart/byterantes";
type_number([?'3GPP_RO_TYPE-NUMBER_MULTIPART_ALTERNATIVE']) ->
	"multipart/alternative";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_ALL']) ->
	"application/*";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_JAVA-VM']) ->
	"application/java-vm";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-WWW-FORM-URLENCODED']) ->
	"application/x-www-form-urlencoded"; 
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-HDMLC']) ->
	"application/x-hdmlc";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_WMLC']) ->
	"application/vnd.wap.wmlc";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_WMLSCRIPTC']) ->
	"application/vnd.wap.wmlscriptc";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_WTA-EVENTC']) ->
	"application/vnd.wap.wta-eventc";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_UAPROF']) ->
	"application/vnd.wap.uaprof";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_WTLS-CA-CERTIFICATE']) ->
	"application/vnd.wap.wtls-ca-certificate";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_WTLS-USER-CERTIFICATE']) ->
	"application/vnd.wap.wtls-user-certificate";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-X509-CA-CERT']) ->
	"application/x-x509-ca-cert";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-X509-USER-CERT']) ->
	"application/x-x509-user-cert";
type_number([?'3GPP_RO_TYPE-NUMBER_IMAGE_ALL']) ->
	"image/*";
type_number([?'3GPP_RO_TYPE-NUMBER_IMAGE_GIF']) ->
	"image/gif";
type_number([?'3GPP_RO_TYPE-NUMBER_IMAGE_JPEG']) ->
	"image/jpeg";
type_number([?'3GPP_RO_TYPE-NUMBER_IMAGE_TIFF']) ->
	"image/tiff";
type_number([?'3GPP_RO_TYPE-NUMBER_IMAGE_PNG']) ->
	"image/png";
type_number([?'3GPP_RO_TYPE-NUMBER_IMAGE_VND_WAP_WBMP']) ->
	"image/vnd.wap.wbmp";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MULTIPART_ALL']) ->
	"application/vnd.wap.multipart.*";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MULTIPART_MIXED']) ->
	"application/vnd.wap.multipart.mixed";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MULTIPART_FORM-DATA']) ->
	"application/vnd.wap.multipart.form-data";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MULTIPART_BYTERANGES']) ->
	"application/vnd.wap.multipart.byteranges";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MULTIPART_ALTERNATIVE']) ->
	"application/vnd.wap.multipart.alternative";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_XML']) ->
	"application/xml";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_XML']) ->
	"text/xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_WBXML']) ->
	"application/vnd.wap.wbxml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-X968-CROSS-CERT']) ->
	"application/x-x968-cross-cert";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-X968-CA-CERT']) ->
	"application/x-x968-ca-cert";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_X-X968-USER-CERT']) ->
	"application/x-x968-user-cert";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_SI']) ->
	"text/vnd.wap.si";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_SIC']) ->
	"application/vnd.wap.sic";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_SL']) ->
	"text/vnd.wap.sl";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_SLC']) ->
	"application/vnd.wap.slc";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_CO']) ->
	"text/vnd.wap.co";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_COC']) ->
	"application/vnd.wap.coc";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MULTIPART_RELATED']) ->
	"application/vnd.wap.multipart.related";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_SIA']) ->
	"application/vnd.wap.sia";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_VND_WAP_CONNECTIVITY-XML']) ->
	"text/vnd.wap.connectivity-xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_CONNECTIVITY-WBXML']) ->
	"application/vnd.wap.connectivity-wbxml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_PKCS7-MIME']) ->
	"application/pkcs7-mime";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_HASHED-CERTIFICATE']) ->
	"application/vnd.wap.hashed-certificate";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_CERT-RESPONSE']) ->
	"application/vnd.wap.cert-response"; 
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_XHTML_XML']) ->
	"application/xhtml+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_WML_XML']) ->
	"application/wml+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_CSS']) ->
	"text/css";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_MMS-MESSAGE']) ->
	"application/vnd.wap.mms-message";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_ROLLOVER-CERTIFICATE']) ->
	"application/vnd.wap.rollover-certificate";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_LOCC_WBXML']) ->
	"application/vnd.wap.locc+wbxml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_LOC_XML']) ->
	"application/vnd.wap.loc+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_SYNCML_DM_WBXML']) ->
	"application/vnd.syncml.dm+wbxml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_SYNCML_DM_XML']) ->
	"application/vnd.syncml.dm+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_SYNCML_NOTIFICATION']) ->
	"application/vnd.syncml.notification";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WAP_XHTML_XML']) ->
	"application/vnd.wap.xhtml+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WV_CSP_CIR']) ->
	"application/vnd.wv.csp.cir";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DD_XML']) ->
	"application/vnd.oma.dd+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DRM_MESSAGE']) ->
	"application/vnd.oma.drm.message";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DRM_CONTENT']) ->
	"application/vnd.oma.drm.content";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DRM_RIGHTS_XML']) ->
	"application/vnd.oma.drm.rights+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DRM_RIGHTS_WBXML']) ->
	"application/vnd.oma.drm.rights+wbxml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WV_CSP_XML']) ->
	"application/vnd.wv.csp+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_WV_CSP_WBXML']) ->
	"application/vnd.wv.csp+wbxml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_SYNCML_DS_NOTIFICATION']) ->
	"application/vnd.syncml.ds.notification";
type_number([?'3GPP_RO_TYPE-NUMBER_AUDIO_ALL']) ->
	"audio/*";
type_number([?'3GPP_RO_TYPE-NUMBER_VIDEO_ALL']) ->
	"video/*";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DD2_XML']) ->
	"application/vnd.oma.dd2+xml";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_MIKEY']) ->
	"application/mikey";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DCD']) ->
	"application/vnd.oma.dcd";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMA_DCDC']) ->
	"application/vnd.oma.dcdc";
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_X-VMESSAGE']) ->
	"text/x-vMessage";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_OMADS-EMAIL_WBXML']) ->
	"application/vnd.omads-email+wbxml"; 
type_number([?'3GPP_RO_TYPE-NUMBER_TEXT_X-VBOOKMARK']) ->
	"text/x-vBookmark";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_VND_SYNCML_DM_NOTIFICATION']) ->
	"application/vnd.syncml.dm.notification";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_OCTET-STREAM']) ->
	"application/octet-stream";
type_number([?'3GPP_RO_TYPE-NUMBER_APPLICATION_JSON']) ->
	"application/json";
type_number([]) ->
	[].

%% @hidden
content_info(AdditionalContentInformation) ->
	content_info(AdditionalContentInformation, []).
%% @hidden
content_info([#'3gpp_ro_Additional-Content-Information'{
		'Type-Number' = Number,
		'Additional-Type-Information' = Info,
		'Content-Size' = Size} | T], Acc) ->
	ContentInfo1 = case type_number(Number) of
		Mime when length(Mime) > 0 ->
			#{"typeNumber" => Mime};
		[] ->
			#{}
	end,
	ContentInfo2 = case Info of
		[ATI] ->
			ContentInfo1#{"additionalTypeInformation" => ATI};
		[] ->
			ContentInfo1
	end,
	ContentInfo3 = case Size of
		[N] ->
			ContentInfo2#{"contentSize" => N};
		[] ->
			ContentInfo2
	end,
	content_info(T, [ContentInfo3 | Acc]);
content_info([], Acc) ->
	lists:reverse(Acc).

