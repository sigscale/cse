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
%%% == Message Sequence ==
%%% The diagram below depicts the normal sequence of exchanged messages:
%%%
%%% <img alt="message sequence chart" src="pcrf-iwf-chf-msc.svg" />
%%%
%%% ==Configuration==
%%% DIAMETER services provided by the {@link //cse. cse} application
%%% are configured with the `diameter' application environment variable.
%%%
%%% An instance of this IWF requires a dedicated `diameter' service
%%% (`{Addr, Port, Options}') where `Options' includes:
%%% <div class="spec">
%%% 	<p>
%%% 		<tt>{module, [Module, Config]}</tt>
%%% 		<ul class="definitions">
%%% 			<li>
%%% 				<tt>
%%% 					Module = {@module}
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Config = #{nchf_profile => Profile,
%%% 					nchf_uri := URI,
%%% 					nchf_resolver => Resolver,
%%% 					nchf_sort => Sort,
%%% 					nchf_retries => Retries,
%%% 					nchf_http_options => HttpOptions,
%%% 					nchf_Headers => Headers,
%%% 					notify_uri := URI}
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Profile = atom()
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					URI = string()
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Resolver = {M :: atom(), F :: atom()}
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Sort = random | none
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Retries = pos_integer()
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					HttpOptions = [HttpOption]
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					HttpOption = {timeout, timeout()}
%%% 							| {connect_timeout, timeout()}
%%% 							| {ssl, [ssl:tls_option()]}
%%% 							| {autoredirect, boolean()}
%%% 							| {proxy_auth, {string(), string()}}
%%% 							| {version, HttpVersion}
%%% 							| {relaxed, boolean()}
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Headers = [Header]
%%% 				</tt>
%%% 			</li>
%%% 			<li>
%%% 				<tt>
%%% 					Header = {Field :: [byte()], Value :: binary() | iolist()}
%%% 				</tt>
%%% 			</li>
%%% 		</ul>
%%% 	</p>
%%% </div>
%%% Mandatory in `Config': `nchf_uri', `notify_uri'.
%%%
%%% @reference 3GPP TS <a
%%% href="https://webapp.etsi.org/key/key.asp?GSMSpecPart1=29&amp;GSMSpecPart2=219">
%%% 29.219</a> Spending limit reporting over Sy reference point
%%%
%%% @todo Fixed Broadband Access (3GPP TS 29.219 Annex A)
%%%
-module(cse_diameter_3gpp_sy_application_cb).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

-export([peer_up/4, peer_down/4, pick_peer/5, prepare_request/4,
			prepare_retransmit/4, handle_answer/5, handle_error/5,
			handle_request/4]).
-export([init/1]).

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

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 27).
		-behaviour(diameter_app).
	-endif.
-endif.

%%----------------------------------------------------------------------
%%  The DIAMETER application callbacks
%%----------------------------------------------------------------------

