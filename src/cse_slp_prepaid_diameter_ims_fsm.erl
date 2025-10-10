%%% cse_slp_prepaid_diameter_ims_fsm.erl
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
%%% 	<a href="https://app.swaggerhub.com/apis-docs/SigScale/nrf-rating/1.1.7">
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
%%% 	== Configuration ==
%%% 	Application environment variables used in this SLP include:
%%% 	<dl>
%%% 		<dt>`nrf_profile'</dt>
%%% 			<dd>Provides the {@link //inets/httpc:profile(). profile}
%%% 					name of a manager process for the {@link //inets/httpc. httpc}
%%% 					client. (default: `nrf')</dd>
%%% 		<dt>`nrf_uri'</dt>
%%% 			<dd>Uniform Resource Identifier (URI) for a
%%% 					<a href="https://app.swaggerhub.com/apis-docs/SigScale/nrf-rating/1.1.7">Nrf_Rating</a>
%%% 					server (i.e. OCS).</dd>
%%% 		<dt>`nrf_http_options'</dt>
%%% 			<dd>HTTP request {@link //inets/httpc:http_options(). options}
%%% 					used by the {@link //inets/httpc. httpc} client.
%%% 					(default: `[{timeout, 1500}, {connect_timeout, 1500}]').</dd>
%%% 		<dt>`nrf_headers'</dt>
%%% 			<dd>HTTP {@link //inets/httpc:headers(). headers} added by the
%%% 					{@link //inets/httpc. httpc} client (default: `[]').</dd>
%%% 	</dl>
%%% 	Extra start arguments supported with
%%% 	{@link //cse/cse:add_context/4. cse:add_context/4} include:
%%% 	<dl>
%%% 		<dt>`idle_timeout'</dt>
%%% 			<dd>The idle time after which an SLPI will be shutdown:
%%% 					`{seconds | minutes | hours | days, N :: pos_integer()}'
%%% 					(default: `infinity')</dd>
%%% 	</dl>
%%%
-module(cse_slp_prepaid_diameter_ims_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
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
-define(IDLE_TIMEOUT(Data), {timeout, maps:get(idle, Data), idle}).

-type state() :: null
		| authorize_origination_attempt | terminating_call_handling
		| collect_information | analyse_information
		| o_alerting | t_alerting | active.

-type statedata() :: #{start := pos_integer(),
		idle := erlang:timeout(),
		from => pid(),
		session_id => binary(),
		context => string(),
		sequence => pos_integer(),
		mscc => [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		service_info => [#'3gpp_ro_Service-Information'{}],
		req_type => pos_integer(),
		reqno =>  integer(),
		ohost => binary(),
		orealm => binary(),
		drealm => binary(),
		imsi => [$0..$9],
		imei => [$0..$9],
		msisdn => string(),
		direction => originating | terminating,
		called => [$0..$9],
		calling => [$0..$9],
		nrf_profile => atom(),
		nrf_address => inet:ip_address(),
		nrf_port => non_neg_integer(),
		nrf_uri => string(),
		nrf_resolver => {Module :: atom(), Function :: atom},
		nrf_sort => random | none,
		nrf_retries => non_neg_integer(),
		nrf_next_uris => [string()],
		nrf_host => string(),
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
init(Args) ->
	{ok, Profile} = application:get_env(nrf_profile),
	{ok, URI} = application:get_env(nrf_uri),
	{ok, Resolver} = application:get_env(cse, nrf_resolver),
	{ok, Sort} = application:get_env(cse, nrf_sort),
	{ok, Retries} = application:get_env(cse, nrf_retries),
	{ok, HttpOptions} = application:get_env(nrf_http_options),
	{ok, Headers} = application:get_env(nrf_headers),
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
	Data = #{nrf_profile => Profile,
			nrf_sort => Sort, nrf_retries => Retries,
			nrf_resolver => Resolver,
			nrf_http_options => HttpOptions, nrf_headers => Headers,
			start => erlang:system_time(millisecond),
			idle => IdleTime, sequence => 1},
	Data1 = add_nrf(URI, Data),
	case httpc:get_options([ip, port], Profile) of
		{ok, Options} ->
			init1(Options, Data1);
		{error, Reason} ->
			{stop, Reason}
	end.
%% @hidden
init1([{ip, Address} | T], Data) ->
	init1(T, Data#{nrf_address => Address});
init1([{port, Port} | T], Data) ->
	init1(T, Data#{nrf_port => Port});
init1([], Data) ->
	{ok, null, Data, ?IDLE_TIMEOUT(Data)}.

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
null(enter = _EventType, OldState, #{session_id := SessionId} = Data) ->
	catch log_fsm(OldState, Data),
	cse:delete_session(SessionId),
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
	Actions = [postpone, ?IDLE_TIMEOUT(Data) , ?IDLE_TIMEOUT(Data)],
	{next_state, terminating_call_handling, NewData, Actions};
null(timeout, idle, _Data) ->
	{stop, shutdown}.

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
				'User-Equipment-Info' = UserInfo,
				'Service-Information' = ServiceInformation}, Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST' ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	IMEI = imei(UserInfo),
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From, session_id => SessionId,
			imsi => IMSI, msisdn => MSISDN, imei => IMEI,
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
				NewData1 = add_location(Location, NewData),
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				case {ResultCode, CalledDN} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', Destination}
							when length(Destination) > 0 ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{next_state, analyse_information, NewData1, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', _} ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{next_state, collect_information, NewData1, Actions};
					{_, _} ->
						Actions = [{reply, From, Reply}],
						{next_state, null, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, ?FUNCTION_NAME}]),
					Reply1 = diameter_error(?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{{ok, #{}}, {_, Location}}
				when is_list(Location) ->
			NewData1 = add_location(Location, NewData),
			ResultCode1 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
			Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
			{next_state, collect_information, NewData1, Actions1};
		{{error, Partial, Remaining}, Location} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode1 = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
			Actions1 = [{reply, From, Reply1}],
			{next_state, null, NewData, Actions1};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, missing_location},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{state, ?FUNCTION_NAME}]),
			ResultCode1 = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
			Actions1 = [{reply, From, Reply1}],
			{next_state, null, NewData, Actions1}
	end;
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
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
			{state, ?FUNCTION_NAME}]),
	Reply = diameter_error(?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data) ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	nrf_start(NewData);
authorize_origination_attempt(timeout, idle, Data) ->
	{next_state, null, Data}.

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
				'User-Equipment-Info' = UserInfo,
				'Service-Information' = ServiceInformation}, Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST' ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	IMEI = imei(UserInfo),
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From, session_id => SessionId,
			imsi => IMSI, msisdn => MSISDN, imei => IMEI,
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
				'User-Equipment-Info' = UserInfo,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	IMEI = imei(UserInfo),
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From, session_id => SessionId,
			imsi => IMSI, msisdn => MSISDN, imei => IMEI,
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
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_start ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data) ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_start ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {{Version, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := LogHTTP, nrf_uri := URI,
				ohost := OHost, orealm := ORealm,
				reqno := RequestNum, req_type := RequestType} = Data) ->
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
	case NrfOperation of
		nrf_start ->
			{next_state, null, NewData, Actions};
		nrf_update ->
			{keep_state, NewData, Actions ++ [?IDLE_TIMEOUT(Data)]};
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
				NewData1 = add_location(Location, NewData),
				{ResultCode, NewMSCC} = build_mscc(MSCC, ServiceRating),
				Reply = diameter_answer(NewMSCC,
						ResultCode, RequestType, RequestNum),
				case {ResultCode, is_rsu(MSCC)} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true} ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{next_state, t_alerting, NewData1, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false} ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{keep_state, NewData1, Actions};
					{_, _} ->
						Actions = [{reply, From, Reply}],
						{next_state, null, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{{ok, #{}}, {_, Location}}
				when is_list(Location) ->
			NewData1 = add_location(Location, NewData),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData1, Actions};
		{{error, Partial, Remaining}, {_, Location}}
				when is_list(Location) ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{{ok, _}, false} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, missing_location},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{state, ?FUNCTION_NAME}]),
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
				case {ResultCode, is_rsu(MSCC), is_usu(MSCC)} of
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', _, true} ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{next_state, active, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', true, false} ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{next_state, t_alerting, NewData, Actions};
					{?'DIAMETER_BASE_RESULT-CODE_SUCCESS', false, false} ->
						Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
						{keep_state, NewData, Actions};
					{_, _, _} ->
						Actions = [{reply, From, Reply}],
						{next_state, null, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
					{keep_state, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_answer([], ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
terminating_call_handling(cast,
		{NrfOperation, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data) ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	case NrfOperation of
		nrf_start ->
			nrf_start(NewData);
		nrf_update ->
			nrf_update(NewData);
		nrf_release ->
			nrf_release(NewData)
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(timeout, idle, Data) ->
	{next_state, null, Data}.

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
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
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
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions ++ [?IDLE_TIMEOUT(Data)]};
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
				Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
					{keep_state, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_answer([], ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
collect_information(cast,
		{NrfOperation, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	case NrfOperation of
		nrf_update ->
			nrf_update(NewData);
		nrf_release ->
			nrf_release(NewData)
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
collect_information(timeout, idle, Data) ->
	{next_state, null, Data}.

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
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
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
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions ++ [?IDLE_TIMEOUT(Data)]};
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
				Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
					{keep_state, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
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
					{state, ?FUNCTION_NAME}]),
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast,
		{NrfOperation, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	case NrfOperation of
		nrf_update ->
			nrf_update(NewData);
		nrf_release ->
			nrf_release(NewData)
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
analyse_information(timeout, idle, Data) ->
	{next_state, null, Data}.

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
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast,
		{NrfOperation, {RequestId, {{Version, 404, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 404, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast,
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions ++ [?IDLE_TIMEOUT(Data)]};
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
				Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
					{keep_state, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_answer([], ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast,
		{NrfOperation, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	case NrfOperation of
		nrf_update ->
			nrf_update(NewData);
		nrf_release ->
			nrf_release(NewData)
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
o_alerting(timeout, idle, Data) ->
	{next_state, null, Data}.

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
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast,
		{NrfOperation, {RequestId, {{Version, 400, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_http := LogHTTP,
				reqno := RequestNum, req_type := RequestType} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	log_nrf(ecs_http(Version, 400, Headers, Body, LogHTTP), Data),
	NewData = remove_nrf(Data),
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast,
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions ++ [?IDLE_TIMEOUT(Data)]};
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
				Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
					{keep_state, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_answer([], ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast,
		{NrfOperation, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	case NrfOperation of
		nrf_update ->
			nrf_update(NewData);
		nrf_release ->
			nrf_release(NewData)
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
t_alerting(timeout, idle, Data) ->
	{next_state, null, Data}.

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
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
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
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
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
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			[{reply, From, Reply}]
	end,
	case NrfOperation of
		nrf_update ->
			{keep_state, NewData, Actions ++ [?IDLE_TIMEOUT(Data)]};
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
				Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
				{keep_state, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {location, Location}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}, ?IDLE_TIMEOUT(Data)],
					{keep_state, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
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
							{state, ?FUNCTION_NAME}]),
					ResultCode1 = ?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
					Reply1 = diameter_error(ResultCode1, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{ok, #{}} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			Reply = diameter_answer([], ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm},
					{partial, Partial}, {remaining, Remaining},
					{state, ?FUNCTION_NAME}]),
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {error, {failed_connect, _}}}},
		#{nrf_reqid := RequestId, nrf_next_uris := [URI | T]} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = Data1#{nrf_uri => URI, nrf_next_uris => T},
	case NrfOperation of
		nrf_update ->
			nrf_update(NewData);
		nrf_release ->
			nrf_release(NewData)
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
			{state, ?FUNCTION_NAME}]),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
	Reply = diameter_error(ResultCode, RequestType, RequestNum),
	case NrfOperation of
		nrf_update ->
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		nrf_release ->
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
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
handle_event(_EventType, _EventContent, _State, Data) ->
	{keep_state_and_data, ?IDLE_TIMEOUT(Data)}.

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
		Result :: {keep_state, Data, Actions} | {next_state, null, Data, Actions},
		Actions :: [Action] | Action,
		Action :: {reply, From, #'3gpp_ro_CCA'{}} | {timeout, Time, idle},
		From :: {pid(), reference()},
		Time :: erlang:timeout().
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
nrf_start1(JSON, #{sequence := Sequence} = Data) ->
	Now = erlang:system_time(millisecond),
	JSON1 = JSON#{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	nrf_start2(Now, JSON1, Data).
%% @hidden
nrf_start2(Now, JSON,
		#{from := From, nrf_profile := Profile,
				nrf_uri := URI, nrf_next_uris := NextURIs, nrf_host := Host,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"host", Host},
			{"accept", "application/json, application/problem+json"}
			| Headers],
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
			{keep_state, NewData, ?IDLE_TIMEOUT(Data)};
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewData = Data#{nrf_uri => hd(NextURIs),
					nrf_next_uris => tl(NextURIs)},
			nrf_start2(Now, JSON, NewData);
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
		Result :: {keep_state, Data, Actions},
		Actions :: [Action] | Action,
		Action :: {reply, From, #'3gpp_ro_CCA'{}} | {timeout, Time, idle},
		From :: {pid(), reference()},
		Time :: erlang:timeout().
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
		#{from := From, nrf_profile := Profile,
				nrf_uri := URI, nrf_next_uris := NextURIs, nrf_host := Host,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"host", Host},
			{"accept", "application/json, application/problem+json"}
			| Headers],
	Body = zj:encode(JSON),
	ContentType = "application/json",
	RequestURL = uri_string:resolve(Location, URI) ++ "/update",
	LogHTTP = ecs_http(ContentType, Body),
	Request = {RequestURL, Headers1, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_start => Now, nrf_reqid => RequestId,
					nrf_req_url => RequestURL, nrf_http => LogHTTP},
			{keep_state, NewData, ?IDLE_TIMEOUT(Data)};
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewData = Data#{nrf_uri => hd(NextURIs),
					nrf_next_uris => tl(NextURIs)},
			nrf_update2(Now, JSON, NewData);
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()},
					{origin_host, OHost}, {origin_realm, ORealm}]),
			NewData = maps:remove(nrf_location, Data),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(ResultCode, RequestType, RequestNum),
			Actions = [{reply, From, Reply}, ?IDLE_TIMEOUT(Data)],
			{keep_state, NewData, Actions}
	end.

-spec nrf_release(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data, Actions} | {next_state, null, Data, Actions},
		Actions :: [Action] | Action,
		Action :: {reply, From, #'3gpp_ro_CCA'{}} | {timeout, Time, idle},
		From :: {pid(), reference()},
		Time :: erlang:timeout().
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
		#{from := From, nrf_profile := Profile,
				nrf_uri := URI, nrf_next_uris := NextURIs, nrf_host := Host,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location, 
				ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers1 = [{"host", Host},
			{"accept", "application/json, application/problem+json"}
			| Headers],
	Body = zj:encode(JSON),
	ContentType = "application/json",
	RequestURL = uri_string:resolve(Location, URI) ++ "/release",
	LogHTTP = ecs_http(ContentType, Body),
	Request = {RequestURL, Headers1, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_start => Now, nrf_reqid => RequestId,
					nrf_req_url => RequestURL, nrf_http => LogHTTP},
			{keep_state, NewData, ?IDLE_TIMEOUT(Data)};
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewData = Data#{nrf_uri => hd(NextURIs),
					nrf_next_uris => tl(NextURIs)},
			nrf_release2(Now, JSON, NewData);
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

%% @hidden
fui({ok, #{"finalUnitAction" := "TERMINATE"} = FUI}) ->
	fui1(FUI, #'3gpp_ro_Final-Unit-Indication'{
			'Final-Unit-Action' = ?'3GPP_FINAL-UNIT-ACTION_TERMINATE'});
fui({ok, #{"finalUnitAction" := "REDIRECT"} = FUI}) ->
	fui1(FUI, #'3gpp_ro_Final-Unit-Indication'{
			'Final-Unit-Action' = ?'3GPP_FINAL-UNIT-ACTION_REDIRECT'});
fui({ok, #{"finalUnitAction" := "RESTRICT_ACCESS"} = FUI}) ->
	fui1(FUI, #'3gpp_ro_Final-Unit-Indication'{
			'Final-Unit-Action' = ?'3GPP_FINAL-UNIT-ACTION_RESTRICT_ACCESS'});
fui(_) ->
	[].
%% @hidden
fui1(#{"restrictionFilterRules" := IPFilterRules} = FUI, Acc)
		when is_list(IPFilterRules) ->
	case lists:all(fun is_list/1, IPFilterRules) of
		true ->
			fui2(FUI, Acc#'3gpp_ro_Final-Unit-Indication'{
					'Restriction-Filter-Rule' = IPFilterRules});
		false ->
			fui2(FUI, Acc)
	end;
fui1(FUI, Acc) ->
	fui2(FUI, Acc).
%% @hidden
fui2(#{"filterIds" := FilterIds} = FUI, Acc)
		when is_list(FilterIds) ->
	case lists:all(fun is_list/1, FilterIds) of
		true ->
			fui3(FUI, Acc#'3gpp_ro_Final-Unit-Indication'{
					'Filter-Id' = FilterIds});
		false ->
			fui3(FUI, Acc)
	end;
fui2(FUI, Acc) ->
	fui3(FUI, Acc).
%% @hidden
fui3(#{"redirectServer" := #{"redirectAddressType" := "IPV4",
			"redirectServerAddress" := Address}}, Acc)
		when is_list(Address) ->
	RS = #'3gpp_ro_Redirect-Server'{
			'Redirect-Address-Type' = '?3GPP_RO_REDIRECT-ADDRESS-TYPE_IPV4_ADDRESS',
			'Redirect-Server-Address' = Address},
	[Acc#'3gpp_ro_Final-Unit-Indication'{'Redirect-Server' = RS}];
fui3(#{"redirectServer" := #{"redirectAddressType" := "IPV6",
			"redirectServerAddress" := Address}}, Acc)
		when is_list(Address) ->
	RS = #'3gpp_ro_Redirect-Server'{
			'Redirect-Address-Type' = '?3GPP_RO_REDIRECT-ADDRESS-TYPE_IPV6_ADDRESS',
			'Redirect-Server-Address' = Address},
	[Acc#'3gpp_ro_Final-Unit-Indication'{'Redirect-Server' = RS}];
fui3(#{"redirectServer" := #{"redirectAddressType" := "URL",
			"redirectServerAddress" := Address}}, Acc)
		when is_list(Address) ->
	RS = #'3gpp_ro_Redirect-Server'{
			'Redirect-Address-Type' = '?3GPP_RO_REDIRECT-ADDRESS-TYPE_URL',
			'Redirect-Server-Address' = Address},
	[Acc#'3gpp_ro_Final-Unit-Indication'{'Redirect-Server' = RS}];
fui3(#{"redirectServer" := #{"redirectAddressType" := "URI",
			"redirectServerAddress" := Address}}, Acc)
		when is_list(Address) ->
	RS = #'3gpp_ro_Redirect-Server'{
			'Redirect-Address-Type' = '?3GPP_RO_REDIRECT-ADDRESS-TYPE_SIP_URI',
			'Redirect-Server-Address' = Address},
	[Acc#'3gpp_ro_Final-Unit-Indication'{'Redirect-Server' = RS}];
fui3(_FUI, Acc) ->
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
	SR4 = service_rating_ps(ServiceInformation, SR3),
	SR5 = service_rating_ims(ServiceInformation, SR4),
	SR6 = service_rating_vcs(ServiceInformation, SR5),
	SR7 = service_rating_imei(Data, SR6),
	Acc1 = service_rating_rsu(MSCC, SR7, Acc),
	Acc2 = service_rating_usu(MSCC, SR7, Acc1),
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
service_rating_ims([#'3gpp_ro_Service-Information'{
		'IMS-Information' = IMS}],
		#{"serviceInformation" := Info} = ServiceRating) ->
	service_rating_ims1(IMS, ServiceRating, Info);
service_rating_ims([#'3gpp_ro_Service-Information'{
		'IMS-Information' = IMS}], ServiceRating) ->
	service_rating_ims1(IMS, ServiceRating, #{});
service_rating_ims(_ServiceInformation, ServiceRating) ->
	ServiceRating.
%% @hidden
service_rating_ims1([#'3gpp_ro_IMS-Information'{
		'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS'}] = IMS,
		ServiceRating, Info) ->
	Info1 = Info#{"nodeFunctionality" => "AS"},
	service_rating_ims2(IMS, ServiceRating, Info1);
service_rating_ims1(IMS, ServiceRating, Info) ->
	service_rating_ims2(IMS, ServiceRating, Info).
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
service_rating_imei(#{imei := IMEI}, ServiceRating)
		when is_list(IMEI) ->
	Pei = "imei-" ++ IMEI,
	ServiceRating#{"userInformation" => #{"servedPei" => Pei}};
service_rating_imei(_, ServiceRating) ->
	ServiceRating.

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

%% @hidden
imei([#'3gpp_ro_User-Equipment-Info'{
		'User-Equipment-Info-Type' = ?'3GPP_RO_USER-EQUIPMENT-INFO-TYPE_IMEISV',
		'User-Equipment-Info-Value' = IMEISV}])
		when is_binary(IMEISV), size(IMEISV) >= 15 ->
	lists:sublist(binary_to_list(IMEISV), 16);
imei(_) ->
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
	FUI = fui(maps:find("finalUnitIndication", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Final-Unit-Indication' = FUI,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([SI], [], [#{"serviceId" := SI,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	FUI = fui(maps:find("finalUnitIndication", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Final-Unit-Indication' = FUI,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([], [RG], [#{"ratingGroup" := RG,
		"resultCode" := ResultCode} = ServiceRating | _], {FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	FUI = fui(maps:find("finalUnitIndication", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Rating-Group' = [RG],
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Final-Unit-Indication' = FUI,
			'Result-Code' = [RC]},
	{final_result(RC, FinalRC), [MSCC | Acc]};
build_mscc1([], [], [#{"resultCode" := ResultCode} = ServiceRating | _],
		{FinalRC, Acc}) ->
	GSU = gsu(maps:find("grantedUnit", ServiceRating)),
	{QT, QV, QU} = quota_threshold(ServiceRating),
	Validity = vality_time(ServiceRating),
	FUI = fui(maps:find("finalUnitIndication", ServiceRating)),
	RC = result_code(ResultCode),
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = GSU,
			'Time-Quota-Threshold' = QT,
			'Volume-Quota-Threshold' = QV,
			'Unit-Quota-Threshold' = QU,
			'Validity-Time' = Validity,
			'Final-Unit-Indication' = FUI,
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
%% @doc Construct ECS JSON `map()' for Nrf response.
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

-spec log_fsm(State, Data) -> ok
	when
		State :: atom(),
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
	Data3 = maps:remove(nrf_req_url, Data2),
	Data4 = maps:remove(nrf_http, Data3),
	maps:remove(nrf_reqid, Data4).

%% @hidden
add_nrf(URI, Data) ->
	add_nrf(URI, Data, uri_string:parse(URI)).
%% @hidden
add_nrf(URI, Data, #{host := Address, port := Port} = _URIMap)
		when is_list(Address) ->
	Host = Address ++ ":" ++ integer_to_list(Port),
	Data1 = Data#{nrf_host => Host},
	add_nrf1(URI, Data1);
add_nrf(URI, Data, #{host := Address, port := Port} = _URIMap)
		when is_binary(Address) ->
	Host = binary_to_list(Address) ++ ":" ++ integer_to_list(Port),
	Data1 = Data#{nrf_host => Host},
	add_nrf1(URI, Data1);
add_nrf(URI, Data, #{host := Address} = _URIMap)
		when is_list(Address) ->
	Data1 = Data#{nrf_host => Address},
	add_nrf1(URI, Data1);
add_nrf(URI, Data, #{host := Address} = _URIMap)
		when is_binary(Address) ->
	Data1 = Data#{nrf_host => binary_to_list(Address)},
	add_nrf1(URI, Data1).
%% @hidden
add_nrf1(URI, #{nrf_resolver := {M, F},
		nrf_sort := Sort, nrf_retries := Retries} = Data) ->
	add_nrf2(M:F(URI, [{sort, Sort}, {max_uri, Retries + 1}]), Data).
%% @hidden
add_nrf2(HostURI,
		#{nrf_retries := 0} = Data) ->
	Data#{nrf_uri => HostURI, nrf_next_uris => []};
add_nrf2([H | T], Data) ->
	Data#{nrf_uri => H, nrf_next_uris => T}.

%% @hidden
add_location(URI, Data) ->
	add_location(URI, Data, uri_string:parse(URI)).
%% @hidden
add_location(URI, Data, #{host := Address, port := Port} = URIMap)
		when is_list(Address) ->
	Host = Address ++ ":" ++ integer_to_list(Port),
	Filter = #{path => [], query => [], fragment => []},
	URIMap1 = maps:intersect(Filter, URIMap),
	Location = uri_string:recompose(URIMap1),
	Data1 = Data#{nrf_host => Host, nrf_location => Location},
	add_location1(URI, Data1);
add_location(URI, Data, #{host := Address, port := Port} = URIMap)
		when is_binary(Address) ->
	Host = binary_to_list(Address) ++ ":" ++ integer_to_list(Port),
	Filter = #{path => [], query => [], fragment => []},
	URIMap1 = maps:intersect(Filter, URIMap),
	Location = uri_string:recompose(URIMap1),
	Data1 = Data#{nrf_host => Host, nrf_location => Location},
	add_location1(URI, Data1);
add_location(URI, Data, #{host := Address} = URIMap)
		when is_list(Address) ->
	Filter = #{path => [], query => [], fragment => []},
	URIMap1 = maps:intersect(Filter, URIMap),
	Location = uri_string:recompose(URIMap1),
	Data1 = Data#{nrf_host => Address, nrf_location => Location},
	add_location1(URI, Data1);
add_location(URI, Data, #{host := Address} = URIMap)
		when is_binary(Address) ->
	Host = binary_to_list(Address),
	Filter = #{path => [], query => [], fragment => []},
	URIMap1 = maps:intersect(Filter, URIMap),
	Location = uri_string:recompose(URIMap1),
	Data1 = Data#{nrf_host => Host, nrf_location => Location},
	add_location1(URI, Data1);
add_location(_URI, Data, #{} = URIMap) ->
	Filter = #{path => [], query => [], fragment => []},
	URIMap1 = maps:intersect(Filter, URIMap),
	Location = uri_string:recompose(URIMap1),
	Data#{nrf_location => Location}.
%% @hidden
add_location1(URI, #{nrf_resolver := {M, F},
		nrf_sort := Sort, nrf_retries := Retries} = Data) ->
	add_location2(M:F(URI, [{sort, Sort}, {max_uri, Retries + 1}]), Data).
%% @hidden
add_location2(HostURI,
		#{nrf_retries := 0} = Data) ->
	Data#{nrf_uri => HostURI, nrf_next_uris => []};
add_location2([H | T], Data) ->
	Data#{nrf_uri => H, nrf_next_uris => T}.

