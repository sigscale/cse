%%% cse_slp_prepaid_diameter_ims_fsm.erl
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
%%% 	point interface, using the
%%% 	<a href="https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0">
%%% 	Nrf_Rating</a> API, with a remote <i>Rating Function</i>.
%%%
%%% 	This SLP specifically handles IP Multimedia Subsystem (IMS) voice
%%% 	service usage with `Service-Context-Id' of `32260@3gpp.org', and
%%% 	Circuit Switched (CS) Voice Call Service (VCS) (through a proxy)
%%% 	service usage with `Service-Context-Id' of `32276@3gpp.org'.
%%%
%%% 	== Message Sequence ==
%%% 	The diagram below depicts the normal sequence of exchanged messages:
%%%
%%% 	<img alt="message sequence chart" src="ocf-nrf-msc.svg" />
%%%
%%% 	== State Transitions ==
%%% 	The following diagram depicts the states, and events which drive state
%%% 	transitions, in the OCF finite state machine (FSM):
%%%
%%% 	<img alt="state machine" src="prepaid-diameter-voice.svg" />
%%%
-module(cse_slp_prepaid_diameter_ims_fsm).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Refath Wadood <refath@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, authorize_origination_attempt/3,
		terminating_call_handling/3,
		collect_information/3, analyse_information/3,
		o_alerting/3, t_alerting/3, active/3]).
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
-define(IMS_CONTEXTID, "32260@3gpp.org").
-define(VCS_CONTEXTID, "32276@3gpp.org").
-define(SERVICENAME, "Prepaid Voice").
-define(FSM_LOGNAME, prepaid).
-define(NRF_LOGNAME, rating).

-type state() :: null
		| authorize_origination_attempt | terminating_call_handling
		| collect_information | analyse_information
		| o_alerting | t_alerting | active.

-type statedata() :: #{start := pos_integer(),
		from => pid(),
		session_id => binary(),
		context => string(),
		mscc => [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		service_info => [#'3gpp_ro_Service-Information'{}],
		req_type => pos_integer(),
		reqno =>  integer(),
		ohost => binary(),
		orealm => binary(),
		drealm => binary(),
		imsi => [$0..$9],
		msisdn => string(),
		direction => originating | terminating,
		called => [$0..$9],
		calling => [$0..$9],
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
%%  The cse_slp_prepaid_diameter_ims_fsm gen_statem callbacks
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
null({call, _From}, #'3gpp_ro_CCR'{
		'Service-Information' = [#'3gpp_ro_Service-Information'{
				'IMS-Information' = [#'3gpp_ro_IMS-Information'{
						'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE']}]}]},
		Data) ->
	NewData = Data#{direction => originating},
	{next_state, authorize_origination_attempt, NewData, postpone};
null({call, _From}, #'3gpp_ro_CCR'{
		'Service-Information' = [#'3gpp_ro_Service-Information'{
				'IMS-Information' = [#'3gpp_ro_IMS-Information'{
						'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE']}]}]},
		Data) ->
	NewData = Data#{direction => terminating},
	{next_state, terminating_call_handling, NewData, postpone}.

-spec authorize_origination_attempt(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_origination_attempt</em> state.
%% @private
authorize_origination_attempt(enter, _EventContent, _Data) ->
	keep_state_and_data;
authorize_origination_attempt({call, From},
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
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From, session_id => SessionId,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, service_info => ServiceInformation,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			reqno => RequestNum, req_type => RequestType},
	nrf_start(NewData);
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := LogHTTP,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType, mscc := MSCC,
				called := CalledDN} = Data) ->
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
				case {ResultCode, CalledDN} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', Destination}
							when length(Destination) > 0 ->
						{next_state, analyse_information, NewData1, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', _} ->
						{next_state, collect_information, NewData1, Actions};
					{_, _} ->
						{next_state, null, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, authorize_origination_attempt}]),
					Reply1 = diameter_error(?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{{error, Partial, Remaining}, Location} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			ResultCode1 = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
			Actions1 = [{reply, From, Reply1}],
			{next_state, null, NewData, Actions1}
	end;
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
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
			{state, authorize_origination_attempt}]),
	Reply = diameter_error(?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
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
			{state, authorize_origination_attempt}]),
	Reply = diameter_error(?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_origination_attempt}]),
	Reply = diameter_error(?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_release, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, authorize_origination_attempt}]),
	Reply = diameter_error(?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions}.