-spec init(ServiceStateData) -> Result
	when
		ServiceStateData :: cse_diameter_service_fsm:statedata(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Initialize Sy application diameter service.
init(_ServiceStateData) ->
	Module = cse_slp_spending_limit_iwf_fsm,
	Args = [[]],
	Opts = [],
	case supervisor:start_child(cse_slp_sup, [Module, Args, Opts]) of
		{ok, _Child} ->
			ok;
		{error, Reason} ->
			{error, Reason}
	end.

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
		Result :: {ok, Answer} | {error, ResultCode},
		Answer :: diameter_app:message(),
		ResultCode :: 0..4294967295.
%% @doc Invoked when an answer message is received from a peer.
handle_answer(#diameter_packet{errors = [], msg = Answer} = _Packet,
		_Request, _ServiceName, _Peer, _Config) ->
	{ok, Answer};
handle_answer(#diameter_packet{errors = Errors, msg = Request} = _Packet,
		_Request, ServiceName, {_, Capabilities} = _Peer, _Config) ->
	ResultCode = errors(ServiceName, Capabilities, Request, Errors),
	{error, ResultCode}.

-spec handle_error(Reason, Request, ServiceName, Peer, Config) -> Result
	when
		Reason :: timeout | failover | term(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Config :: map(),
		Result :: term().
%% @doc Invoked when an error occurs before an answer message is received.
handle_error(Reason, _Request, _ServiceName, _Peer, _Config) ->
	{error, Reason}.

-spec handle_request(Packet, ServiceName, Peer, Config) -> Action
	when
		Packet :: packet(),
		ServiceName :: term(),
		Peer :: peer(),
		Config :: map(),
		Action :: Reply | {relay, [Opt]} | discard
			| {eval | eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999 | 5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Invoked when a request message is received from the peer.
handle_request(#diameter_packet{errors = [], msg = Request} = _Packet,
		ServiceName, {_, Capabilities} = Peer,
		Config) ->
	Start = erlang:system_time(millisecond),
	Reply = process_request(ServiceName, Capabilities, Request, Config),
	Stop = erlang:system_time(millisecond),
	catch cse_log:blog(?LOGNAME, {Start, Stop, ServiceName, Peer, Request, Reply}),
	Reply;
handle_request(#diameter_packet{errors = Errors, msg = Request} = _Packet,
		ServiceName, {_, Capabilities} = Peer, _Config) ->
	Start = erlang:system_time(millisecond),
	ResultCode = errors(ServiceName, Capabilities, Request, Errors),
	Reply = {answer_message, ResultCode},
	Stop = erlang:system_time(millisecond),
	catch cse_log:blog(?LOGNAME, {Start, Stop, ServiceName, Peer, Request, Reply}),
	Reply.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec errors(ServiceName, Capabilities, Request, Errors) -> ResultCode
	when
		ServiceName :: term(),
		Capabilities :: capabilities(),
		Request :: message(),
		Errors :: [Error],
		Error :: {ResultCode, #diameter_avp{}} | ResultCode,
		ResultCode :: 0..4294967295.
%% @doc Parse and log errors.
%% @private
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_UNSUPPORTED', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP unsupported",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_AVP_UNSUPPORTED';
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_VALUE', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP invalid",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_VALUE';
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_MISSING_AVP', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP missing",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_MISSING_AVP';
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_CONTRADICTING_AVPS', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVPs contradicting",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_CONTRADICTING_AVPS';
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_NOT_ALLOWED', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP not allowed",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_AVP_NOT_ALLOWED';
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_AVP_OCCURS_TOO_MANY_TIMES', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP too many times",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_AVP_OCCURS_TOO_MANY_TIMES';
errors(ServiceName, Capabilities, _Request,
		[{?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_LENGTH', _} | _] = Errors) ->
	error_logger:error_report(["DIAMETER AVP invalid length",
			{service_name, ServiceName}, {capabilities, Capabilities},
			{errors, Errors}]),
	?'DIAMETER_BASE_RESULT-CODE_INVALID_AVP_LENGTH';
errors(_ServiceName, _Capabilities, _Request, [{ResultCode, _} | _]) ->
	ResultCode;
errors(_ServiceName, _Capabilities, _Request, [ResultCode | _]) ->
	ResultCode.

-spec process_request(ServiceName, Caps, Request, Config) -> Result
	when
		ServiceName :: term(),
		Caps :: capabilities(),
		Request :: #'3gpp_sy_SLR'{},
		Config :: map(),
		Result :: {reply, message()} | {answer_message, 5000..5999}.
%% @doc Process a received DIAMETER packet.
%% @todo `NotificationCorrelation' feature
%% @todo `ES3XX' feature
%% @todo `ASR' feature
%% @todo `Pending-Policy-Counter-Information' AVP
%% @private
process_request(ServiceName,
		#diameter_caps{origin_host = {OHost, _DHost},
				origin_realm = {ORealm, _DRealm}} = _Caps,
		#'3gpp_sy_SLR'{'Session-Id' = SessionId,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'Origin-Host' = OriginHost,
				'Origin-Realm' = OriginRealm,
				'SL-Request-Type' = RequestType,
				'Subscription-Id' = SubscriptionId,
				'Supported-Features' = _SupportedFeatures,
				'Policy-Counter-Identifier' = PolicyCounterId} = Request,
		Config)
		when RequestType == ?'3GPP_SY_SL-REQUEST-TYPE_INITIAL_REQUEST' ->
	try
		#{supi := SUPI} = SLC1 = supi(SubscriptionId, #{}),
		SLC2 = gpsi(SubscriptionId, SLC1),
		SLC3 = pcid(PolicyCounterId, SLC2),
		SLC4 = notify(Config, SLC3),
		SpendingLimitContext = SLC4#{supportedFeatures => "0"},
		Body = zj:encode(SpendingLimitContext),
		nchf_initial(Body, Config)
	of
		{201 = _StatusCode, ResponseHeaders,
				#{"statusInfos" := StatusInfos} = _ResponseBody}
				when is_map(StatusInfos) ->
			case lists:keyfind("location", 1, ResponseHeaders) of
				{_, Location} ->
					ets:insert(sy_session,
							{SessionId, SUPI, list_to_binary(Location)}),
					ets:insert(nchf_session,
							{SUPI, ServiceName, SessionId,
									OHost, ORealm, OriginHost, OriginRealm}),
					F = fun(PolicyCounterId1,
								#{"policyCounterId" := PolicyCounterId1,
								"currentStatus" := CurrentStatus}, Acc)
								when is_list(PolicyCounterId1),
								is_list(CurrentStatus) ->
							[#'3gpp_sy_Policy-Counter-Status-Report'{
									'Policy-Counter-Identifier' = PolicyCounterId1,
									'Policy-Counter-Status' = CurrentStatus} | Acc]
					end,
					PCSR = maps:fold(F, [], StatusInfos),
					ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
					SLA = #'3gpp_sy_SLA'{'Session-Id' = SessionId,
							'Auth-Application-Id' = ?SY_APPLICATION_ID,
							'Origin-Host' = OHost,
							'Origin-Realm' = ORealm,
							'Result-Code' = [ResultCode],
							'Supported-Features' = [],
							'Policy-Counter-Status-Report' = PCSR},
					{reply, SLA};
				false ->
					ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					ErrorMessage = ["Nchf response missing Location"],
					diameter_error(SessionId, OHost, ORealm,
							ResultCode, ErrorMessage, [])
			end;
		{StatusCode, ResponseHeaders, ResponseBody} ->
			{ResultCode, ErrorMessage, Failed} = case lists:keyfind("content-type",
					1, ResponseHeaders) of
				{_, "application/problem+json"} ->
					case zj:decode(ResponseBody) of
						{ok, #{"title" := Title,
								"cause" := "USER_UNKNOWN"} = _ProblemDetails}
								when StatusCode == 400 ->
							{?'IETF_RESULT-CODE_USER_UNKNOWN', [Title], []};
						{ok, #{"title" := Title,
								"cause" := "NO_AVAILABLE_POLICY_COUNTERS"} = _ProblemDetails}
								when StatusCode == 400 ->
							{?'3GPP_SY_EXPERIMENTAL-RESULT-CODE_NO_AVAILABLE_POLICY_COUNTERS',
									[Title], []};
						{ok, #{"title" := Title,
								"cause" := "UNKNOWN_POLICY_COUNTERS"} = ProblemDetails}
								when StatusCode == 400 ->
							RC = ?'3GPP_SY_EXPERIMENTAL-RESULT-CODE_UNKNOWN_POLICY_COUNTERS',
							case maps:get("invalidParams", ProblemDetails, undefined) of
								InvalidParams when is_list(InvalidParams) ->
									F = fun(#{"param" := PolicyCounterId2})
											when is_list(PolicyCounterId2) ->
										#diameter_avp{code = 2901,
												vendor_id = 10415,
												name = 'Policy-Counter-Identifier',
												type = 'UTF8String',
												is_mandatory = true,
												data = list_to_binary(PolicyCounterId2)}
									end,
									FailedAVP = lists:map(F, InvalidParams),
									{RC, [Title], FailedAVP};
								undefined ->
									{RC, [Title], []}
							end;
						{ok, #{"title" := Title} = _ProblemDetails} ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									[Title], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 400 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf client error"], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 401 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf client unauthorized"], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 500 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf server error"], []};
						{ok, #{} = _ProblemDetails} ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf unexpected problem response"], []};
						_ ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf decoding ProblemDetails failed"], []}
					end;
				_ when StatusCode == 400 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf client error"], []};
				_ when StatusCode == 401 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf client unauthorized"], []};
				_ when StatusCode == 500 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf server error"], []};
				_ ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf unexpected response"], []}
			end,
			diameter_error(SessionId, OHost, ORealm,
							ResultCode, ErrorMessage, Failed);
		{error, _Reason} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			ErrorMessage = ["Nchf transport error"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, [])
	catch
		throw:supi ->
			ResultCode = ?'IETF_RESULT-CODE_USER_UNKNOWN',
			ErrorMessage = ["SUPI (IMSI/NAI) missing"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, []);
		?CATCH_STACK ->
			?SET_STACK,
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
					{origin_host, OriginHost}, {origin_realm, OriginRealm},
					{request, Request},
					{error, Reason}, {stack, StackTrace}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			ErrorMessage = ["Unspecified error"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, [])
	end;
process_request(_ServiceName,
		#diameter_caps{origin_host = {OHost, _DHost},
				origin_realm = {ORealm, _DRealm}},
		#'3gpp_sy_SLR'{'Session-Id' = SessionId,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'Origin-Host' = OriginHost,
				'Origin-Realm' = OriginRealm,
				'SL-Request-Type' = RequestType,
				'Supported-Features' = _SupportedFeatures,
				'Policy-Counter-Identifier' = PolicyCounterId} = Request,
		Config)
		when RequestType == ?'3GPP_SY_SL-REQUEST-TYPE_INTERMEDIATE_REQUEST' ->
	try
		case ets:lookup(sy_session, SessionId) of
			[{_, SUPI, Location}] ->
				SLC1 = pcid(PolicyCounterId, #{}),
				SLC2 = notify(Config, SLC1),
				SpendingLimitContext = SLC2#{supi => SUPI,
						supportedFeatures => "0"},
				Body = zj:encode(SpendingLimitContext),
				nchf_intermediate(Location, Body, Config);
			[] ->
				throw(session)
		end
	of
		{200 = _StatusCode, _ResponseHeaders,
				#{"statusInfos" := StatusInfos} = _SpendingLimitStatus}
				when is_map(StatusInfos) ->
			F = fun(PolicyCounterId1,
						#{"policyCounterId" := PolicyCounterId1,
						"currentStatus" := CurrentStatus}, Acc)
						when is_list(PolicyCounterId1),
						is_list(CurrentStatus) ->
					[#'3gpp_sy_Policy-Counter-Status-Report'{
							'Policy-Counter-Identifier' = PolicyCounterId1,
							'Policy-Counter-Status' = CurrentStatus} | Acc]
			end,
			PCSR = maps:fold(F, [], StatusInfos),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			SLA = #'3gpp_sy_SLA'{'Session-Id' = SessionId,
					'Auth-Application-Id' = ?SY_APPLICATION_ID,
					'Origin-Host' = OHost,
					'Origin-Realm' = ORealm,
					'Result-Code' = [ResultCode],
					'Supported-Features' = [],
					'Policy-Counter-Status-Report' = PCSR},
			{reply, SLA};
		{StatusCode, ResponseHeaders, ResponseBody} ->
			{ResultCode, ErrorMessage, Failed} = case lists:keyfind("content-type",
					1, ResponseHeaders) of
				{_, "application/problem+json"} ->
					case zj:decode(ResponseBody) of
						{ok, #{"title" := Title,
								"cause" := "USER_UNKNOWN"} = _ProblemDetails}
								when StatusCode == 400 ->
							{?'IETF_RESULT-CODE_USER_UNKNOWN', [Title], []};
						{ok, #{"title" := Title,
								"cause" := "NO_AVAILABLE_POLICY_COUNTERS"} = _ProblemDetails}
								when StatusCode == 400 ->
							{?'3GPP_SY_EXPERIMENTAL-RESULT-CODE_NO_AVAILABLE_POLICY_COUNTERS',
									[Title], []};
						{ok, #{"title" := Title,
								"cause" := "UNKNOWN_POLICY_COUNTERS"} = ProblemDetails}
								when StatusCode == 400 ->
							RC = ?'3GPP_SY_EXPERIMENTAL-RESULT-CODE_UNKNOWN_POLICY_COUNTERS',
							case maps:get("invalidParams", ProblemDetails, undefined) of
								InvalidParams when is_list(InvalidParams) ->
									F = fun(#{"param" := PolicyCounterId2})
											when is_list(PolicyCounterId2) ->
										#diameter_avp{code = 2901,
												vendor_id = 10415,
												name = 'Policy-Counter-Identifier',
												type = 'UTF8String',
												is_mandatory = true,
												data = list_to_binary(PolicyCounterId2)}
									end,
									FailedAVP = lists:map(F, InvalidParams),
									{RC, [Title], FailedAVP};
								undefined ->
									{RC, [Title], []}
							end;
						{ok, #{"title" := Title} = _ProblemDetails} ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									[Title], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 400 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf client error"], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 401 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf client unauthorized"], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 500 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf server error"], []};
						{ok, #{} = _ProblemDetails} ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf unexpected problem response"], []};
						_ ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf decoding ProblemDetails failed"], []}
					end;
				_ when StatusCode == 400 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf client error"], []};
				_ when StatusCode == 401 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf client unauthorized"], []};
				_ when StatusCode == 500 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf server error"], []};
				_ ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf unexpected response"], []}
			end,
			diameter_error(SessionId, OHost, ORealm,
							ResultCode, ErrorMessage, Failed);
		{error, _Reason} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			ErrorMessage = ["Nchf transport error"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, [])
	catch
		throw:session ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNKNOWN_SESSION_ID',
			ErrorMessage = ["Sy Session-Id not found"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, []);
		?CATCH_STACK ->
			?SET_STACK,
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
					{origin_host, OriginHost}, {origin_realm, OriginRealm},
					{request, Request},
					{error, Reason}, {stack, StackTrace}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			ErrorMessage = ["Unspecified error"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, [])
	end;
process_request(_ServiceName,
		#diameter_caps{origin_host = {OHost, _DHost},
				origin_realm = {ORealm, _DRealm}},
		#'3gpp_sy_STR'{'Session-Id' = SessionId,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'Origin-Host' = OriginHost,
				'Origin-Realm' = OriginRealm,
				'Termination-Cause' = Cause} = Request,
		Config) when Cause == ?'DIAMETER_BASE_TERMINATION-CAUSE_LOGOUT' ->
	try
		case ets:lookup(sy_session, SessionId) of
			[{_, SUPI, Location}] ->
				ets:delete(sy_session, SessionId),
				ets:delete(nchf_session, SUPI),
				nchf_final(Location, Config);
			[] ->
				throw(session)
		end
	of
		{204 = _StatusCode, _ResponseHeaders, _ResponseBody} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			STA = #'3gpp_sy_STA'{'Session-Id' = SessionId,
					'Origin-Host' = OHost,
					'Origin-Realm' = ORealm,
					'Result-Code' = [ResultCode]},
			{reply, STA};
		{StatusCode, ResponseHeaders, ResponseBody} ->
			{ResultCode, ErrorMessage, Failed} = case lists:keyfind("content-type",
					1, ResponseHeaders) of
				{_, "application/problem+json"} ->
					case zj:decode(ResponseBody) of
						{ok, #{"title" := Title} = _ProblemDetails} ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									[Title], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 400 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf client error"], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 401 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf client unauthorized"], []};
						{ok, #{} = _ProblemDetails} when StatusCode == 500 ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf server error"], []};
						{ok, #{} = _ProblemDetails} ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf unexpected problem response"], []};
						_ ->
							{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
									["Nchf decoding ProblemDetails failed"], []}
					end;
				_ when StatusCode == 400 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf client error"], []};
				_ when StatusCode == 401 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf client unauthorized"], []};
				_ when StatusCode == 500 ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf server error"], []};
				_ ->
					{?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							["Nchf unexpected response"], []}
			end,
			diameter_error(SessionId, OHost, ORealm,
							ResultCode, ErrorMessage, Failed);
		{error, _Reason} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			ErrorMessage = ["Nchf transport error"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, [])
	catch
		throw:session ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNKNOWN_SESSION_ID',
			ErrorMessage = ["Sy Session-Id not found"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, []);
		?CATCH_STACK ->
			?SET_STACK,
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
					{origin_host, OriginHost}, {origin_realm, OriginRealm},
					{request, Request},
					{error, Reason}, {stack, StackTrace}]),
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			ErrorMessage = ["Unspecified error"],
			diameter_error(SessionId, OHost, ORealm,
					ResultCode, ErrorMessage, [])
	end.

-spec nchf_initial(Body, Config) -> Reply
	when
		Body :: iolist() | binary(),
		Config :: map(),
		Reply :: {StatusCode, ResponseHeaders, ResponseBody}
				| {error, Reason},
		StatusCode :: non_neg_integer(),
		ResponseHeaders :: [HttpHeader],
		HttpHeader :: {HeaderField, HeaderValue},
		HeaderField :: [byte()],
		HeaderValue :: binary() | iolist(),
		HttpHeader :: {Field :: [byte()], Value :: binary() | iolist()},
		ResponseBody :: string() | binary() | map(),
		Reason :: term().
%% @doc Perform an initial `Nchf_SpendingLimitControl_Subscribe' operation.
%% @private
nchf_initial(Body, Config) ->
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
	ContentType = "application/json",
	RequestURL = list_to_binary([URI, <<"/subscriptions">>]),
	Request = {RequestURL, RequestHeaders, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(post, Request, HttpOptions1, [], Profile) of
		{ok, {{_Version, 201 = StatusCode, _Phrase},
				ResponseHeaders, ResponseBody}} ->
			case lists:keymember("location", 1, ResponseHeaders) of
				true ->
					ok;
				false ->
					?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
							{error, missing_location}, {profile, Profile},
							{uri, RequestURL}, {host, Host},
							{status_code, StatusCode},
							{headers, ResponseHeaders}])
			end,
			case zj:decode(ResponseBody) of
				{ok, SpendingLimitStatus}
						when is_map(SpendingLimitStatus) ->
					{StatusCode, ResponseHeaders, SpendingLimitStatus};
				{_, Partial, Remaining} ->
					?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
							{error, bad_json}, {profile, Profile},
							{uri, RequestURL}, {host, Host},
							{status_code, StatusCode},
							{partial, Partial}, {remaining, Remaining}])
			end;
		{ok, {{_Version, StatusCode, _Phrase},
				ResponseHeaders, ResponseBody}} ->
			{StatusCode, ResponseHeaders, ResponseBody};
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewConfig = Config#{nchf_uri => hd(NextURIs),
					nchf_next_uris => tl(NextURIs)},
			?FUNCTION_NAME(Body, NewConfig);
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME}, {error, Reason},
					{profile, Profile}, {uri, RequestURL}, {host, Host}]),
			{error, Reason}
	end.

-spec nchf_intermediate(Location, Body, Config) -> Reply
	when
		Location :: binary(),
		Body :: iolist() | binary(),
		Config :: map(),
		Reply :: {StatusCode, ResponseHeaders, ResponseBody}
				| {error, Reason},
		StatusCode :: non_neg_integer(),
		ResponseHeaders :: [HttpHeader],
		HttpHeader :: {HeaderField, HeaderValue},
		HeaderField :: [byte()],
		HeaderValue :: binary() | iolist(),
		HttpHeader :: {Field :: [byte()], Value :: binary() | iolist()},
		ResponseBody :: string() | binary() | map(),
		Reason :: term().
%% @doc Perform an intermediate `Nchf_SpendingLimitControl_Subscribe' operation.
%% @private
nchf_intermediate(Location, Body, Config) ->
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
	ContentType = "application/json",
	RequestURL = uri_string:resolve(Location, URI),
	Request = {RequestURL, RequestHeaders, ContentType, Body},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(put, Request, HttpOptions1, [], Profile) of
		{ok, {{_Version, 200 = StatusCode, _Phrase},
				ResponseHeaders, ResponseBody}} ->
			case zj:decode(ResponseBody) of
				{ok, SpendingLimitStatus}
						when is_map(SpendingLimitStatus) ->
					{StatusCode, ResponseHeaders, SpendingLimitStatus};
				{_, Partial, Remaining} ->
					?LOG_ERROR([{?MODULE, ?FUNCTION_NAME},
							{error, bad_json}, {profile, Profile},
							{uri, RequestURL}, {host, Host},
							{status_code, StatusCode},
							{partial, Partial}, {remaining, Remaining}])
			end;
		{ok, {{_Version, StatusCode, _Phrase},
				ResponseHeaders, ResponseBody}} ->
			{StatusCode, ResponseHeaders, ResponseBody};
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewConfig = Config#{nchf_uri => hd(NextURIs),
					nchf_next_uris => tl(NextURIs)},
			?FUNCTION_NAME(Location, Body, NewConfig);
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME}, {error, Reason},
					{profile, Profile}, {uri, RequestURL}, {host, Host}]),
			{error, Reason}
	end.

