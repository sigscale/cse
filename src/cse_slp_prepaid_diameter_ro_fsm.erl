%%% cse_slp_prepaid_diameter_ro_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
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
%%% 	<img alt="state machine" src="prepaid-diameter-ro.svg" />
%%%
-module(cse_slp_prepaid_diameter_ro_fsm).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Refath Wadood <refath@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, authorize_origination_attempt/3,
		terminating_call_handling/3,
		collect_information/3, analyse_information/3,
		routing/3, o_alerting/3, t_alerting/3, active/3]).
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
-define(LOGNAME, prepaid).
-define(SERVICENAME, "Prepaid Voice").

-type state() :: null
		| authorize_origination_attempt | terminating_call_handling
		| collect_information | analyse_information
		| routing | o_alerting | t_alerting | active.

-type statedata() :: #{start := pos_integer(),
		nrf_profile => atom(),
		nrf_uri => string(),
		nrf_location => string(),
		nrf_reqid => reference(),
		imsi => [$0..$9],
		direction => originating | terminating,
		called =>  [$0..$9],
		calling => [$0..$9],
		msisdn => string(),
		context => string(),
		mscc => [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		req_type => pos_integer(),
		reqno =>  integer(),
		session_id => binary(),
		ohost => binary(),
		orealm => binary(),
		drealm => binary(),
		from => pid()}.

-type mscc() :: #{rg => pos_integer(),
		si => pos_integer(),
		usu => #{unit() => pos_integer()},
		rsu => #{unit() => pos_integer()} | []}.

-type unit() :: time | downlinkVolume | uplinkVolume
		| totalVolume | serviceSpecificUnit.

-type service_rating() :: #{serviceContextId => string(),
		serviceId => pos_integer(),
		ratingGroup => pos_integer(),
		requestSubType => string(),
		consumedUnit => #{unit() => pos_integer()},
		grantedUnit => #{unit() => pos_integer()}}.

%%----------------------------------------------------------------------
%%  The cse_slp_prepaid_diameter_ro_fsm gen_statem callbacks
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
	Data = #{nrf_profile => Profile, nrf_uri => URI,
			start => erlang:system_time(millisecond)},
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
	log(OldState,Data),
	{stop, shutdown};
null({call, _From}, #'3gpp_ro_CCR'{
		'Service-Information' = [#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE']}]}]},
		Data) ->
	NewData = Data#{direction => origininating},
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
%%
%% 	We handle `CCR-U' in this state because we may have entered
%% 	from another SLP which consumed the `CCR-I'.
%%.
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
	NewData = Data#{from => From,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, drealm => DRealm, reqno => RequestNum,
			req_type => RequestType},
	nrf_start(NewData);
