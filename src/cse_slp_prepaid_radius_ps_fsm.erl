%%% cse_slp_prepaid_radius_ps_fsm.erl
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
%%% 	for RADIUS authentication and accounting within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This Service Logic Program (SLP) implements a 3GPP Online
%%% 	Charging Function (OCF) interfacing across the <i>Re</i> reference
%%% 	point interafce, using the
%%% 	<a href="https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0">
%%% 	Nrf_Rating</a> API, with a remote <i>Rating Function</i>.
%%%
%%% 	This SLP specifically handles Packet Switched (PS) data
%%% 	service usage with `Service-Context-Id' of `32251@3gpp.org'.
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
%%% 	<img alt="state machine" src="prepaid-diameter-data.svg" />
%%%
-module(cse_slp_prepaid_radius_ps_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, authorize_origination_attempt/3,
		collect_information/3, analyse_information/3, active/3]).
%% export the private api
-export([nrf_start_reply/2, nrf_update_reply/2, nrf_release_reply/2]).

-include_lib("radius/include/radius.hrl").
-include_lib("kernel/include/logger.hrl").
-include("cse.hrl").
-include("cse_codec.hrl").

-define(PS_CONTEXTID, "32251@3gpp.org").
-define(SERVICENAME, "Prepaid Data").
-define(FSM_LOGNAME, prepaid).
-define(NRF_LOGNAME, rating).

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 23).
		-define(HMAC(Key, Data), crypto:mac(hmac, md5, Key, Data)).
	-else.
		-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
	-endif.
-else.
	-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
-endif.

-type state() :: null
		| authorize_origination_attempt
		| collect_information | analyse_information | active.

-type statedata() :: #{start := pos_integer(),
		from => pid(),
		nas_client => cse:client(),
		nas_id => string(),
		nas_port => inet:port_number(),
		context => string(),
		session_id => binary(),
		req_id => byte(),
		req_authenticator => [byte()],
		username => string(),
		password => string(),
		sequence => pos_integer(),
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
%%  The cse_slp_prepaid_radius_ps_fsm gen_statem callbacks
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
init([Client, NasId, Port, UserName, Password | _ExtraArgs]) ->
	{ok, Profile} = application:get_env(cse, nrf_profile),
	{ok, URI} = application:get_env(cse, nrf_uri),
	{ok, HttpOptions} = application:get_env(nrf_http_options),
	{ok, Headers} = application:get_env(nrf_headers),
	Data = #{context => "32251@3gpp.org",
			nrf_profile => Profile, nrf_uri => URI,
			nrf_http_options => HttpOptions, nrf_headers => Headers,
			start => erlang:system_time(millisecond),
			username => UserName, password => Password,
			nas_client => Client, nas_id => NasId,
			nas_port => Port, sequence => 1},
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
null(enter = _EventType, _OldState, _Data) ->
	{stop, shutdown};
