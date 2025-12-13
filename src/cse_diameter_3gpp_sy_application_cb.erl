%%% cse_diameter_3gpp_sy_application_cb.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2025 SigScale Global Inc.
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
%%% @doc This {@link //diameter/diameter_app. diameter_app}
%%% 	behaviour callback module handles {@link //diameter. diameter}
%%% 	messages for the 3GPP DIAMETER Sy application
%%% 	in the {@link //cse. cse} application.
%%%
%%% ==Interworking Function (IWF)==
%%% The {@link //cse. cse} application provides an IWF between the
%%% 3GPP reference architecture interface points Sy (EPC) and N28 (5GC).
%%% 
%%% This module implements the DIAMETER <i>Sy</i> application for
%%% communication with a Policy and Charging Rules Function (PCRF)
%%% of the Evolved Packet Core (EPC) and consumes the
%%% <i>Nchf_SpendingLimitControl</i> service produced by a Charging
%%% Function (CHF) of the 5G Core (5GC).
%%%
%%% ==Configuration==
%%% DIAMETER services provided by the {@link //cse. cse} application
%%% are configured with the `diameter' application environment variable.
%%%
%%% An instance of this IWF requires a dedicated `diameter' service
%%% (`{Addr, Port, Options}') where `Options' includes:
%%%  <div class="spec">
%%%  <p><tt>{module, [Module, Config]}</tt>
%%%  <ul class="definitions">
%%%    <li>
%%% 		<tt>
%%% 			Module = {@module}
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Config = #{nchf_profile => Profile,
%%% 			nchf_uri => URI,
%%% 			nchf_resolver => Resolver,
%%% 			nchf_sort => Sort,
%%% 			nchf_retries => Retries,
%%% 			nchf_http_options => HttpOptions,
%%% 			nchf_Headers => Headers}
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Profile = atom()
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			URI = string()
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Resolver = {M :: atom(), F :: atom()}
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Sort = random | none
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Retries = pos_integer()
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			HttpOptions = [HttpOption]
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			HttpOption = {timeout, timeout()}
%%% 					| {connect_timeout, timeout()}
%%% 					| {ssl, [ssl:tls_option()]}
%%% 					| {autoredirect, boolean()}
%%% 					| {proxy_auth, {string(), string()}}
%%% 					| {version, HttpVersion}
%%% 					| {relaxed, boolean()}
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Headers = [Header]
%%% 		</tt>
%%% 	</li>
%%%   <li>
%%% 		<tt>
%%% 			Header = {Field :: [byte()], Value :: binary() | iolist()}
%%% 		</tt>
%%% 	</li>
%%%  </ul></p>
%%%  </div>
%%%
%%% @reference 3GPP TS <a
%%% href="https://webapp.etsi.org/key/key.asp?GSMSpecPart1=29&amp;GSMSpecPart2=219">
%%% 29.219</a> Spending limit reporting over Sy reference point
%%%
-module(cse_diameter_3gpp_sy_application_cb).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

-export([peer_up/4, peer_down/4, pick_peer/5, prepare_request/4,
			prepare_retransmit/4, handle_answer/5, handle_error/5,
			handle_request/4]).

-include_lib("kernel/include/logger.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_sy_application.hrl").

-record(state, {}).

-define(LOGNAME, '3gpp_sy').
-define(SY_APPLICATION_ID, 16777302).

-type state() :: #state{}.
-type capabilities() :: #diameter_caps{}.
-type packet() ::  #diameter_packet{}.
-type message() ::  tuple() | list().
-type peer() :: {Peer_Ref :: term(), Capabilities :: capabilities()}.

-ifdef(OTP_RELEASE). % >= 21
	-define(CATCH_STACK, _:Reason:ST).
	-define(SET_STACK, StackTrace = ST).
-else.
	-define(CATCH_STACK, _:Reason).
	-define(SET_STACK, StackTrace = erlang:get_stacktrace()).
-endif.

%%----------------------------------------------------------------------
%%  The DIAMETER application callbacks
%%----------------------------------------------------------------------

-spec peer_up(ServiceName, Peer, State, Config) -> NewState
	when
		ServiceName :: diameter:service_name(),
		Peer ::  peer(),
		State :: state(),
		Config :: map(),
		NewState :: state().
%% @doc Invoked when the peer connection is available.
peer_up(_ServiceName, _Peer, State, _Config) ->
    State.

-spec peer_down(ServiceName, Peer, State, Config) -> NewState
	when
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		State :: state(),
		Config :: map(),
		NewState :: state().
%% @doc Invoked when the peer connection is not available.
peer_down(_ServiceName, _Peer, State, _Config) ->
    State.

-spec pick_peer(LocalCandidates, RemoteCandidates,
			ServiceName, State, Config) -> Result
	when
		LocalCandidates :: [peer()],
		RemoteCandidates :: [peer()],
		ServiceName :: diameter:service_name(),
		State :: state(),
		Config :: map(),
		NewState :: state(),
		Selection :: {ok, Peer} | {Peer, NewState},
		Peer :: peer() | false,
		Result :: Selection | false.
%% @doc Pick a destination peer for an outgoing request.
pick_peer([Peer | _] = _LocalCandidates, _RemoteCandidates,
		_ServiceName, _State, _Config) ->
	{ok, Peer}.

-spec prepare_request(Packet, ServiceName, Peer, Config) -> Action
	when
		Packet :: packet(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Config :: map(),
		Action :: Send | Discard | {eval_packet, Action, PostF},
		Send :: {send, packet() | message()},
		Discard :: {discard, Reason} | discard,
		Reason :: term(),
		PostF :: diameter:evaluable().
%% @doc Invoked to return a request for encoding and transport.
prepare_request(#diameter_packet{} = Packet, _ServiceName, _Peer, _Config) ->
	{send, Packet}.

-spec prepare_retransmit(Packet, ServiceName, Peer, Config) -> Action
	when
		Packet :: packet(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Config :: map(),
		Action :: Send | Discard | {eval_packet, Action, PostF},
		Send :: {send, packet() | message()},
		Discard :: {discard, Reason} | discard,
		Reason :: term(),
		PostF :: diameter:evaluable().
%% @doc Invoked to return a request for encoding and retransmission.
prepare_retransmit(Packet, ServiceName, Peer, Config) ->
	prepare_request(Packet, ServiceName, Peer, Config).

-spec handle_answer(Packet, Request, ServiceName, Peer, Config) -> Result
	when
		Packet :: packet(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Config :: map(),
		Result :: term().
%% @doc Invoked when an answer message is received from a peer.
handle_answer(_Packet, _Request, _ServiceName, _Peer, _Config) ->
    not_implemented.

-spec handle_error(Reason, Request, ServiceName, Peer, Config) -> Result
	when
		Reason :: timeout | failover | term(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Config :: map(),
		Result :: term().
%% @doc Invoked when an error occurs before an answer message is received.
handle_error(_Reason, _Request, _ServiceName, _Peer, _Config) ->
	not_implemented.

-spec handle_request(Packet, ServiceName, Peer, Config) -> Action
	when
		Packet :: packet(),
		ServiceName :: term(),
		Peer :: peer(),
		Config :: map(),
		Action :: Reply | {relay, [Opt]} | discard
			| {eval | eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999|5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Invoked when a request message is received from the peer.
handle_request(#diameter_packet{errors = [], msg = Request} = _Packet,
		{_, IpAddress, Port} = ServiceName, {_, Capabilities} = Peer,
		Config) ->
	Start = erlang:system_time(millisecond),
	Reply = process_request(IpAddress, Port, Capabilities, Request, Config),
	Stop = erlang:system_time(millisecond),
	catch cse_log:blog(?LOGNAME, {Start, Stop, ServiceName, Peer, Request, Reply}),
	Reply;
handle_request(#diameter_packet{errors = Errors, msg = Request} = _Packet,
		ServiceName, {_, Capabilities} = Peer, _Config) ->
	Start = erlang:system_time(millisecond),
	Reply = errors(ServiceName, Capabilities, Request, Errors),
	Stop = erlang:system_time(millisecond),
	catch cse_log:blog(?LOGNAME, {Start, Stop, ServiceName, Peer, Request, Reply}),
	Reply.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec errors(ServiceName, Capabilities, Request, Errors) -> Action
	when
		ServiceName :: atom(),
		Capabilities :: capabilities(),
		Request :: message(),
		Errors :: [Error],
		Error :: {Code, #diameter_avp{}} | Code,
		Code :: 0..4294967295,
		Action :: Reply | {relay, [Opt]} | discard
			| {eval | eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999|5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Handle errors in requests.
%% @private
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_UNSUPPORTED', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP unsupported",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_AVP_UNSUPPORTED'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_VALUE', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP invalid",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_VALUE'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_MISSING_AVP', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP missing",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_MISSING_AVP'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_CONTRADICTING_AVPS', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVPs contradicting",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_CONTRADICTING_AVPS'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_NOT_ALLOWED', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP not allowed",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_AVP_NOT_ALLOWED'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_OCCURS_TOO_MANY_TIMES', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP too many times",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_AVP_OCCURS_TOO_MANY_TIMES'};
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_LENGTH', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP invalid length",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	{answer_message, ?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_LENGTH'};
errors(_ServiceName, _Capabilities, _Request, [{ResultCode, _} | _]) ->
	{answer_message, ResultCode};
errors(_ServiceName, _Capabilities, _Request, [ResultCode | _]) ->
	{answer_message, ResultCode}.

-spec process_request(IpAddress, Port, Caps, Request, Config) -> Result
	when
		IpAddress :: inet:ip_address(),
		Port :: inet:port_number(),
		Caps :: capabilities(),
		Request :: #'3gpp_sy_SLR'{},
		Config :: map(),
		Result :: {reply, message()} | {answer_message, 5000..5999}.
%% @doc Process a received DIAMETER packet.
%% @private
process_request(_IpAddress, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_sy_SLR'{'Session-Id' = SessionId,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'SL-Request-Type' = RequestType} = _Request, Config)
		when RequestType == ?'3GPP_SY_SL-REQUEST-TYPE_INITIAL_REQUEST' ->
	nchf_subscribe(<<>>, SessionId, OHost, ORealm, Config);
process_request(_IpAddress, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_sy_SLR'{'Session-Id' = SessionId,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'SL-Request-Type' = RequestType} = _Request, Config)
		when RequestType == ?'3GPP_SY_SL-REQUEST-TYPE_INTERMEDIATE_REQUEST' ->
	nchf_subscribe(<<>>, SessionId, OHost, ORealm, Config).

-spec nchf_subscribe(JSON, SessionId, OriginHost, OriginRealm, Config) -> Reply
	when
		JSON :: binary(),
		SessionId :: binary(),
		OriginHost :: string(),
		OriginRealm :: string(),
		Config :: map(),
		Reply :: {reply, #'3gpp_sy_SLA'{}}.
%% @doc Perform an Nchf_SpendingLimitControl_Subscribe operation.
%% @private
nchf_subscribe(JSON, SessionId, OriginHost, OriginRealm, Config) ->
	Config1 = add_nchf(Config),
	Profile = maps:get(nchf_profile, Config1, nchf),
	URI = maps:get(nchf_uri, Config1),
	NextURIs = maps:get(nchf_next_uris, Config1),
	Host = maps:get(nchf_host, Config1),
	Headers = maps:get(nchf_headers, Config1, []),
	HttpOptions = maps:get(nchf_http_options, Config,
			[{timeout, 1500}, {connect_timeout, 1500}]),
	RequestHeaders = [{"host", Host},
			{"accept", "application/json, application/problem+json"}
			| Headers],
	RequestBody = zj:encode(JSON),
	ContentType = "application/json",
	RequestURL = URI ++ "/subscriptions",
Body = [],
	LogHTTP = ecs_http(ContentType, Body),
	Request = {RequestURL, RequestHeaders, ContentType, RequestBody},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, [], Profile) of
		{{Version, 200, _Phrase}, ResponseHeaders, ResponseBody} ->
ok;
		{{Version, 201, _Phrase}, ResponseHeaders, ResponseBody} ->
ok;
		{{Version, 400, _Phrase}, ResponseHeaders, ResponseBody} ->
ok;
		{{Version, 404, _Phrase}, ResponseHeaders, ResponseBody} ->
ok;
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewConfig = Config#{nchf_uri => hd(NextURIs),
					nchf_next_uris => tl(NextURIs)},
			nchf_subscribe(JSON, SessionId,
					OriginHost, OriginRealm, NewConfig);
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, ?FUNCTION_NAME},
					{error, Reason}, {profile, Profile},
					{uri, URI}, {slpi, self()}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			diameter_error(SessionId, ResultCode, OriginHost, OriginRealm);
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
					{error, Reason}, {profile, Profile},
					{uri, URI}, {slpi, self()}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			diameter_error(SessionId, ResultCode, OriginHost, OriginRealm)
	end.

-spec diameter_error(SessionId, ResultCode, OriginHost, OriginRealm) -> Reply
	when
		SessionId :: binary(),
		ResultCode :: pos_integer(),
		OriginHost :: string(),
		OriginRealm :: string(),
		Reply :: {reply, #'3gpp_sy_SLA'{}}.
%% @doc Send SLA to DIAMETER client indicating an operation failure.
%% @hidden
diameter_error(SessionId, ResultCode, OriginHost, OriginRealm) ->
	SLA = #'3gpp_sy_SLA'{'Session-Id' = SessionId,
			'Auth-Application-Id' = ?SY_APPLICATION_ID,
			'Origin-Host' = OriginHost, 'Origin-Realm' = OriginRealm,
			'Result-Code' = [ResultCode]},
	{reply, SLA}.

%% @hidden
add_nchf(#{nchf_uri := URI} = Config) ->
	add_nchf(URI, Config, uri_string:parse(URI));
add_nchf(Config) ->
	URI = "http://chf.5gc.mnc001.mcc001.3gppnetwork.org"
			"/nchf-spendinglimitcontrol/v1/",
	add_nchf(Config#{nchf_uri => URI}).
%% @hidden
add_nchf(URI, Config, #{host := Address, port := Port} = _URIMap)
		when is_list(Address) ->
	Host = Address ++ ":" ++ integer_to_list(Port),
	Config1 = Config#{nchf_host => Host},
	add_nchf1(URI, Config1);
add_nchf(URI, Config, #{host := Address, port := Port} = _URIMap)
		when is_binary(Address) ->
	Host = binary_to_list(Address) ++ ":" ++ integer_to_list(Port),
	Config1 = Config#{nchf_host => Host},
	add_nchf1(URI, Config1);
add_nchf(URI, Config, #{host := Address} = _URIMap)
		when is_list(Address) ->
	Config1 = Config#{nchf_host => Address},
	add_nchf1(URI, Config1);
add_nchf(URI, Config, #{host := Address} = _URIMap)
		when is_binary(Address) ->
	Config1 = Config#{nchf_host => binary_to_list(Address)},
	add_nchf1(URI, Config1).
%% @hidden
add_nchf1(URI, #{nchf_resolver := {M, F},
		nchf_sort := Sort, nchf_retries := Retries} = Config) ->
	add_nchf2(M:F(URI, [{sort, Sort}, {max_uri, Retries + 1}]), Config);
add_nchf1(URI, Config)
		when not is_map_key(nchf_resolver, Config) ->
	add_nchf1(URI, Config#{nchf_resolver => {cse_rest, resolve}});
add_nchf1(URI, Config)
		when not is_map_key(nchf_sort, Config) ->
	add_nchf1(URI, Config#{nchf_sort => random});
add_nchf1(URI, Config)
		when not is_map_key(nchf_retries, Config) ->
	add_nchf1(URI, Config#{nchf_retries => 1}).
%% @hidden
add_nchf2(HostURI,
		#{nchf_retries := 0} = Config) ->
	Config#{nchf_uri => HostURI, nchf_next_uris => []};
add_nchf2([H | T], Config) ->
	Config#{nchf_uri => H, nchf_next_uris => T}.

-spec ecs_http(MIME, Body) -> HTTP
	when
		MIME :: string(),
		Body :: binary() | iolist(),
		HTTP :: map().
%% @doc Construct ECS JSON map() for Nchf request.
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
%% @doc Construct ECS JSON map() for Nchf response.
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