-spec nchf_final(Location, Config) -> Reply
	when
		Location :: binary(),
		Config :: map(),
		Reply :: {StatusCode, ResponseHeaders, ResponseBody}
				| {error, Reason},
		StatusCode :: non_neg_integer(),
		ResponseHeaders :: [HttpHeader],
		HttpHeader :: {HeaderField, HeaderValue},
		HeaderField :: [byte()],
		HeaderValue :: binary() | iolist(),
		HttpHeader :: {Field :: [byte()], Value :: binary() | iolist()},
		ResponseBody :: string() | binary() | map(),
		Reason :: term().
%% @doc Perform a final `Nchf_SpendingLimitControl_Unsubscribe' operation.
%% @private
nchf_final(Location, Config) ->
	Config1 = add_nchf(Config),
	Profile = maps:get(nchf_profile, Config1, nchf),
	URI = maps:get(nchf_uri, Config1),
	NextURIs = maps:get(nchf_next_uris, Config1),
	Host = maps:get(nchf_host, Config1),
	Headers = maps:get(nchf_headers, Config1, []),
	HttpOptions = maps:get(nchf_http_options, Config,
			[{timeout, 1500}, {connect_timeout, 1500}]),
	RequestHeaders = [{"host", Host},
			{"accept", "application/problem+json"}
			| Headers],
	ContentType = [],
	RequestURL = uri_string:resolve(Location, URI),
	Request = {RequestURL, RequestHeaders, ContentType, []},
	HttpOptions1 = [{relaxed, true} | HttpOptions],
	case httpc:request(delete, Request, HttpOptions1, [], Profile) of
		{ok, {{_Version, StatusCode, _Phrase},
				ResponseHeaders, ResponseBody}} ->
			{StatusCode, ResponseHeaders, ResponseBody};
		{error, {failed_connect, _} = _Reason}
				when length(NextURIs) > 0 ->
			NewConfig = Config#{nchf_uri => hd(NextURIs),
					nchf_next_uris => tl(NextURIs)},
			?FUNCTION_NAME(Location, NewConfig);
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, ?FUNCTION_NAME}, {error, Reason},
					{profile, Profile}, {uri, RequestURL}, {host, Host}]),
			{error, Reason}
	end.

-spec diameter_error(SessionId, OriginHost, OriginRealm,
			ResultCode, ErrorMessage, Failed) -> Reply
	when
		SessionId :: binary(),
		OriginHost :: string(),
		OriginRealm :: string(),
		ResultCode :: pos_integer(),
		ErrorMessage :: [string() | binary()],
		Failed :: [#diameter_avp{}],
		Reply :: {reply, #'3gpp_sy_SLA'{}}.
%% @doc Send SLA to DIAMETER client indicating an operation failure.
%% @hidden
diameter_error(SessionId, OriginHost, OriginRealm,
		ResultCode, ErrorMessage, Failed)
		when ResultCode ==
		?'3GPP_SY_EXPERIMENTAL-RESULT-CODE_NO_AVAILABLE_POLICY_COUNTERS';
		ResultCode ==
		?'3GPP_SY_EXPERIMENTAL-RESULT-CODE_UNKNOWN_POLICY_COUNTERS' ->
	ExperimentalResult = #'3gpp_sy_Experimental-Result'{
			'Vendor-Id' = 10415,
			'Experimental-Result-Code' = ResultCode},
	SLA = #'3gpp_sy_SLA'{'Session-Id' = SessionId,
			'Auth-Application-Id' = ?SY_APPLICATION_ID,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Experimental-Result' = [ExperimentalResult],
			'Error-Message' = ErrorMessage,
			'Failed-AVP' = Failed},
	{reply, SLA};
diameter_error(SessionId, OriginHost, OriginRealm,
		ResultCode, ErrorMessage, Failed) ->
	SLA = #'3gpp_sy_SLA'{'Session-Id' = SessionId,
			'Auth-Application-Id' = ?SY_APPLICATION_ID,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Result-Code' = [ResultCode],
			'Error-Message' = ErrorMessage,
			'Failed-AVP' = Failed},
	{reply, SLA}.

%% @hidden
supi([#'3gpp_sy_Subscription-Id'{'Subscription-Id-Data' = IMSI,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI'} | _],
		SLC) ->
	SUPI = <<"imsi-", IMSI/binary>>,
	SLC#{supi => SUPI};
supi([#'3gpp_sy_Subscription-Id'{'Subscription-Id-Data' = NAI,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_NAI'} | _],
		SLC) ->
	SUPI = <<"nai-", NAI/binary>>,
	SLC#{supi => SUPI};
supi([_H | T], SLC) ->
	supi(T, SLC);
supi([], _SLC) ->
	throw(supi).

%% @hidden
gpsi([#'3gpp_sy_Subscription-Id'{'Subscription-Id-Data' = MSISDN,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164'} | _],
		SLC) ->
	GPSI = <<"msisdn-", MSISDN/binary>>,
	SLC#{gpsi => GPSI};
gpsi([#'3gpp_sy_Subscription-Id'{'Subscription-Id-Data' = URI,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_SIP_URI'} | _],
		SLC) ->
	GPSI = <<"extid-", URI/binary>>,
	SLC#{gpsi => GPSI};
gpsi([#'3gpp_sy_Subscription-Id'{'Subscription-Id-Data' = PRIVATE,
		'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_PRIVATE'} | _],
		SLC) ->
	GPSI = <<"extid-", PRIVATE/binary>>,
	SLC#{gpsi => GPSI};
gpsi([_H | T], SLC) ->
	gpsi(T, SLC);
gpsi([], SLC) ->
	SLC.

%% @hidden
pcid(PolicyCounterId, SLC)
		when length(PolicyCounterId) > 0 ->
	SLC#{policyCounterIds => PolicyCounterId};
pcid([], SLC) ->
	SLC.

%% @hidden
notify(#{notify_uri := URI} = _Config, SLC) ->
	SLC#{notifUri => URI}.

%% @hidden
add_nchf(#{nchf_uri := URI} = Config) ->
	add_nchf(URI, Config, uri_string:parse(URI));
add_nchf(Config) ->
	URI = "http://chf.5gc.mnc001.mcc001.3gppnetwork.org"
			"/nchf-spendinglimitcontrol/v1",
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