authorize_origination_attempt({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, drealm => DRealm, reqno => RequestNum,
			req_type => RequestType},
	nrf_update(NewData);
authorize_origination_attempt({call, From},
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
authorize_origination_attempt({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum},
		#{session_id := SessionId, ohost := OHost, orealm := ORealm} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST' ->
	NewData = Data#{from => From,
			reqno => RequestNum, req_type => RequestType},
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, called := Called,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := ServiceRating}}, {_, Location}}
				when is_list(Location) ->
			try
				NewData1 = NewData#{nrf_location => Location},
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {rsu_positive(MSCC), Called} of
					{true, Destination} when is_list(Destination) ->
						{next_state, analyse_information, NewData1, Actions};
					{true, undefined} ->
						{next_state, collect_information, NewData1, Actions};
					{false, _} ->
						{keep_state, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{state, authorize_origination_attempt}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			Reply2 = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions2 = [{reply, From, Reply2}],
			{next_state, null, NewData, Actions2}
	end;
authorize_origination_attempt(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, mscc := MSCC, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, session_id := SessionId,
				req_type := RequestType, called := Called} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {rsu_positive(MSCC), Called} of
					{true, Destination} when is_list(Destination) ->
						{next_state, analyse_information, NewData, Actions};
					{true, undefined} ->
						{next_state, collect_information, NewData, Actions};
					{false, _} ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{state, authorize_origination_attempt}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
authorize_origination_attempt(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, mscc := MSCC, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, session_id := SessionId,
				req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{state, authorize_origination_attempt}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
authorize_origination_attempt(cast,
		{nrf_start, {_RequestId, {{_Version, 404, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	NewData = maps:remove(nrf_reqid, Data),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_update, {_RequestId, {{_Version, 404, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	NewData = maps:remove(nrf_reqid, Data),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {_RequestId, {{_Version, 403, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = maps:remove(from, Data1),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_update, {_RequestId, {{_Version, 403, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = maps:remove(from, Data1),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
authorize_origination_attempt(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_start; NrfOperation == nrf_update;
		NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{state, authorize_origination_attempt}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_start ->
			{next_state, null, NewData, Actions};
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
authorize_origination_attempt(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_start; NrfOperation == nrf_update;
				NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
			{state, authorize_origination_attempt}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_start ->
			{next_state, null, NewData, Actions};
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end.

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
	NewData = Data#{from => From,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, drealm => DRealm, reqno => RequestNum,
			req_type => RequestType},
	nrf_start(NewData);
terminating_call_handling({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum,
				'Multiple-Services-Credit-Control' = MSCC,
				'Service-Information' = ServiceInformation},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	IMSI = imsi(SubscriptionId),
	MSISDN = msisdn(SubscriptionId),
	{CallingDN, CalledDN} = call_parties(ServiceInformation),
	NewData = Data#{from => From,
			imsi => IMSI, msisdn => MSISDN,
			calling => CallingDN, called => CalledDN,
			context => binary_to_list(SvcContextId),
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, drealm => DRealm, reqno => RequestNum,
			req_type => RequestType},
	nrf_update(NewData);
terminating_call_handling({call, From},
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
terminating_call_handling({call, From},
		#'3gpp_ro_CCR'{'Session-Id' = SessionId,
				'CC-Request-Type' = RequestType,
				'CC-Request-Number' = RequestNum},
		#{session_id := SessionId, ohost := OHost, orealm := ORealm} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST' ->
	NewData = Data#{from => From,
			reqno => RequestNum, req_type => RequestType},
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
terminating_call_handling(cast,
		{nrf_start, {_RequestId, {{_Version, 404, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	NewData = maps:remove(nrf_reqid, Data),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
terminating_call_handling(cast,
		{nrf_update, {_RequestId, {{_Version, 404, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	NewData = maps:remove(nrf_reqid, Data),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
terminating_call_handling(cast,
		{nrf_start, {_RequestId, {{_Version, 403, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = maps:remove(from, Data1),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
terminating_call_handling(cast,
		{nrf_update, {_RequestId, {{_Version, 403, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	ResultCode = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Data1 = maps:remove(nrf_reqid, Data),
	NewData = maps:remove(from, Data1),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
terminating_call_handling(cast,
		{nrf_start, {RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, mscc := MSCC, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, session_id := SessionId,
				req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := ServiceRating}}, {_, Location}}
				when is_list(Location) ->
			try
				NewData1 = NewData#{nrf_location => Location},
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case rsu_positive(MSCC) of
					false ->
						{keep_state, NewData1, Actions};
					true ->
						{next_state, t_alerting, NewData1, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{state, terminating_call_handling}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, terminating_call_handling}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, mscc := MSCC, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, session_id := SessionId,
				req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {rsu_positive(MSCC), usu_positive(MSCC)} of
					{false, false} ->
						{keep_state, NewData, Actions};
					{true, false} ->
						{next_state, t_alerting, NewData, Actions};
					{_, true} ->
						{next_state, active, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{state, terminating_call_handling}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, terminating_call_handling}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
terminating_call_handling(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, mscc := MSCC, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, session_id := SessionId,
				req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
							{state, terminating_call_handling}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, terminating_call_handling}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_start; NrfOperation == nrf_update;
				NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{state, terminating_call_handling}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_start ->
			{next_state, null, NewData, Actions};
		nrf_update ->
			{keep_state, NewData, Actions};
		nrf_release ->
			{next_state, null, NewData, Actions}
	end;
terminating_call_handling(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_start; NrfOperation == nrf_update;
				NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
			{state, terminating_call_handling}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	case NrfOperation of
		nrf_start ->
			{next_state, NewData, Actions};
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
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
collect_information({call, From},
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
collect_information(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				called := Called, nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case {rsu_positive(MSCC), Called} of
					{true, Destination} when is_list(Destination) ->
						{next_state, analyse_information, NewData, Actions};
					_ ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
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
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, collect_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
collect_information(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
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
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, collect_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
collect_information(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
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
collect_information(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
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
	case usu_positive(MSCC) of
		true ->
			{next_state, active, NewData, postpone};
		false ->
			{next_state, routing, NewData, postpone}
	end;
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
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()},
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
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, analyse_information}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
analyse_information(cast, {nrf_release,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, nrf_release},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{state, analyse_information}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
analyse_information(cast, {nrf_release, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data) ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()},
			{state, analyse_information}]),
	Reply = diameter_error(SessionId,
			?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			OHost, ORealm, RequestType, RequestNum),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions}.

-spec routing(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>routing</em> state.
%% @private
routing(enter, _EventContent, _Data) ->
	keep_state_and_data;
routing({call, From},
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
routing({call, From},
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
routing(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case usu_positive(MSCC) of
					true ->
						{next_state, active, NewData, Actions};
					false ->
						{next_state, o_alerting, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, routing}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, routing}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
routing(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, routing}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, routing}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
routing(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{state, routing}]),
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
routing(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()}, {state, routing}]),
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
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
o_alerting({call, From},
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
o_alerting(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case usu_positive(MSCC) of
					true ->
						{next_state, active, NewData, Actions};
					false ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, o_alerting}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, o_alerting}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
o_alerting(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, o_alerting}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, o_alerting}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
o_alerting(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{state, o_alerting}]),
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
o_alerting(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()}, {state, o_alerting}]),
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
				'Multiple-Services-Credit-Control' = MSCC},
		#{session_id := SessionId, nrf_location := Location} = Data)
		when RequestType == ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
				is_list(Location) ->
	NewData = Data#{from => From, mscc => MSCC,
			reqno => RequestNum, req_type => RequestType},
	nrf_update(NewData);
t_alerting({call, From},
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
t_alerting(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				case usu_positive(MSCC) of
					true ->
						{next_state, active, NewData, Actions};
					false ->
						{keep_state, NewData, Actions}
				end
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, t_alerting}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, t_alerting}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
t_alerting(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, t_alerting}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, t_alerting}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
t_alerting(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
			{state, t_alerting}]),
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
t_alerting(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()}, {state, t_alerting}]),
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
		{nrf_update, {_RequestId, {{_Version, 403, _Phrase}, _Headers, _Body}}},
		#{from := From, ohost := OHost, orealm := ORealm,
				reqno := RequestNum, session_id := SessionId,
				req_type := RequestType} = Data) ->
	ResultCode = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED',
	Reply = diameter_error(SessionId, ResultCode,
			OHost, ORealm, RequestType, RequestNum),
	Data = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data),
	Actions = [{reply, From, Reply}],
	{keep_state, NewData, Actions};
active(cast,
		{nrf_update, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{keep_state, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, active}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{keep_state, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end;
active(cast,
		{nrf_release, {RequestId, {{_Version, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId, req_type := RequestType} = Data) ->
	Data1 = maps:remove(from, Data),
	NewData = maps:remove(nrf_reqid, Data1),
	case zj:decode(Body) of
		{ok, #{"serviceRating" := ServiceRating}} ->
			try
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
							{request_id, RequestId}, {profile, Profile},
							{uri, URI}, {slpi, self()}, {state, active}]),
					Reply1 = diameter_error(SessionId,
							?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED',
							OHost, ORealm, RequestType, RequestNum),
					Actions1 = [{reply, From, Reply1}],
					{next_state, null, NewData, Actions1}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {slpi, self()},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
active(cast, {NrfOperation,
		{RequestId, {{_Version, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase}, {request_id, RequestId},
			{profile, Profile}, {uri, URI}, {slpi, self()},
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
active(cast, {NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, session_id := SessionId, ohost := OHost,
				orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when NrfOperation == nrf_update; NrfOperation == nrf_release ->
	NewData = maps:remove(nrf_reqid, Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()}, {state, active}]),
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
nrf_start(#{mscc := MSCC, context := ServiceContextId} = Data) ->
	ServiceRating = service_rating(mscc(MSCC), ServiceContextId),
	nrf_start1(ServiceRating, ServiceContextId, Data).
%% @hidden
nrf_start1(ServiceRating, ?IMS_CONTEXTID, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"serviceRating" => ServiceRating},
	nrf_start2(JSON, Data).
%% @hidden
nrf_start2(JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				session_id := SessionId, ohost := OHost, orealm := ORealm,
				req_type := RequestType, reqno := RequestNum} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
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
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, Data, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
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
	ServiceRating = service_rating(mscc(MSCC), ServiceContextId),
	nrf_update1(ServiceRating, ServiceContextId, Data).
%% @hidden
nrf_update1(ServiceRating, ?IMS_CONTEXTID, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"serviceRating" => ServiceRating},
	nrf_update2(JSON, Data).
%% @hidden
nrf_update2(JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_location := Location, session_id := SessionId,
				ohost := OHost, orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/update", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_reqid => RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()}]),
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
	ServiceRating = service_rating(mscc(MSCC), ServiceContextId),
	nrf_release1(ServiceRating, ServiceContextId, Data).
%% @hidden
nrf_release1(ServiceRating, ?IMS_CONTEXTID, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data),
			"serviceRating" => ServiceRating},
	nrf_release2(JSON, Data).
%% @hidden
nrf_release2(JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_location := Location, session_id := SessionId,
				ohost := OHost, orealm := ORealm, req_type := RequestType,
				reqno := RequestNum} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ Location ++ "/release", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_reqid => RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_release}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()}]),
			NewData = maps:remove(nrf_location, Data),
			Reply = diameter_error(SessionId,
					?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RequestType, RequestNum),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end.

-spec mscc(MSCC) -> Result
	when
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		Result :: [mscc()].
%% @doc Convert a list of Diameter MSCCs to a list of equivalent maps.
mscc(MSCC) ->
	mscc(MSCC, []).
%% @hidden
mscc([H | T], Acc) ->
	Amounts = #{rg => rg(H), si => si(H), rsu => rsu(H), usu => usu(H)},
	mscc(T, [Amounts | Acc]);
mscc([], Acc) ->
	lists:reverse(Acc).

%% @hidden
si(#'3gpp_ro_Multiple-Services-Credit-Control'{'Service-Identifier' = [SI]})
		when is_integer(SI) ->
	SI;
si(_) ->
	undefined.

%% @hidden
rg(#'3gpp_ro_Multiple-Services-Credit-Control'{'Rating-Group' = [RG]})
		when is_integer(RG) ->
	RG;
rg(_) ->
	undefined.

%% @hidden
rsu_positive([H | T]) ->
	case rsu(H) of
		#{} ->
			true;
		[] ->
			true;
		undefined ->
			rsu_positive(T)
	end;
rsu_positive([]) ->
	false.

%% @hidden
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Time' = [CCTime]}]})
		when is_integer(CCTime), CCTime > 0 ->
	#{time => CCTime};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Total-Octets' = [CCTotalOctets]}]})
		when is_integer(CCTotalOctets), CCTotalOctets > 0 ->
	#{totalVolume => CCTotalOctets};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets],
		'CC-Input-Octets' = [CCInputOctets]}]})
		when is_integer(CCInputOctets), is_integer(CCOutputOctets),
				CCInputOctets > 0, CCOutputOctets > 0 ->
	#{totalVolume => CCInputOctets + CCOutputOctets,
			downlinkVolume => CCOutputOctets, uplinkVolume => CCInputOctets};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]}]})
		when is_integer(CCSpecUnits), CCSpecUnits > 0 ->
	#{serviceSpecificUnit => CCSpecUnits};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{}]}) ->
	[];
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{}) ->
	undefined.

%% @hidden
usu_positive([H | T]) ->
	case usu(H) of
		#{} ->
			true;
		undefined ->
			usu_positive(T)
	end;
usu_positive([]) ->
	false.

usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Time' = [CCTime]} | _]})
		when is_integer(CCTime), CCTime > 0 ->
	#{time => CCTime};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Total-Octets' = [CCTotalOctets]} | _]})
		when is_integer(CCTotalOctets), CCTotalOctets > 0 ->
	#{totalVolume => CCTotalOctets};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets],
		'CC-Input-Octets' = [CCInputOctets]} | _]})
		when is_integer(CCInputOctets), is_integer(CCOutputOctets),
				CCInputOctets > 0, CCOutputOctets > 0 ->
	#{totalVolume => CCInputOctets + CCOutputOctets,
			downlinkVolume => CCOutputOctets, uplinkVolume => CCInputOctets};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]} | _]})
		when is_integer(CCSpecUnits), CCSpecUnits > 0 ->
	#{serviceSpecificUnit => CCSpecUnits};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{'Used-Service-Unit' = []}) ->
	undefined;
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{}) ->
	undefined.

%% @hidden
gsu(#{"time" := CCTime})
		when CCTime > 0 ->
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [CCTime]};
gsu(#{"totalVolume" := CCTotalOctets})
		when CCTotalOctets > 0 ->
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [CCTotalOctets]};
gsu(#{"serviceSpecificUnit" := CCSpecUnits})
		when CCSpecUnits > 0 ->
	#'3gpp_ro_Granted-Service-Unit'{'CC-Service-Specific-Units' = [CCSpecUnits]};
gsu(_) ->
	[].

-spec service_rating(MSCC, ServiceContextId) -> ServiceRating
	when
		MSCC :: [mscc()],
		ServiceContextId :: string(),
		ServiceRating :: [service_rating()].
%% @doc Build a `serviceRating' object.
%% @hidden
service_rating(MSCC, ServiceContextId) ->
	service_rating(MSCC, ServiceContextId, []).
%% @hidden
service_rating([#{} = H| T], ServiceContextId, Acc) ->
	service_rating(T, ServiceContextId,
			Acc ++ service_rating1(H, ServiceContextId));
service_rating([], _ServiceContextId, Acc) ->
	lists:reverse(Acc).
%% @hidden
service_rating1(#{rg := RG} = MSCC, ServiceContextId)
		when is_integer(RG) ->
	Acc = #{serviceContextId => ServiceContextId, ratingGroup => RG},
	service_rating2(MSCC, Acc);
service_rating1(MSCC, ServiceContextId) ->
	Acc = #{serviceContextId => ServiceContextId},
	service_rating2(MSCC, Acc).
%% @hidden
service_rating2(#{si := SI} = MSCC, Acc)
		when is_integer(SI) ->
	Acc1 = Acc#{serviceId => SI},
	service_rating3(MSCC, Acc1);
service_rating2(MSCC, Acc) ->
	service_rating3(MSCC, Acc).
%% @hidden
%% Initial
service_rating3(#{rsu := [], usu := undefined}, Acc) ->
	RatingObject = Acc#{requestSubType => "RESERVE"},
	[RatingObject];
service_rating3(#{rsu := #{} = RSU, usu := undefined}, Acc) ->
	RatingObject = Acc#{requestSubType => "RESERVE", grantedUnit => RSU},
	[RatingObject];
%% Interim
service_rating3(#{rsu := [], usu := #{} = USU}, Acc) ->
	RatingObject1 = Acc#{requestSubType => "RESERVE"},
	RatingObject2 = Acc#{requestSubType => "DEBIT", consumedUnit => USU},
	[RatingObject1, RatingObject2];
service_rating3(#{rsu := #{} = RSU , usu := #{} = USU}, Acc) ->
	RatingObject1 = Acc#{requestSubType => "RESERVE", grantedUnit => RSU},
	RatingObject2 = Acc#{requestSubType => "DEBIT", consumedUnit => USU},
	[RatingObject1, RatingObject2];
%% Final
service_rating3(#{rsu := undefined, usu := #{} = USU}, Acc) ->
	RatingObject = Acc#{requestSubType => "DEBIT", consumedUnit => USU},
	[RatingObject];
%% No RSU & No GSU
service_rating3(#{rsu := undefined, usu := undefined}, Acc) ->
	[Acc].

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

-spec build_container(MSCC) -> MSCC
	when
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}].
%% @doc Build a container for CCR MSCC.
build_container(MSCC) ->
	build_container(MSCC, []).
%% @hidden
build_container([#'3gpp_ro_Multiple-Services-Credit-Control'
		{'Service-Identifier' = SI, 'Rating-Group' = RG} = _MSCC | T], Acc) ->
	NewMSCC = #'3gpp_ro_Multiple-Services-Credit-Control'
			{'Service-Identifier' = SI, 'Rating-Group' = RG},
	build_container(T, [NewMSCC | Acc]);
build_container([], Acc) ->
	lists:reverse(Acc).

-spec build_mscc(ServiceRatings, Container) -> Result
	when
		ServiceRatings :: [service_rating()],
		Container :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		Result :: {ResultCode, [#'3gpp_ro_Multiple-Services-Credit-Control'{}]},
		ResultCode :: pos_integer().
%% @doc Build a list of CCA MSCCs
build_mscc(ServiceRatings, Container) ->
	build_mscc(ServiceRatings, Container, undefined).
%% @hidden
build_mscc([H | T], Container, FinalResultCode) ->
	F = fun F(#{"serviceId" := SI, "ratingGroup" := RG, "resultCode" := RC} = ServiceRating,
			[#'3gpp_ro_Multiple-Services-Credit-Control'
					{'Service-Identifier' = [SI], 'Rating-Group' = [RG]} = MSCC1 | T1], Acc) ->
				case catch gsu(maps:get("grantedUnit", ServiceRating)) of
					#'3gpp_ro_Granted-Service-Unit'{} = GSU ->
						RC2 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Granted-Service-Unit' = [GSU],
								'Result-Code' = [RC2]},
						{RC2, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					_ ->
						RC2 = result_code(RC),
						RC3 = case FinalResultCode of
							undefined ->
								RC2;
							_ ->
								FinalResultCode
						end,
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Result-Code' = [RC2]},
						{RC3, lists:reverse(T1) ++ [MSCC2] ++ Acc}
				end;
		F(#{"serviceId" := SI, "resultCode" := RC} = ServiceRating,
			[#'3gpp_ro_Multiple-Services-Credit-Control'
					{'Service-Identifier' = [SI], 'Rating-Group' = []} = MSCC1 | T1], Acc) ->
				case catch gsu(maps:get("grantedUnit", ServiceRating)) of
					[] ->
						RC2 = result_code(RC),
						RC3 = case FinalResultCode of
							undefined ->
								RC2;
							_ ->
								FinalResultCode
						end,
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Result-Code' = [RC2]},
						{RC3, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					#'3gpp_ro_Granted-Service-Unit'{} = GSU ->
						RC2 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Granted-Service-Unit' = [GSU],
								'Result-Code' = [RC2]},
						{RC2, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					_ ->
						{FinalResultCode, lists:reverse(T1) ++ Acc}
				end;
			F(#{"ratingGroup" := RG, "resultCode" := RC} = ServiceRating,
					[#'3gpp_ro_Multiple-Services-Credit-Control'
							{'Service-Identifier' = [], 'Rating-Group' = [RG]} = MSCC1 | T1], Acc) ->
				case catch gsu(maps:get("grantedUnit", ServiceRating)) of
					#'3gpp_ro_Granted-Service-Unit'{} = GSU ->
						RC2 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Granted-Service-Unit' = [GSU],
								'Result-Code' = [RC2]},
						{RC2, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					_ ->
						RC2 = result_code(RC),
						RC3 = case FinalResultCode of
							undefined ->
								RC2;
							_ ->
								FinalResultCode
						end,
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Result-Code' = [RC2]},
						{RC3, lists:reverse(T1) ++ [MSCC2] ++ Acc}
				end;
			F(ServiceRating, [H1 | T1], Acc) ->
				F(ServiceRating, T1, [H1 | Acc])
	end,
	{NewFRC, NewContainer} = F(H, Container, []),
	build_mscc(T, NewContainer, NewFRC);
build_mscc([], NewContainer, FinalResultCode) ->
	{FinalResultCode, lists:reverse(NewContainer)}.

-spec diameter_answer(SessionId, MSCC, ResultCode,
		OriginHost, OriginRealm, RequestType, RequestNum) -> Result
	when
			SessionId :: binary(),
			MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
			ResultCode :: pos_integer(),
			OriginHost :: string(),
			OriginRealm :: string(),
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
		OriginHost :: string(),
		OriginRealm :: string(),
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

-spec call_parties(ServiceInformation) -> Result
	when
		ServiceInformation :: [#'3gpp_ro_Service-Information'{}],
		Result :: {Calling, Called},
		Calling :: undefined | [Digit],
		Called :: undefined | [Digit],
		Digit :: $0..$9.
%% @doc Extract call party addresses.
%% @hidden
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [],
		'Called-Party-Address' = [CalledParty]}]}]) ->
	{undefined, address(CalledParty)};
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [CallingParty],
		'Called-Party-Address' = []}]}]) ->
	{address(CallingParty), undefined};
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = [#'3gpp_ro_IMS-Information'{
		'Calling-Party-Address' = [CallingParty],
		'Called-Party-Address' = [CalledParty]}]}]) ->
	{address(CallingParty), address(CalledParty)};
call_parties([#'3gpp_ro_Service-Information'{
		'IMS-Information' = []}]) ->
	{undefined, undefined};
call_parties([]) ->
	{undefined, undefined}.

%% @hidden
address(<<"tel:", Dest/binary>>) ->
	binary_to_list(Dest);
address(Dest) ->
	binary_to_list(Dest).

-spec log(OldState, Data) -> ok
	when
		OldState :: atom(),
		Data :: statedata().
%% Log an event.
%% @hidden
log(State,
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
	cse_log:blog(?LOGNAME, {Start, Stop, ?SERVICENAME,
			State, Subscriber, Call, Network, OCS}).