-spec terminating_call_handling(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>terminating_call_handling</em> state.
%%.
%% 	We handle `CCR-U' in this state because we may have entered
%% 	from another SLP which consumed the `CCR-I'.
%%.
%% @private
terminating_call_handling(enter, _EventContent, _Data) ->
	keep_state_and_data;
terminating_call_handling({call, From},
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
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From, session_id => SessionId,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, service_info => ServiceInformation,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			reqno => RequestNum, req_type => RequestType},
	nrf_start(NewData);
terminating_call_handling({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
				'Destination-Realm' = DRealm,
				'CC-Request-Type' = RequestType,
				'Service-Context-Id' = SvcContextId,
				'CC-Request-Number' = RequestNum,
				'Subscription-Id' = SubscriptionId,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From, session_id => SessionId,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, service_info => ServiceInformation,
			ohost => OHost, orealm => ORealm, drealm => DRealm,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
terminating_call_handling({call, From},
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
terminating_call_handling({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum},
		#{session_id := SessionId} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST' ->
	NewData = Data#{from => From,
			reqno => RequestNum, req_type => RequestType},
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_start ->
			{next_state, null, NewData, Actions};
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_start ->
			{next_state, null, NewData, Actions};
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{nrf_start, {RequestId, {{Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := LogHTTP,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				req_type := RequestType, mscc := MSCC} = Data) ->
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
				case {ResultCode, is_rsu(MSCC)} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true} ->
						{next_state, t_alerting, NewData1, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false} ->
						{keep_state, NewData1, Actions};
					{_, _} ->
						{next_state, null, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, terminating_call_handling}]),
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
					{state, terminating_call_handling}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{nrf_update, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
				case {ResultCode, is_rsu(MSCC), is_usu(MSCC)} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', _, true} ->
						{next_state, active, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true, false} ->
						{next_state, t_alerting, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false, false} ->
						{keep_state, NewData, Actions};
					{_, _, _} ->
						{next_state, null, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, terminating_call_handling}]),
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
					{state, terminating_call_handling}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
terminating_call_handling(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType,
				mscc := MSCC} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC, ResultCode, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, terminating_call_handling}]),
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
					{state, terminating_call_handling}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
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
			{state, terminating_call_handling}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, terminating_call_handling}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, terminating_call_handling}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end.

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
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			calling => CallingDN, called => CalledDN,
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
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType, mscc := MSCC,
				called := CalledDN} = Data) ->
	log_nrf(ecs_http(Version, 200, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {ResultCode, is_rsu(MSCC), is_usu(MSCC), CalledDN} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', _, true, _} ->
						{next_state, active, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true, false, _} ->
						{next_state, o_alerting, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false,
							false, Destination} when length(Destination) > 0 ->
						{next_state, analyse_information, NewData, Actions};
					{_, _, _, _} ->
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
					{state, collect_information}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
collect_information(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
				req_type := RequestType, reqno := RequestNum} = Data)
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
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
				case {ResultCode, is_rsu(MSCC), is_usu(MSCC)} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', _, true} ->
						{next_state, active, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true, false} ->
						{next_state, o_alerting, NewData, Actions};
					{_, _, _}->
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
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
				req_type := RequestType, reqno := RequestNum} = Data)
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
o_alerting({call, From},
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
o_alerting({call, From},
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
o_alerting(cast,
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
o_alerting(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast,
		{nrf_update, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
					{_, false} ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, o_alerting}]),
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
					{state, o_alerting}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
o_alerting(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
							{state, o_alerting}]),
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
					{state, o_alerting}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast,
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
			{state, o_alerting}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, o_alerting}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end.

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
t_alerting({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location)  ->
	NewData = Data#{from => From,
			mscc => MSCC, service_info => ServiceInformation,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
t_alerting({call, From},
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
t_alerting(cast,
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
t_alerting(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast,
		{nrf_update, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
					{_, false} ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, t_alerting}]),
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
					{state, t_alerting}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
t_alerting(cast,
		{nrf_release, {RequestId, {{Version, 200, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
							{state, t_alerting}]),
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
					{state, t_alerting}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast,
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
			{state, t_alerting}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_location := Location,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = remove_nrf(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {location, Location}, {slpi, self()},
			{origin_host, OHost}, {origin_realm, ORealm},
			{state, t_alerting}]),
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
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 403, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
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
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
				nrf_uri := URI, nrf_location := Location,
				nrf_http := LogHTTP, ohost := OHost, orealm := ORealm,
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
				req_type := RequestType, reqno := RequestNum} = Data)
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
nrf_start1(JSON, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
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
nrf_update1(JSON, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON1 = JSON#{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	nrf_update2(Now, JSON1, Data).
%% @hidden
nrf_update2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
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
nrf_release1(JSON, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON1 = JSON#{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	nrf_release2(Now, JSON1, Data).
%% @hidden
nrf_release2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, 
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
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
is_rsu([#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [_RSU]} | _]) ->
	true;
is_rsu([#'3gpp_ro_Multiple-Services-Credit-Control'{} | T]) ->
	is_rsu(T);
is_rsu([]) ->
	false.

%% @hidden
rsu(#'3gpp_ro_Requested-Service-Unit'{
		'CC-Time' = [CCTime]} = RSU) ->
	rsu1(RSU, #{"time" => CCTime});
rsu(RSU) ->
	rsu1(RSU, #{}).
%% @hidden
rsu1(#'3gpp_ro_Requested-Service-Unit'{
		'CC-Total-Octets' = [CCTotalOctets]} = RSU, Acc) ->
	rsu2(RSU, Acc#{"totalVolume" => CCTotalOctets});
rsu1(RSU, Acc) ->
	rsu2(RSU, Acc).
%% @hidden
rsu2(#'3gpp_ro_Requested-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets]} = RSU, Acc) ->
	rsu3(RSU, Acc#{"downlinkVolume" => CCOutputOctets});
rsu2(RSU, Acc) ->
	rsu3(RSU, Acc).
%% @hidden
rsu3(#'3gpp_ro_Requested-Service-Unit'{
		'CC-Input-Octets' = [CCInputOctets]} = RSU, Acc) ->
	rsu4(RSU, Acc#{"uplinkVolume" => CCInputOctets});
rsu3(RSU, Acc) ->
	rsu4(RSU, Acc).
%% @hidden
rsu4(#'3gpp_ro_Requested-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]}, Acc) ->
	Acc#{"serviceSpecificUnit" => CCSpecUnits};
rsu4(_RSU, Acc) ->
	Acc.

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
		'CC-Time' = [CCTime]} = USU) ->
	usu1(USU, #{"time" => CCTime});
usu(USU) ->
	usu1(USU, #{}).
%% @hidden
usu1(#'3gpp_ro_Used-Service-Unit'{
		'CC-Total-Octets' = [CCTotalOctets]} = USU, Acc) ->
	usu2(USU, Acc#{"totalVolume" => CCTotalOctets});
usu1(USU, Acc) ->
	usu2(USU, Acc).
%% @hidden
usu2(#'3gpp_ro_Used-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets]} = USU, Acc) ->
	usu3(USU, Acc#{"downlinkVolume" => CCOutputOctets});
usu2(USU, Acc) ->
	usu3(USU, Acc).
%% @hidden
usu3(#'3gpp_ro_Used-Service-Unit'{
		'CC-Input-Octets' = [CCInputOctets]} = USU, Acc) ->
	usu4(USU, Acc#{"uplinkVolume" => CCInputOctets});
usu3(USU, Acc) ->
	usu4(USU, Acc).
%% @hidden
usu4(#'3gpp_ro_Used-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]}, Acc) ->
	Acc#{"serviceSpecificUnit" => CCSpecUnits};
usu4(_USU, Acc) ->
	Acc.

%% @hidden
gsu({ok, #{"time" := CCTime} = GSU})
		when is_integer(CCTime), CCTime > 0 ->
	gsu1(GSU, #'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [CCTime]});
gsu({ok, GSU}) when map_size(GSU) > 0 ->
	gsu1(GSU, #'3gpp_ro_Granted-Service-Unit'{});
gsu(_) ->
	[].
%% @hidden
gsu1(#{"totalVolume" := CCTotalOctets} = GSU, Acc)
		when is_integer(CCTotalOctets), CCTotalOctets > 0 ->
	gsu2(GSU, Acc#'3gpp_ro_Granted-Service-Unit'{
			'CC-Total-Octets' = [CCTotalOctets]});
gsu1(GSU, Acc) ->
	gsu2(GSU, Acc).
%% @hidden
gsu2(#{"downlinkVolume" := CCOutputOctets} = GSU, Acc)
		when is_integer(CCOutputOctets), CCOutputOctets > 0 ->
	gsu3(GSU, Acc#'3gpp_ro_Granted-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets]});
gsu2(GSU, Acc) ->
	gsu3(GSU, Acc).
%% @hidden
gsu3(#{"uplinkVolume" := CCInputOctets} = GSU, Acc)
		when is_integer(CCInputOctets), CCInputOctets > 0 ->
	gsu4(GSU, Acc#'3gpp_ro_Granted-Service-Unit'{
		'CC-Input-Octets' = [CCInputOctets]});
gsu3(GSU, Acc) ->
	gsu4(GSU, Acc).
%% @hidden
gsu4(#{"serviceSpecificUnit" := CCSpecUnits}, Acc)
		when is_integer(CCSpecUnits), CCSpecUnits > 0 ->
	[Acc#'3gpp_ro_Granted-Service-Unit'{
			'CC-Service-Specific-Units' = [CCSpecUnits]}];
gsu4(_GSU, Acc) ->
	[Acc].

-spec service_rating(Data) -> ServiceRating
	when
		Data :: statedata(),
		ServiceRating :: [map()].
%% @doc Build a `serviceRating' object.
%% @hidden
service_rating(#{mscc := MSCC} = Data) ->
	service_rating(MSCC, Data, []).
%% @hidden
service_rating([MSCC | T],
		#{context := ServiceContextId,
		service_info := ServiceInformation} = Data, Acc) ->
	SR1 = #{"serviceContextId" => ServiceContextId},
	SR2 = service_rating_si(MSCC, SR1),
	SR3 = service_rating_rg(MSCC, SR2),
	SR4 = service_rating_ims(ServiceInformation, SR3),
	SR5 = service_rating_vcs(ServiceInformation, SR4),
	Acc1 = service_rating_rsu(MSCC, SR5, Acc),
	Acc2 = service_rating_usu(MSCC, SR5, Acc1),
	service_rating(T, Data, Acc2);
service_rating([], _Data, Acc) ->
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
service_rating_ims([#'3gpp_ro_Service-Information'{
		'IMS-Information' = IMS}], ServiceRating) ->
	service_rating_ims1(IMS, ServiceRating);
service_rating_ims(_ServiceInformation, ServiceRating) ->
	ServiceRating.
%% @hidden
service_rating_ims1([#'3gpp_ro_IMS-Information'{
		'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS'}] = IMS,
		ServiceRating) ->
	Info = #{"nodeFunctionality" => "AS"},
	service_rating_ims2(IMS, ServiceRating, Info);
service_rating_ims1(IMS, ServiceRating) ->
	service_rating_ims2(IMS, ServiceRating, #{}).
%% @hidden
service_rating_ims2([#'3gpp_ro_IMS-Information'{
		'Role-Of-Node' = [Role]}] = IMS, ServiceRating, Info) ->
	RoleOfNode = case Role of
		?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE' ->
			"ORIGINATING";
		?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE' ->
			"TERMINATING";
		?'3GPP_RO_ROLE-OF-NODE_FORWARDING_ROLE' ->
			"FORWARDING"
	end,
	Info1 = Info#{"roleOfNode" => RoleOfNode},
	service_rating_ims3(IMS, ServiceRating, Info1);
service_rating_ims2(IMS, ServiceRating, Info) ->
	service_rating_ims3(IMS, ServiceRating, Info).
%% @hidden
service_rating_ims3([#'3gpp_ro_IMS-Information'{
		'IMS-Visited-Network-Identifier' = [VisitedNetwork]}] = IMS,
		ServiceRating, Info) ->
	Info1 = Info#{"visitedNetworkIdentifier" => VisitedNetwork},
	service_rating_ims4(IMS, ServiceRating, Info1);
service_rating_ims3(IMS, ServiceRating, Info) ->
	service_rating_ims4(IMS, ServiceRating, Info).
%% @hidden
service_rating_ims4([#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [<<"sip:", NAI/binary>>]}] = IMS,
		ServiceRating, Info) ->
	OriginationId = #{"originationIdType" => "NAI",
			"originationIdData" => binary_to_list(NAI)},
	ServiceRating1 = ServiceRating#{"originationId" => [OriginationId]},
	service_rating_ims5(IMS, ServiceRating1, Info);
service_rating_ims4([#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [<<"tel:", DN/binary>>]}] = IMS,
		ServiceRating, Info) ->
	OriginationId = #{"originationIdType" => "DN",
			"originationIdData" => binary_to_list(DN)},
	ServiceRating1 = ServiceRating#{"originationId" => [OriginationId]},
	service_rating_ims5(IMS, ServiceRating1, Info);
service_rating_ims4(IMS, ServiceRating, Info) ->
	service_rating_ims5(IMS, ServiceRating, Info).
%% @hidden
service_rating_ims5([#'3gpp_ro_IMS-Information'{
		'Called-Party-Address' = [<<"sip:", NAI/binary>>]}],
		ServiceRating, Info) ->
	DestinationId = #{"destinationIdType" => "NAI",
			"destinationIdData" => binary_to_list(NAI)},
	ServiceRating1 = ServiceRating#{"destinationId" => [DestinationId]},
	service_rating_ims6(ServiceRating1, Info);
service_rating_ims5([#'3gpp_ro_IMS-Information'{
		'Called-Party-Address' = [<<"tel:", DN/binary>>]}],
		ServiceRating, Info) ->
	DestinationId = #{"destinationIdType" => "DN",
			"destinationIdData" => binary_to_list(DN)},
	ServiceRating1 = ServiceRating#{"destinationId" => [DestinationId]},
	service_rating_ims6(ServiceRating1, Info);
service_rating_ims5(_IMS, ServiceRating, Info) ->
	service_rating_ims6(ServiceRating, Info).
%% @hidden
service_rating_ims6(ServiceRating, Info)
		when map_size(Info) > 0 ->
	ServiceRating#{"serviceInformation" => Info};
service_rating_ims6(ServiceRating, _Info) ->
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
		'Network-Call-Reference-Number' = [RN]}] = VCS,
		ServiceRating, Info) ->
	Info1 = Info#{"callReferenceNumber" => binary_to_list(RN)},
	service_rating_vcs2(VCS, ServiceRating, Info1);
service_rating_vcs1(VCS, ServiceRating, Info) ->
	service_rating_vcs2(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs2([#'3gpp_ro_VCS-Information'{
		'MSC-Address' = [Address]}] = VCS,
		ServiceRating, Info) ->
	Info1 = Info#{"mscAddress" => binary_to_list(Address)},
	service_rating_vcs3(VCS, ServiceRating, Info1);
service_rating_vcs2(VCS, ServiceRating, Info) ->
	service_rating_vcs3(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs3([#'3gpp_ro_VCS-Information'{
		'ISUP-Location-Number' = [Number]}] = VCS,
		ServiceRating, Info) ->
	Info1 = Info#{"locationNumber" => binary_to_list(Number)},
	service_rating_vcs4(VCS, ServiceRating, Info1);
service_rating_vcs3(VCS, ServiceRating, Info) ->
	service_rating_vcs4(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs4([#'3gpp_ro_VCS-Information'{
		'VLR-Number' = [Number]}] = VCS,
		ServiceRating, Info) ->
	Info1 = Info#{"vlrNumber" => binary_to_list(Number)},
	service_rating_vcs5(VCS, ServiceRating, Info1);
service_rating_vcs4(VCS, ServiceRating, Info) ->
	service_rating_vcs5(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs5([#'3gpp_ro_VCS-Information'{
		'ISUP-Cause' = [C]}] = VCS,
		ServiceRating, Info) ->
	Cause1 = case C#'3gpp_ro_ISUP-Cause'.'ISUP-Cause-Location' of
		[0] ->
			#{"causeLocation" => "user"};
		[1] ->
			#{"causeLocation" => "local_private"};
		[2] ->
			#{"causeLocation" => "local_public"};
		[3] ->
			#{"causeLocation" => "transit"};
		[4] ->
			#{"causeLocation" => "remote_public"};
		[5] ->
			#{"causeLocation" => "remote_private"};
		[7] ->
			#{"causeLocation" => "international"};
		[10] ->
			#{"causeLocation" => "beyond"};
		_ ->
			#{}
	end,
	Cause2 = case C#'3gpp_ro_ISUP-Cause'.'ISUP-Cause-Value' of
		[Value] when is_integer(Value) ->
			Cause1#{"causeValue" => Value};
		_ ->
			Cause1
	end,
	Cause3 = case C#'3gpp_ro_ISUP-Cause'.'ISUP-Cause-Diagnostics'  of
		[Diag] ->
			Cause2#{"causeDiagnostics" => binary_to_list(Diag)};
		_ ->
			Cause2
	end,
	Info1 = Info#{"isupCause" => Cause3},
	service_rating_vcs6(VCS, ServiceRating, Info1);
service_rating_vcs5(VCS, ServiceRating, Info) ->
	service_rating_vcs6(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs6([#'3gpp_ro_VCS-Information'{
		'Start-Time' = [Time]}] = VCS,
		ServiceRating, Info) ->
	TS = cse_rest:date(Time),
	Info1 = Info#{"startTime" => cse_rest:iso8601(TS)},
	service_rating_vcs7(VCS, ServiceRating, Info1);
service_rating_vcs6(VCS, ServiceRating, Info) ->
	service_rating_vcs7(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs7([#'3gpp_ro_VCS-Information'{
		'Start-of-Charging' = [Time]}] = VCS,
		ServiceRating, Info) ->
	TS = cse_rest:date(Time),
	Info1 = Info#{"startOfCharging" => cse_rest:iso8601(TS)},
	service_rating_vcs8(VCS, ServiceRating, Info1);
service_rating_vcs7(VCS, ServiceRating, Info) ->
	service_rating_vcs8(VCS, ServiceRating, Info).
%% @hidden
service_rating_vcs8([#'3gpp_ro_VCS-Information'{
		'Stop-Time' = [Time]}],
		ServiceRating, Info) ->
	TS = cse_rest:date(Time),
	Info1 = Info#{"startOfCharging" => cse_rest:iso8601(TS)},
	service_rating_vcs9(ServiceRating, Info1);
service_rating_vcs8(_VCS, ServiceRating, Info) ->
	service_rating_vcs9(ServiceRating, Info).
%% @hidden
service_rating_vcs9(ServiceRating, Info) ->
	ServiceRating#{"serviceInformation" => Info}.

%% @hidden
service_rating_rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [RSU]}, ServiceRating, Acc) ->
	case rsu(RSU) of
		ResquestedUnit when map_size(ResquestedUnit) > 0 ->
			[ServiceRating#{"requestSubType" => "RESERVE",
					"requestedUnit" => ResquestedUnit} | Acc];
		_ResquestedUnit ->
			[ServiceRating#{"requestSubType" => "RESERVE"} | Acc]
	end;
service_rating_rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = []}, _ServiceRating, Acc) ->
	Acc.

%% @hidden
service_rating_usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [USU]}, ServiceRating, Acc) ->
	case usu(USU) of
		UsedUnit when map_size(UsedUnit) > 0 ->
			[ServiceRating#{"requestSubType" => "DEBIT",
					"consumedUnit" => usu(USU)} | Acc];
		_UsedUnit ->
			Acc
	end;
service_rating_usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
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
	#'3gpp_ro_CCA'{'Multiple-Services-Credit-Control' = MSCC,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
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
result_code("SUCCESS") ->
	?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
result_code("END_USER_SERVICE_DENIED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("QUOTA_LIMIT_REACHED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED';
result_code("QUOTA_MANAGEMENT_NOT_APPLICABLE") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_CONTROL_NOT_APPLICABLE';
result_code("USER_UNKNOWN") ->
	?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN';
result_code("END_USER_SERVICE_REJECTED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("RATING_FAILED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED'.

-spec call_parties(ServiceInformation) -> Result
	when
		ServiceInformation :: [#'3gpp_ro_Service-Information'{}],
		Result :: {Calling, Called},
		Calling :: [Digit],
		Called :: [Digit],
		Digit :: $0..$9.
%% @doc Extract call party addresses.
%% @hidden
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [],
		'Called-Party-Address' = [CalledParty]}]}]) ->
	{[], address(CalledParty)};
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [CallingParty],
		'Called-Party-Address' = []}]}]) ->
	{address(CallingParty), []};
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [CallingParty],
		'Called-Party-Address' = [CalledParty]}]}]) ->
	{address(CallingParty), address(CalledParty)};
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = []}]) ->
	{[], []};
call_parties([]) ->
	{[], []}.

%% @hidden
address(<<"tel:", Dest/binary>>) ->
	binary_to_list(Dest);
address(Dest) ->
	binary_to_list(Dest).

-spec ecs_http(MIME, Body) -> HTTP
	when
		MIME :: string(),
		Body :: binary() | iolist(),
		HTTP :: map().
%% @doc Construct ECS JSON `map()' for Nrf request.
%% @hidden
ecs_http(MIME, Body) ->
	Body1 = #{"bytes" => iolist_size(Body),
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
		direction := Direction,
		called :=  Called,
		calling := Calling,
		context := Context,
		session_id := SessionId} = Data) ->
	Stop = erlang:system_time(millisecond),
	Subscriber = #{imsi => IMSI, msisdn => MSISDN},
	Call = #{direction => Direction, calling => Calling, called => Called},
	Network = #{context => Context, session_id => SessionId},
	OCS = #{nrf_location => maps:get(nrf_location, Data, [])},
	cse_log:blog(?FSM_LOGNAME, {Start, Stop, ?SERVICENAME,
			State, Subscriber, Call, Network, OCS}).

%% @hidden
remove_nrf(Data) ->
	Data1 = maps:remove(from, Data),
	Data2 = maps:remove(nrf_start, Data1),
	Data3 = maps:remove(nrf_req_uri, Data2),
	Data4 = maps:remove(nrf_http, Data3),
	maps:remove(nrf_reqid, Data4).