null({call, _From},
		#radius{code = ?AccessRequest}, Data) ->
	{next_state, authorize_origination_attempt, Data, postpone};
null({call, _From},
		#radius{code = ?AccountingRequest}, Data) ->
	{next_state, active, Data, postpone}.

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
		#radius{code = ?AccessRequest, id = ReqId,
				authenticator = RequestAuthenticator,
				attributes = AttributeData}, Data) ->
	Attributes = radius_attributes:codec(AttributeData),
	case radius_attributes:find(?AcctSessionId, Attributes) of
		{ok, SessionId} ->
			SessionId1 = list_to_binary(SessionId),
			NewData = Data#{from => From, req_id => ReqId,
					req_authenticator => RequestAuthenticator,
					session_id => SessionId1},
			cse:add_session(SessionId1, self()),
			nrf_start(NewData);
		{error, not_found} ->
			NewData = Data#{from => From, req_id => ReqId,
					req_authenticator => RequestAuthenticator},
			Reply = radius_result("MANDATORY_IE_MISSING", NewData),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{_, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nas_id := NasId} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := _ServiceRating}}, {_, Location}}
				when is_list(Location) ->
			Reply = radius_result("SUCCESS", Data),
			NewData = remove_req(Data#{nrf_location => Location}),
			Actions = [{reply, From, Reply}],
			{next_state, collect_information, NewData, Actions};
		{{error, Partial, Remaining}, Location} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location},
					{slpi, self()}, {nas, NasId},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			NewData = remove_req(Data),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{_, 400, _Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_http := _LogHTTP} = Data) ->
	Reply = radius_result("SYSTEM_FAILURE", Data),
	NewData = remove_req(Data),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{_, 404, _Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_http := _LogHTTP} = Data) ->
	Reply = radius_result("USER_UNKNOWN", Data),
	NewData = remove_req(Data),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{_, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := _LogHTTP, nrf_uri := URI,
				nas_id := NasId} = Data) ->
	case {zj:decode(Body), lists:keyfind("content-type", 1, Headers)} of
		{{ok, #{"cause" := Cause}}, {_, "application/problem+json" ++ _}} ->
			Reply = radius_result(Cause, Data),
			NewData = remove_req(Data),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {status, 403},
					{slpi, self()}, {nas, NasId},
					{partial, Partial}, {remaining, Remaining},
					{state, authorize_origination_attempt}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			NewData = remove_req(Data),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end;
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {{_, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nas_id := NasId} = Data) ->
	?LOG_WARNING([{?MODULE, nrf_start},
			{code, Code}, {reason, Phrase},
			{request_id, RequestId},
			{profile, Profile}, {uri, URI},
			{slpi, self()}, {nas, NasId},
			{state, authorize_origination_attempt}]),
	Reply = radius_result("SYSTEM_FAILURE", Data),
	NewData = remove_req(Data),
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
authorize_origination_attempt(cast,
		{nrf_start, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nas_id := NasId} = Data) ->
	?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()}, {nas, NasId},
			{state, authorize_origination_attempt}]),
	Reply = radius_result("SYSTEM_FAILURE", Data),
	NewData = remove_req(Data),
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
		#radius{code = ?AccessRequest, id = ReqId,
				authenticator = RequestAuthenticator},
		Data) ->
	% @todo challenge response
	Reply = radius_result("UNSPECIFIED_MSG_FAILURE", Data),
	NewData = Data#{from => From, req_id => ReqId,
			req_authenticator => RequestAuthenticator},
	Actions = [{reply, From, Reply}],
	{next_state, null, NewData, Actions};
collect_information({call, _From},
		#radius{code = ?AccountingRequest}, Data) ->
	{next_state, active, Data, postpone}.

-spec analyse_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>analyse_information</em> state.
%% @private
analyse_information(_, _EventContent, _Data) ->
	keep_state_and_data.

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
		#radius{code = ?AccountingRequest, id = ReqId,
				authenticator = RequestAuthenticator,
				attributes = AttributeData},
		Data) when is_map_key(session_id, Data) == false ->
	NewData = Data#{from => From, req_id => ReqId,
			req_authenticator => RequestAuthenticator},
	Attributes = radius_attributes:codec(AttributeData),
	case {radius_attributes:find(?AcctSessionId, Attributes),
			radius_attributes:find(?AcctStatusType, Attributes)} of
		{{ok, SessionId}, {ok, ?AccountingStart}} ->
			SessionId1 = list_to_binary(SessionId),
			NextData = Data#{session_id => SessionId1},
			cse:add_session(SessionId1, self()),
			nrf_start(NextData);
		_ ->
			Actions = [{reply, From, ignore}],
			{next_state, null, NewData, Actions}
	end;
