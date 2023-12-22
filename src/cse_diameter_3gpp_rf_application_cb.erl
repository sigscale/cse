%%% cse_diameter_3gpp_rf_application_cb.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2023 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_server. gen_server} behaviour callback
%%% 	module receives {@link //diameter. diameter} messages on a port assigned
%%% 	for the 3GPP DIAMETER Rf in the {@link //cse. cse} application.
%%%
%%% @reference 3GPP TS 29.299 Diameter charging applications
%%% @reference <a href="https://datatracker.ietf.org/doc/html/rfc6733">
%%% 	RFC6733 - DIAMETER Base Protocol</a>
%%%
-module(cse_diameter_3gpp_rf_application_cb).
-copyright('Copyright (c) 2016 - 2023 SigScale Global Inc.').

-export([peer_up/3, peer_down/3, pick_peer/4, prepare_request/3,
			prepare_retransmit/3, handle_answer/4, handle_error/4,
			handle_request/3]).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_rf_application.hrl").
-include("cse.hrl").

-record(state, {}).

-define(LOGNAME, '3gpp_rf').
-define(RF_APPLICATION_ID, 3).

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

-spec peer_up(ServiceName, Peer, State) -> NewState
	when
		ServiceName :: diameter:service_name(),
		Peer ::  peer(),
		State :: state(),
		NewState :: state().
%% @doc Invoked when the peer connection is available
peer_up(_ServiceName, _Peer, State) ->
    State.

-spec peer_down(ServiceName, Peer, State) -> NewState
	when
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		State :: state(),
		NewState :: state().
%% @doc Invoked when the peer connection is not available
peer_down(_ServiceName, _Peer, State) ->
    State.

-spec pick_peer(LocalCandidates, RemoteCandidates, ServiceName, State) -> Result
	when
		LocalCandidates :: [peer()],
		RemoteCandidates :: [peer()],
		ServiceName :: diameter:service_name(),
		State :: state(),
		NewState :: state(),
		Selection :: {ok, Peer} | {Peer, NewState},
		Peer :: peer() | false,
		Result :: Selection | false.
%% @doc Invoked as a consequence of a call to diameter:call/4 to select
%% a destination peer for an outgoing request.
pick_peer([Peer | _] = _LocalCandidates, _RemoteCandidates, _ServiceName, _State) ->
	{ok, Peer}.

-spec prepare_request(Packet, ServiceName, Peer) -> Action
	when
		Packet :: packet(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Action :: Send | Discard | {eval_packet, Action, PostF},
		Send :: {send, packet() | message()},
		Discard :: {discard, Reason} | discard,
		Reason :: term(),
		PostF :: diameter:evaluable().
%% @doc Invoked to return a request for encoding and transport
prepare_request(#diameter_packet{} = Packet, _ServiceName, _Peer) ->
	{send, Packet}.

-spec prepare_retransmit(Packet, ServiceName, Peer) -> Action
	when
		Packet :: packet(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Action :: Send | Discard | {eval_packet, Action, PostF},
		Send :: {send, packet() | message()},
		Discard :: {discard, Reason} | discard,
		Reason :: term(),
		PostF :: diameter:evaluable().
%% @doc Invoked to return a request for encoding and retransmission.
%% In case of peer connection is lost alternate peer is selected.
prepare_retransmit(Packet, ServiceName, Peer) ->
	prepare_request(Packet, ServiceName, Peer).

-spec handle_answer(Packet, Request, ServiceName, Peer) -> Result
	when
		Packet :: packet(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Result :: term().
%% @doc Invoked when an answer message is received from a peer.
handle_answer(_Packet, _Request, _ServiceName, _Peer) ->
    not_implemented.

-spec handle_error(Reason, Request, ServiceName, Peer) -> Result
	when
		Reason :: timeout | failover | term(),
		Request :: message(),
		ServiceName :: diameter:service_name(),
		Peer :: peer(),
		Result :: term().
%% @doc Invoked when an error occurs before an answer message is received
%% in response to an outgoing request.
handle_error(_Reason, _Request, _ServiceName, _Peer) ->
	not_implemented.

-spec handle_request(Packet, ServiceName, Peer) -> Action
	when
		Packet :: packet(),
		ServiceName :: term(),
		Peer :: peer(),
		Action :: Reply | {relay, [Opt]} | discard
			| {eval | eval_packet, Action, PostF},
		Reply :: {reply, packet() | message()}
			| {answer_message, 3000..3999|5000..5999}
			| {protocol_error, 3000..3999},
		Opt :: diameter:call_opt(),
		PostF :: diameter:evaluable().
%% @doc Invoked when a request message is received from the peer.
handle_request(#diameter_packet{errors = [], msg = Request} = _Packet,
		{_, IpAddress, Port} = ServiceName, {_, Capabilities} = Peer) ->
	Start = erlang:system_time(millisecond),
	Reply = process_request(IpAddress, Port, Capabilities, Request),
	Stop = erlang:system_time(millisecond),
	cse_log:blog(?LOGNAME, {Start, Stop, ServiceName, Peer, Request, Reply}),
	Reply;
handle_request(#diameter_packet{errors = Errors, msg = Request} = _Packet,
		ServiceName, {_, Capabilities} = Peer) ->
	Start = erlang:system_time(millisecond),
	Reply = errors(ServiceName, Capabilities, Request, Errors),
	Stop = erlang:system_time(millisecond),
	cse_log:blog(?LOGNAME, {Start, Stop, ServiceName, Peer, Request, Reply}),
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

-spec process_request(IpAddress, Port, Caps, Request) -> Result
	when
		IpAddress :: inet:ip_address(),
		Port :: inet:port_number(),
		Request :: #'3gpp_rf_ACR'{},
		Caps :: capabilities(),
		Result :: {reply, message()} | {answer_message, 5000..5999}.
%% @doc Process a received DIAMETER packet.
%% @private
process_request(_IpAddress, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = [ContextId],
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum} = Request)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD' ->
	try
		Children = supervisor:which_children(cse_sup),
		{_, SlpSup, _, _} = lists:keyfind(cse_slp_sup, 1, Children),
		#diameter_context{module = Module, args = Args,
				opts = Opts} = cse:get_context(ContextId),
		supervisor:start_child(SlpSup, [Module, Args, Opts])
	of
		{ok, Child} ->
			case catch gen_statem:call(Child, Request) of
				{'EXIT', Reason} ->
					error_logger:error_report(["Diameter Error",
							{module, ?MODULE}, {fsm, Child},
							{type, event_type(RecordType)}, {error, Reason}]),
					diameter_error(SessionId,
							?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							OHost, ORealm, RecordType, RecordNum);
				#'3gpp_rf_ACA'{} = ACA ->
					cse:add_session(SessionId, Child),
					Reply = ACA#'3gpp_rf_ACA'{'Session-Id' = SessionId,
							'Origin-Host' = OHost, 'Origin-Realm' = ORealm},
					{reply, Reply}
			end;
		{error, Reason} ->
			error_logger:error_report(["Diameter Error",
					{module, ?MODULE}, {error, Reason},
					{origin_host, OHost}, {origin_realm, ORealm},
					{type, event_type(RecordType)}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	catch
		?CATCH_STACK ->
			?SET_STACK,
			error_logger:warning_report(["Unable to process DIAMETER request",
						{origin_host, OHost}, {origin_realm, ORealm},
						{request, Request}, {error, Reason}, {stack, StackTrace}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	end;
process_request(_IpAddress, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum} = Request)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD' ->
	try
		case cse:find_session(SessionId) of
			{ok, Pid} ->
				case catch gen_statem:call(Pid, Request) of
					{'EXIT', Reason1} ->
						error_logger:error_report(["Diameter Error",
								{module, ?MODULE}, {session, SessionId},
								{fsm, Pid}, {type, event_type(RecordType)},
								{error, Reason1}]),
						diameter_error(SessionId,
								?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
								OHost, ORealm, RecordType, RecordNum);
					#'3gpp_rf_ACA'{} = ACA ->
						Reply = ACA#'3gpp_rf_ACA'{'Session-Id' = SessionId,
								'Origin-Host' = OHost, 'Origin-Realm' = ORealm},
						{reply, Reply}
				end;
			{error, Reason1} ->
				error_logger:error_report(["Diameter Error",
						{module, ?MODULE}, {error, Reason1},
						{origin_host, OHost}, {origin_realm, ORealm},
						{type, event_type(RecordType)}]),
				diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
						OHost, ORealm, RecordType, RecordNum)
		end
	catch
		?CATCH_STACK ->
			?SET_STACK,
			error_logger:warning_report(["Unable to process DIAMETER request",
						{origin_host, OHost}, {origin_realm, ORealm},
						{request, Request}, {error, Reason}, {stack, StackTrace}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	end;
process_request(_IpAddress, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum} = Request)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' ->
	try
		cse:find_session(SessionId)
	of
		{ok, Pid} ->
			case catch gen_statem:call(Pid, Request) of
				{'EXIT', Reason1} ->
					error_logger:error_report(["Diameter Error",
							{module, ?MODULE}, {session, SessionId},
							{fsm, Pid}, {type, event_type(RecordType)},
							{error, Reason1}]),
					cse:delete_session(SessionId),
					diameter_error(SessionId,
							?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							OHost, ORealm, RecordType, RecordNum);
				#'3gpp_rf_ACA'{} = ACA ->
					cse:delete_session(SessionId),
					Reply = ACA#'3gpp_rf_ACA'{'Session-Id' = SessionId,
							'Origin-Host' = OHost, 'Origin-Realm' = ORealm},
					{reply, Reply}
			end;
		{error, Reason} ->
			error_logger:error_report(["Diameter Error",
					{module, ?MODULE}, {error, Reason},
					{origin_host, OHost}, {origin_realm, ORealm},
					{type, event_type(RecordType)}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	catch
		?CATCH_STACK ->
			?SET_STACK,
			error_logger:warning_report(["Unable to process DIAMETER request",
						{origin_host, OHost}, {origin_realm, ORealm},
						{request, Request}, {error, Reason}, {stack, StackTrace}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	end;
process_request(_IpAddress, _Port,
		#diameter_caps{origin_host = {OHost, _DHost}, origin_realm = {ORealm, _DRealm}},
		#'3gpp_rf_ACR'{'Session-Id' = SessionId,
				'Service-Context-Id' = [ContextId],
				'Accounting-Record-Type' = RecordType,
				'Accounting-Record-Number' = RecordNum} = Request)
		when RecordType == ?'3GPP_RF_ACCOUNTING-RECORD-TYPE_EVENT_RECORD' ->
	try
		Children = supervisor:which_children(cse_sup),
		{_, SlpSup, _, _} = lists:keyfind(cse_slp_sup, 1, Children),
		#diameter_context{module = Module, args = Args,
				opts = Opts} = cse:get_context(ContextId),
		supervisor:start_child(SlpSup, [Module, Args, Opts])
	of
		{ok, Child} ->
			case catch gen_statem:call(Child, Request) of
				{'EXIT', Reason} ->
					error_logger:error_report(["Diameter Error",
							{module, ?MODULE}, {fsm, Child},
							{type, event_type(RecordType)}, {error, Reason}]),
					diameter_error(SessionId,
							?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
							OHost, ORealm, RecordType, RecordNum);
				#'3gpp_rf_ACA'{} = ACA ->
					Reply = ACA#'3gpp_rf_ACA'{'Session-Id' = SessionId,
							'Origin-Host' = OHost, 'Origin-Realm' = ORealm},
					{reply, Reply}
			end;
		{error, Reason} ->
			error_logger:error_report(["Diameter Error",
					{module, ?MODULE}, {error, Reason},
					{origin_host, OHost}, {origin_realm, ORealm},
					{type, event_type(RecordType)}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	catch
		?CATCH_STACK ->
			?SET_STACK,
			error_logger:warning_report(["Unable to process DIAMETER request",
						{origin_host, OHost}, {origin_realm, ORealm},
						{request, Request}, {error, Reason}, {stack, StackTrace}]),
			diameter_error(SessionId, ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					OHost, ORealm, RecordType, RecordNum)
	end.

-spec diameter_error(SessionId, ResultCode, OriginHost,
		OriginRealm, RecordType, RecordNum) -> Reply
	when
		SessionId :: binary(),
		ResultCode :: pos_integer(),
		OriginHost :: string(),
		OriginRealm :: string(),
		RecordType :: integer(),
		RecordNum :: integer(),
		Reply :: {reply, #'3gpp_rf_ACA'{}}.
%% @doc Send ACA to DIAMETER client indicating an operation failure.
%% @hidden
diameter_error(SessionId, ResultCode, OHost, ORealm, RecordType, RecordNum) ->
	{reply, #'3gpp_rf_ACA'{'Session-Id' = SessionId, 'Result-Code' = ResultCode,
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Acct-Application-Id' = ?RF_APPLICATION_ID,
			'Accounting-Record-Type' = RecordType,
			'Accounting-Record-Number' = RecordNum}}.

-spec event_type(RecordType) -> EventType
	when
	RecordType :: 1..4,
	EventType :: start | interim | stop.
%% @doc Converts CC-Request-Type integer value to a readable atom.
event_type(?'3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD') -> start;
event_type(?'3GPP_RF_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD') -> interim;
event_type(?'3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD') -> stop;
event_type(?'3GPP_RF_ACCOUNTING-RECORD-TYPE_EVENT_RECORD') -> event.