active({call, From},
		#radius{code = ?AccountingRequest, id = ReqId,
				authenticator = RequestAuthenticator,
				attributes = AttributeData},
		#{session_id := SessionId} = Data) ->
	NewData = Data#{from => From, req_id => ReqId,
			req_authenticator => RequestAuthenticator},
	SessionId1 = binary_to_list(SessionId),
	Attributes = radius_attributes:codec(AttributeData),
	case {radius_attributes:find(?AcctSessionId, Attributes),
			radius_attributes:find(?AcctStatusType, Attributes)} of
		{{ok, SessionId1}, {ok, ?AccountingStart}} ->
			nrf_update(NewData);
		{{ok, SessionId1}, {ok, ?AccountingInterimUpdate}} ->
			nrf_update(NewData);
		{{ok, SessionId1}, {ok, ?AccountingStop}} ->
			nrf_release(NewData);
		_Other ->
			Actions = [{reply, From, ignore}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{nrf_start, {RequestId, {{_, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nas_id := NasId} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := _ServiceRating}}, {_, Location}}
				when is_list(Location) ->
			Reply = radius_response(?AccountingResponse, [], Data),
			NewData = remove_req(Data),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions};
		{{error, Partial, Remaining}, Location} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location},
					{slpi, self()}, {nas, NasId},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			NewData = remove_req(Data),
			Actions = [{reply, From, ignore}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{_, 200, _Phrase}, _Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nrf_location := Location, nas_id := NasId} = Data)
		when NrfOperation == nrf_update;
		NrfOperation == nrf_release ->
	case zj:decode(Body) of
		{ok, #{"serviceRating" := _ServiceRating}} ->
			Reply = radius_response(?AccountingResponse, [], Data),
			NewData = remove_req(Data),
			Actions = [{reply, From, Reply}],
			case NrfOperation of
				nrf_update ->
					{keep_state, NewData, Actions};
				nrf_release ->
					{next_state, null, NewData, Actions}
			end;
		{error, Partial, Remaining} ->
			?LOG_ERROR([{?MODULE, NrfOperation}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {location, Location},
					{slpi, self()}, {nas, NasId},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			NewData = remove_req(Data),
			Actions = [{reply, From, ignore}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{_NrfOperation, {RequestId, {{_, 400, _Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_http := _LogHTTP} = Data) ->
	NewData = remove_req(Data),
	Actions = [{reply, From, ignore}],
	{next_state, null, NewData, Actions};
active(cast,
		{_NrfOperation, {RequestId, {{_, 404, _Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId,
				nrf_http := _LogHTTP} = Data) ->
	NewData = remove_req(Data),
	Actions = [{reply, From, ignore}],
	{next_state, null, NewData, Actions};
active(cast,
		{NrfOperation, {RequestId, {{_, 403, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_http := _LogHTTP, nrf_uri := URI,
				nas_id := NasId} = Data) ->
	NewData = remove_req(Data),
	case {zj:decode(Body), lists:keyfind("content-type", 1, Headers)} of
		{{ok, #{"cause" := _Cause}}, {_, "application/problem+json" ++ _}} ->
			Actions = [{reply, From, ignore}],
			{next_state, null, NewData, Actions};
		{{error, Partial, Remaining}, _} ->
			?LOG_ERROR([{?MODULE, NrfOperation}, {error, invalid_json},
					{request_id, RequestId}, {profile, Profile},
					{uri, URI}, {status, 403},
					{slpi, self()}, {nas, NasId},
					{partial, Partial}, {remaining, Remaining},
					{state, active}]),
			Actions = [{reply, From, ignore}],
			{next_state, null, NewData, Actions}
	end;
active(cast,
		{NrfOperation, {RequestId, {{_, Code, Phrase}, _Headers, _Body}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nas_id := NasId} = Data) ->
	NewData = remove_req(Data),
	?LOG_WARNING([{?MODULE, NrfOperation},
			{code, Code}, {reason, Phrase},
			{request_id, RequestId},
			{profile, Profile}, {uri, URI},
			{slpi, self()}, {nas, NasId},
			{state, active}]),
	Actions = [{reply, From, ignore}],
	{next_state, null, NewData, Actions};
active(cast,
		{NrfOperation, {RequestId, {error, Reason}}},
		#{from := From, nrf_reqid := RequestId, nrf_profile := Profile,
				nrf_uri := URI, nrf_http := _LogHTTP,
				nas_id := NasId} = Data) ->
	NewData = remove_req(Data),
	?LOG_ERROR([{?MODULE, NrfOperation}, {error, Reason},
			{request_id, RequestId}, {profile, Profile},
			{uri, URI}, {slpi, self()}, {nas, NasId},
			{state, active}]),
	Actions = [{reply, From, ignore}],
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
		Actions :: [{reply, From, #radius{}}],
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
				nrf_uri := URI, nrf_http_options := HttpOptions,
				nrf_headers := Headers } = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	% @todo synchronous start
	Options = [{sync, false}, {receiver, MFA}],
	AcceptType = "application/json, application/problem+json",
	Headers1 = [{"accept", AcceptType} | Headers],
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
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			Actions = [{reply, From, Reply}],
			{keep_state, Data, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			Actions = [{reply, From, Reply}],
			{keep_state, Data, Actions}
	end.

-dialyzer({no_unused, [nrf_update/1, nrf_update1/2, nrf_update2/3]}).
-spec nrf_update(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {keep_state, Data, Actions},
		Actions :: [{reply, From, #radius{}}],
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
	JSON1 = JSON#{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => subscription_id(Data)},
	NewData = Data#{sequence => NewSequence},
	nrf_update2(Now, JSON1, NewData).
%% @hidden
nrf_update2(Now, JSON,
		#{from := From, nrf_profile := Profile, nrf_uri := URI,
				nrf_http_options := HttpOptions, nrf_headers := Headers,
				nrf_location := Location} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_update_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	AcceptType = "application/json, application/problem+json",
	Headers1 = [{"accept", AcceptType} | Headers],
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
					{location, Location}, {slpi, self()}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			NewData = maps:remove(nrf_location, Data),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_update}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			NewData = maps:remove(nrf_location, Data),
			Actions = [{reply, From, Reply}],
			{keep_state, NewData, Actions}
	end.

-dialyzer({no_unused, [nrf_release/1, nrf_release1/2, nrf_release2/3]}).
-spec nrf_release(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {keep_state, Data, Actions},
		Actions :: [{reply, From, #radius{}}],
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
				nrf_location := Location} = Data)
		when is_list(Location) ->
	MFA = {?MODULE, nrf_release_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	AcceptType = "application/json, application/problem+json",
	Headers1 = [{"accept", AcceptType} | Headers],
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
					{location, Location}, {slpi, self()}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			NewData = maps:remove(nrf_location, Data),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_release}, {error, Reason},
					{profile, Profile}, {uri, URI},
					{location, Location}, {slpi, self()}]),
			Reply = radius_result("SYSTEM_FAILURE", Data),
			NewData = maps:remove(nrf_location, Data),
			Actions = [{reply, From, Reply}],
			{next_state, null, NewData, Actions}
	end.

-spec service_rating(Data) -> ServiceRating
	when
		Data :: statedata(),
		ServiceRating :: [map()].
%% @doc Build a `serviceRating' array.
%% @hidden
service_rating(#{context := ServiceContextId} = _Data) ->
	[#{"serviceContextId" => ServiceContextId,
			"requestSubType" => "RESERVE"}];
service_rating(_Data) ->
	[].

%% @hidden
subscription_id(Data) ->
	subscription_id1(Data, []).
%% @hidden
subscription_id1(#{username := Username} = _Data, Acc)
		when is_list(Username) ->
	["nai-" ++ Username | Acc].

-spec radius_result(ResultCode, Data) -> Response
	when
		ResultCode :: string(),
		Data :: statedata(),
		Response :: #radius{}.
%% @doc Convert an Nrf ResultCode to a RADIUS reply message.
%% @hidden
% 3GPP TS 32.291 6.1.7.3-1
radius_result("CHARGING_FAILED", Data) ->
	Attributes = [{?ReplyMessage, "Rating failed"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("RE_AUTHORIZATION_FAILED", Data) ->
	Attributes = [{?ReplyMessage, "End user service denied"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("CHARGING_NOT_APPLICABLE", Data) ->
	Attributes = [{?ReplyMessage, "Credit control not applicable"}],
	radius_response(?AccessAccept, Attributes, Data);
radius_result("USER_UNKNOWN", Data) ->
	Attributes = [{?ReplyMessage, "User unknown"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("END_USER_REQUEST_DENIED", Data) ->
	Attributes = [{?ReplyMessage, "End user service denied"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("QUOTA_LIMIT_REACHED", Data) ->
	Attributes = [{?ReplyMessage, "Credit limit reached"}],
	radius_response(?AccessReject, Attributes, Data);
% 3GPP TS 32.291 6.1.6.3.14-1
radius_result("SUCCESS", Data) ->
	Attributes = [{?ReplyMessage, "Success"}],
	radius_response(?AccessAccept, Attributes, Data);
radius_result("END_USER_SERVICE_DENIED", Data) ->
	Attributes = [{?ReplyMessage, "End user service denied"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("QUOTA_MANAGEMENT_NOT_APPLICABLE", Data) ->
	Attributes = [{?ReplyMessage, "Credit control not applicable"}],
	radius_response(?AccessAccept, Attributes, Data);
radius_result("END_USER_SERVICE_REJECTED", Data) ->
	Attributes = [{?ReplyMessage, "End user service denied"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("RATING_FAILED", Data) ->
	Attributes = [{?ReplyMessage, "Rating failed"}],
	radius_response(?AccessReject, Attributes, Data);
% 3GPP TS 29.500 5.2.7.2-1
radius_result("SYSTEM_FAILURE", Data) ->
	Attributes = [{?ReplyMessage, "Unable to comply"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("MANDATORY_IE_MISSING", Data) ->
	Attributes = [{?ReplyMessage, "Unable to comply"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("MANDATORY_IE_INCORRECT", Data) ->
	Attributes = [{?ReplyMessage, "Unable to comply"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result("UNSPECIFIED_MSG_FAILURE", Data) ->
	Attributes = [{?ReplyMessage, "Unable to comply"}],
	radius_response(?AccessReject, Attributes, Data);
radius_result(_, Data) ->
	Attributes = [{?ReplyMessage, "Unable to comply"}],
	radius_response(?AccessReject, Attributes, Data).

-spec radius_response(RadiusCode, ResponseAttributes, Data) -> Response
	when
		RadiusCode :: byte(),
		ResponseAttributes :: radius_attributes:attributes(),
		Data :: statedata(),
		Response :: #radius{}.
%% @doc Construct a RADIUS response.
%% @hidden
radius_response(RadiusCode, ResponseAttributes,
		#{req_id := RadiusId,
				req_authenticator := RequestAuthenticator,
				nas_client := #client{secret = Secret}} = _Data)
		when RadiusCode == ?AccessAccept;
		RadiusCode == ?AccessReject;
		RadiusCode == ?AccessChallenge ->
	AttributeList1 = radius_attributes:add(?MessageAuthenticator,
			<<0:128>>, ResponseAttributes),
	Attributes1 = radius_attributes:codec(AttributeList1),
	Length = size(Attributes1) + 20,
	MessageAuthenticator = ?HMAC(Secret,
			[<<RadiusCode, RadiusId, Length:16>>,
			RequestAuthenticator, Attributes1]),
	AttributeList2 = radius_attributes:store(?MessageAuthenticator,
			MessageAuthenticator, AttributeList1),
	Attributes2 = radius_attributes:codec(AttributeList2),
	ResponseAuthenticator = crypto:hash(md5,
			[<<RadiusCode, RadiusId, Length:16>>,
			RequestAuthenticator, Attributes2, Secret]),
	#radius{code = RadiusCode, id = RadiusId,
			authenticator = ResponseAuthenticator,
			attributes = Attributes2};
radius_response(RadiusCode, ResponseAttributes,
		#{req_id := RadiusId,
				req_authenticator := RequestAuthenticator,
				nas_client := #client{secret = Secret}} = _Data)
		when RadiusCode == ?AccountingResponse ->
	Attributes = radius_attributes:codec(ResponseAttributes),
	Length = size(Attributes) + 20,
	ResponseAuthenticator = crypto:hash(md5,
			[<<RadiusCode, RadiusId, Length:16>>,
			RequestAuthenticator, Attributes, Secret]),
	#radius{code = RadiusCode, id = RadiusId,
			authenticator = ResponseAuthenticator,
			attributes = Attributes}.

-spec ecs_http(MIME, Body) -> HTTP
	when
		MIME :: string(),
		Body :: binary() | iolist(),
		HTTP :: map().
%% @doc Construct ECS JSON `map()' for Nrf request.
 % @hidden
ecs_http(MIME, Body) ->
	Body1 = #{"bytes" => iolist_size(Body),
			"content" => zj:encode(Body)},
	Request = #{"method" => "post",
			"mime_type" => MIME,
			"body" => Body1},
	#{"request" => Request}.

-dialyzer({no_unused, ecs_http/5}).
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

%% @hidden
remove_req(Data) ->
	Data1 = maps:remove(from, Data),
	Data2 = maps:remove(req_id, Data1),
	Data3 = maps:remove(req_authenticator, Data2),
	Data4 = maps:remove(nrf_start, Data3),
	Data5 = maps:remove(nrf_req_url, Data4),
	Data6 = maps:remove(nrf_http, Data5),
	maps:remove(nrf_reqid, Data6).

