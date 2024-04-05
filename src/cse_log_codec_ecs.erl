%%% cse_log_codec_ecs.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2023 SigScale Global Inc.
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
%%% @doc This library module implements CODEC functions for logging
%%% 	with Elastic Common Schema (ECS) data model
%%% 	in the {@link //cse. cse} application.
%%%
-module(cse_log_codec_ecs).
-copyright('Copyright (c) 2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse_log_codec_ecs  public API
-export([codec_diameter_ecs/1, codec_prepaid_ecs/1, codec_postpaid_ecs/1,
		codec_rating_ecs/1]).
-export([ecs_base/1, ecs_server/4, ecs_client/4, ecs_network/2,
		ecs_source/5, ecs_destination/1, ecs_service/2, ecs_event/7,
		ecs_url/1]).
-export([subscriber_id/1]).

-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_3gpp_rf_application.hrl").
-include_lib("diameter/include/diameter.hrl").

%%----------------------------------------------------------------------
%%  The cse_log_codec_ecs public API
%%----------------------------------------------------------------------

-spec codec_diameter_ecs(Term) -> iodata()
	when
		Term :: {Start, Stop, ServiceName, Peer, Request, Reply},
		Start :: pos_integer(),
		Stop :: pos_integer(),
		ServiceName :: {cse, Address, Port},
		Address :: inet:ip_address(),
		Port :: non_neg_integer(),
		Peer :: diameter_app:peer(),
		Request :: diameter:message(),
		Reply :: {reply,  diameter:message()}
				| {answer_message, 3000..3999 | 5000..5999}.
%% @doc DIAMETER event CODEC for Elastic Stack logs.
%%
%% 	Formats DIAMETER message transaction events for consumption by
%% 	Elastic Stack by providing a JSON format aligned with The Elastic
%% 	Common Schema (ECS).
%%
%% 	Callback handlers for the {@link //diameter. diameter} application
%% 	may use this CODEC function with the {@link //cse/cse_log. cse_log}
%% 	logging functions with the
%% 	{@link //cse/cse_log:log_option(). cse_log:log_option()}
%% 	`{codec, {{@module}, codec_diameter_ecs}}'.
%%
%% 	The `StartTime' should be when the DIAMETER request was received
%% 	and `StopTime' when the response was sent. The values are
%% 	milliseconds since the epoch (e.g. `erlang:system_time(millisecond)').
%% 	A duration will be calculated and `event.start', `event.stop' and
%% 	`event.duration' will be included in the log event.
%%
codec_diameter_ecs({Start, Stop,
		{_, Address, Port} = _ServiceName,
		{_PeerRef, Capabilities} = _Peer,
		Request, Reply} = _Term) ->
	StartTime = cse_log:iso8601(Start),
	StopTime = cse_log:iso8601(Stop),
	Duration = integer_to_list((Stop - Start) * 1000000),
	{ServerAddress, ClientAddress} = Capabilities#diameter_caps.origin_host,
	{ServerDomain, ClientDomain} = Capabilities#diameter_caps.origin_realm,
	Acc = [${,
			ecs_base(cse_log:iso8601(erlang:system_time(millisecond))),
			ecs_server(ServerAddress, ServerDomain, Address, Port),
			ecs_client(ClientAddress, ClientDomain, [], 0)],
	codec_diameter_ecs1(Request, Reply, StartTime, StopTime, Duration, Acc).
%% @hidden
%% @todo TCP/SCTP transport attributes.
codec_diameter_ecs1(#'3gpp_ro_CCR'{} = Request,
		Reply, Start, Stop, Duration, Acc) ->
	NewAcc = [Acc, $,,
			ecs_network("ro", "diameter")],
	codec_diameter_ecs2(Request, Reply, Start, Stop, Duration, NewAcc);
codec_diameter_ecs1(#'3gpp_rf_ACR'{} = Request,
		Reply, Start, Stop, Duration, Acc) ->
	NewAcc = [Acc, $,,
			ecs_network("rf", "diameter")],
	codec_diameter_ecs2(Request, Reply, Start, Stop, Duration, NewAcc).
%% @hidden
codec_diameter_ecs2(#'3gpp_ro_CCR'{
		'CC-Request-Type' = RequestType,
		'Origin-Host' = OriginHost,
		'Origin-Realm' = OriginRealm,
		'Destination-Realm' = DestinationRealm,
		'User-Name' = UserName,
		'Subscription-Id' = SubscriptionId} = Request,
		Reply, Start, Stop, Duration, Acc) ->
	EventType = case RequestType of
		?'3GPP_RO_CC-REQUEST-TYPE_INITIAL_REQUEST' ->
			["protocol", "start"];
		?'3GPP_RO_CC-REQUEST-TYPE_UPDATE_REQUEST' ->
			["protocol"];
		?'3GPP_RO_CC-REQUEST-TYPE_TERMINATION_REQUEST' ->
			["protocol", "end"];
		?'3GPP_RO_CC-REQUEST-TYPE_EVENT_REQUEST' ->
			["protocol"]
	end,
	UserIds = subscriber_id(SubscriptionId),
	NewAcc = [Acc, $,,
			ecs_service("sigscale-cse", "ocf"), $,,
			ecs_source(OriginHost, OriginHost, OriginRealm,
					UserName, UserIds), $,,
			ecs_destination(DestinationRealm)],
	codec_diameter_ecs3(Request, Reply, EventType, Start, Stop, Duration, NewAcc);
codec_diameter_ecs2(#'3gpp_rf_ACR'{
		'Accounting-Record-Type' = RecordType,
		'Origin-Host' = OriginHost,
		'Origin-Realm' = OriginRealm,
		'Destination-Realm' = DestinationRealm,
		'User-Name' = UserName,
		'Subscription-Id' = SubscriptionId} = Request,
		Reply, Start, Stop, Duration, Acc) ->
	EventType = case RecordType of
		?'3GPP_RF_ACCOUNTING-RECORD-TYPE_START_RECORD' ->
			["protocol", "start"];
		?'3GPP_RF_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD' ->
			["protocol"];
		?'3GPP_RF_ACCOUNTING-RECORD-TYPE_STOP_RECORD' ->
			["protocol", "end"];
		?'3GPP_RF_ACCOUNTING-RECORD-TYPE_EVENT_RECORD' ->
			["protocol"]
	end,
	UserIds = subscriber_id(SubscriptionId),
	NewAcc = [Acc, $,,
			ecs_service("sigscale-cse", "ocf"), $,,
			ecs_source(OriginHost, OriginHost, OriginRealm,
					UserName, UserIds), $,,
			ecs_destination(DestinationRealm)],
	codec_diameter_ecs3(Request, Reply, EventType, Start, Stop, Duration, NewAcc).
%% @hidden
codec_diameter_ecs3(#'3gpp_ro_CCR'{} = CCR,
		{reply, #'3gpp_ro_CCA'{'Result-Code' = ResultCode} = CCA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 1000, ResultCode < 2000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", EventType, "unknown"), $,,
			ecs_3gpp_ro(CCR, CCA), $}];
codec_diameter_ecs3(#'3gpp_ro_CCR'{} = CCR,
		{reply, #'3gpp_ro_CCA'{'Result-Code' = ResultCode} = CCA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 2000, ResultCode  < 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["allowed" | EventType], "success"), $,,
			ecs_3gpp_ro(CCR, CCA), $}];
codec_diameter_ecs3(#'3gpp_ro_CCR'{} = CCR,
		{reply, #'3gpp_ro_CCA'{'Result-Code' = ResultCode} = CCA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["denied" | EventType], "failure"), $,,
			ecs_3gpp_ro(CCR, CCA), $}];
codec_diameter_ecs3(#'3gpp_ro_CCR'{} = CCR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 1000, ResultCode < 2000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", EventType, "unknown"), $,,
			ecs_3gpp_ro(CCR, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(#'3gpp_ro_CCR'{} = CCR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 2000, ResultCode  < 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["allowed" | EventType], "success"), $,,
			ecs_3gpp_ro(CCR, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(#'3gpp_ro_CCR'{} = CCR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["denied" | EventType], "failure"), $,,
			ecs_3gpp_ro(CCR, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(#'3gpp_rf_ACR'{} = ACR,
		{reply, #'3gpp_rf_ACA'{'Result-Code' = ResultCode} = ACA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 1000, ResultCode < 2000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", EventType, "unknown"), $,,
			ecs_3gpp_rf(ACR, ACA), $}];
codec_diameter_ecs3(#'3gpp_rf_ACR'{} = ACR,
		{reply, #'3gpp_rf_ACA'{'Result-Code' = ResultCode} = ACA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 2000, ResultCode  < 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["allowed" | EventType], "success"), $,,
			ecs_3gpp_rf(ACR, ACA), $}];
codec_diameter_ecs3(#'3gpp_rf_ACR'{} = ACR,
		{reply, #'3gpp_rf_ACA'{'Result-Code' = ResultCode} = ACA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["denied" | EventType], "failure"), $,,
			ecs_3gpp_rf(ACR, ACA), $}];
codec_diameter_ecs3(#'3gpp_rf_ACR'{} = ACR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 1000, ResultCode < 2000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", EventType, "unknown"), $,,
			ecs_3gpp_rf(ACR, #'3gpp_rf_ACA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(#'3gpp_rf_ACR'{} = ACR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 2000, ResultCode  < 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["allowed" | EventType], "success"), $,,
			ecs_3gpp_rf(ACR, #'3gpp_rf_ACA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(#'3gpp_rf_ACR'{} = ACR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["denied" | EventType], "failure"), $,,
			ecs_3gpp_rf(ACR, #'3gpp_rf_ACA'{'Result-Code' = ResultCode}), $}].

-spec codec_prepaid_ecs(Term) -> iodata()
	when
		Term :: {Start, Stop, ServiceName,
				State, Subscriber, Call, Network, OCS},
		Start :: pos_integer(),
		Stop :: pos_integer(),
		ServiceName :: string(),
		State :: exception | atom(),
		Subscriber :: #{imsi := IMSI, msisdn := MSISDN},
		IMSI :: [$0..$9],
		MSISDN :: [$0..$9],
		Call :: #{direction := Direction, calling := Calling, called := Called}
				| #{recipient := Recipient, originator := Originator},
		Direction :: originating | terminating,
		Calling :: [$0..$9],
		Called :: [$0..$9],
		Recipient :: string(),
		Originator :: string(),
		Network :: #{context => Context, session_id => SessionId,
				hplmn => PLMN, vplmn => PLMN},
		Context :: string(),
		SessionId :: binary(),
		PLMN :: string(),
		OCS :: #{nrf_uri => NrfURL, nrf_location => NrfLocation,
				nrf_result => NrfResult, nrf_cause => NrfCause},
		NrfURL :: string(),
		NrfLocation :: string(),
		NrfResult :: string(),
		NrfCause :: string().
%% @doc Prepaid SLP event CODEC for Elastic Stack logs.
%%
%% 	Formats call detail events for consumption by
%% 	Elastic Stack by providing a JSON format aligned with The Elastic
%% 	Common Schema (ECS).
%%
%% 	Service Logic Processing Programs (SLP) may use this CODEC function
%% 	with the {@link //cse/cse_log. cse_log} logging functions and the
%% 	{@link //cse/cse_log:log_option(). cse_log:log_option()}
%% 	`{codec, {{@module}, codec_prepaid_ecs}}'.
%%
%% 	The `StartTime' should be when the call began and `StopTime' when
%% 	the call ended. The values are milliseconds since the epoch
%% 	(e.g. `erlang:system_time(millisecond)'). A duration will be
%% 	calculated and `event.start', `event.stop' and `event.duration'
%% 	will be included in the log event.
%%
%% @todo Refactor `outcome' after eliminating `exception' state.
codec_prepaid_ecs({Start, Stop, ServiceName,
		State, Subscriber, Call, Network, OCS} = _Term) ->
	StartTime = cse_log:iso8601(Start),
	StopTime = cse_log:iso8601(Stop),
	Duration = integer_to_list((Stop - Start) * 1000000),
	Outcome = case State of
		exception ->
			"failure";
		_ ->
			"success"
	end,
	URL = case maps:get(nrf_location, OCS, []) of
			[] ->
				maps:get(nrf_uri, OCS, []);
			Location ->
				Location
	end,
	[${,
			ecs_base(cse_log:iso8601(erlang:system_time(millisecond))), $,,
			ecs_service(ServiceName, "slp"), $,,
			ecs_network("nrf", "http"), $,,
			ecs_user(msisdn(Subscriber), imsi(Subscriber), []), $,,
			ecs_event(StartTime, StopTime, Duration,
					"event", "session", ["protocol", "end"], Outcome), $,,
			ecs_url(URL), $,,
			ecs_prepaid(State, Call, Network, OCS), $}].

-spec codec_postpaid_ecs(Term) -> iodata()
	when
		Term :: {Start, Stop, ServiceName,
				State, Subscriber, Call, Network},
		Start :: pos_integer(),
		Stop :: pos_integer(),
		ServiceName :: string(),
		State :: exception | atom(),
		Subscriber :: #{imsi := IMSI, msisdn := MSISDN},
		IMSI :: [$0..$9],
		MSISDN :: [$0..$9],
		Call :: #{direction := Direction, calling := Calling, called := Called}
				| #{recipient := Recipient, originator := Originator},
		Direction :: originating | terminating,
		Calling :: [$0..$9],
		Called :: [$0..$9],
		Recipient :: string(),
		Originator :: string(),
		Network :: #{context => Context, session_id => SessionId,
				hplmn => PLMN, vplmn => PLMN},
		Context :: string(),
		SessionId :: binary(),
		PLMN :: string().
%% @doc Postpaid SLP event CODEC for Elastic Stack logs.
%%
%% 	Formats call detail events for consumption by
%% 	Elastic Stack by providing a JSON format aligned with The Elastic
%% 	Common Schema (ECS).
%%
%% 	Service Logic Processing Programs (SLP) may use this CODEC function
%% 	with the {@link //cse/cse_log. cse_log} logging functions and the
%% 	{@link //cse/cse_log:log_option(). cse_log:log_option()}
%% 	`{codec, {{@module}, codec_prepaid_ecs}}'.
%%
%% 	The `StartTime' should be when the call began and `StopTime' when
%% 	the call ended. The values are milliseconds since the epoch
%% 	(e.g. `erlang:system_time(millisecond)'). A duration will be
%% 	calculated and `event.start', `event.stop' and `event.duration'
%% 	will be included in the log event.
%%
%% @todo Refactor `outcome' after eliminating `exception' state.
codec_postpaid_ecs({Start, Stop, ServiceName,
		State, Subscriber, Call, Network} = _Term) ->
	StartTime = cse_log:iso8601(Start),
	StopTime = cse_log:iso8601(Stop),
	Duration = integer_to_list((Stop - Start) * 1000000),
	Outcome = case State of
		exception ->
			"failure";
		_ ->
			"success"
	end,
	[${,
			ecs_base(cse_log:iso8601(erlang:system_time(millisecond))), $,,
			ecs_service(ServiceName, "slp"), $,,
			ecs_user(msisdn(Subscriber), imsi(Subscriber), []), $,,
			ecs_event(StartTime, StopTime, Duration,
					"event", "session", ["protocol", "end"], Outcome), $,,
			ecs_postpaid(State, Call, Network), $}].

-spec codec_rating_ecs(Term) -> iodata()
	when
		Term :: {Start, Stop, ServiceName, Subscriber, Client, URL, HTTP},
		Start :: pos_integer(),
		Stop :: pos_integer(),
		ServiceName :: string(),
		Subscriber :: #{imsi := IMSI, msisdn := MSISDN},
		IMSI :: [$0..$9],
		MSISDN :: [$0..$9],
		Client :: {Address, Port},
		Address :: inet:ip_address() | string(),
		Port :: non_neg_integer(),
		URL :: uri_string:uri_string() | uri_string:uri_map(),
		HTTP :: map().
%% @doc Nrf_Rating event CODEC for Elastic Stack logs.
%%
%% 	Formats Nrf_Rating message transaction events on the Re interface
%% 	for consumption by Elastic Stack by providing a JSON format aligned
%% 	with The Elastic Common Schema (ECS).
%%
%% 	Callback handlers for the {@link //httpc. httpc} application
%% 	may use this CODEC function with the {@link //cse/cse_log. cse_log}
%% 	logging functions with the
%% 	{@link //cse/cse_log:log_option(). cse_log:log_option()}
%% 	`{codec, {{@module}, codec_rating_ecs}}'.
%%
%% 	The `StartTime' should be when the Nrf_Rating request was sent
%% 	and `StopTime' when the response was received. The values are
%% 	milliseconds since the epoch (e.g. `erlang:system_time(millisecond)').
%% 	A duration will be calculated and `event.start', `event.stop' and
%% 	`event.duration' will be included in the log event.
%%
codec_rating_ecs({Start, Stop, ServiceName, Subscriber,
		{Address, Port} = _Client, URL,
		#{"response" := #{"status_code" := StatusCode}} = HTTP} = _Term) ->
	StartTime = cse_log:iso8601(Start),
	StopTime = cse_log:iso8601(Stop),
	Duration = integer_to_list((Stop - Start) * 1000000),
	Outcome = case ((StatusCode >= 200) and (StatusCode =< 299)) of
		true ->
			"success";
		false ->
			"failure"
	end,
	[${,
			ecs_base(cse_log:iso8601(erlang:system_time(millisecond))), $,,
			ecs_service(ServiceName, "slp"), $,,
			ecs_network("nrf", "http"), $,,
			ecs_user(msisdn(Subscriber), imsi(Subscriber), []), $,,
			ecs_event(StartTime, StopTime, Duration,
					"event", "session", ["protocol"], Outcome),
			ecs_client([], [], Address, Port), $,,
			ecs_url(URL), $,,
			$", "http", $", $:, zj:encode(HTTP), $}].

-spec ecs_base(Timestamp) -> iodata()
	when
		Timestamp :: string().
%% @doc Elastic Common Schema (ECS): Base attributes.
%%
%% 	`Timestamp' is milliseconds since the epoch
%% 	(e.g. `erlang:system_time(millisecond)')..
%%
ecs_base(Timestamp) ->
	TS = [$", "@timestamp", $", $:, $", Timestamp, $"],
	Labels = [$", "labels", $", $:, ${,
			$", "application", $", $:, $", "sigscale-cse", $", $}],
	Tags = [$", "tags", $", $:, $[, $]],
	Version = [$", "ecs", $", $:, ${,
			$", "version", $", $:, $", "8.5", $", $}],
	[TS, $,, Labels, $,, Tags, $,, Version].

-spec ecs_server(Address, Domain, IP, Port) -> iodata()
	when
		Address :: binary() | string(),
		Domain :: binary() | string(),
		IP :: inet:ip_address() | string(),
		Port :: non_neg_integer() | string().
%% @doc Elastic Common Schema (ECS): Server attributes.
ecs_server(Address, Domain, IP, Port) when is_tuple(IP) ->
	ecs_server(Address, Domain, inet:ntoa(IP), Port);
ecs_server(Address, Domain, IP, Port) when is_integer(Port) ->
	ecs_server(Address, Domain, IP, integer_to_list(Port));
ecs_server(Address, Domain, IP, Port)
		when ((length(Address) > 0) or (size(Address) > 0)) ->
	Acc = [$", "address", $", $:, $", Address, $"],
	ecs_server1(Domain, IP, Port, Acc);
ecs_server(_Address, Domain, IP, Port)
		when ((length(Domain) > 0) or (size(Domain) > 0)) ->
	Acc = [$", "address", $", $:, $", Domain, $"],
	ecs_server1(Domain, IP, Port, Acc);
ecs_server(_Address, Domain, IP, Port) when length(IP) > 0 ->
	Acc = [$", "address", $", $:, $", IP, $"],
	ecs_server1(Domain, IP, Port, Acc);
ecs_server(_Address, _Domain, _IP, Port) ->
	ecs_server3(Port, []).
%% @hidden
ecs_server1(Domain, IP, Port, Acc)
		when ((length(Domain) > 0) or (size(Domain) > 0)) ->
	NewAcc = [Acc, $,, $", "domain", $", $:, $", Domain, $"],
	ecs_server2(IP, Port, NewAcc);
ecs_server1(_Domain, IP, Port, Acc) ->
	ecs_server2(IP, Port, Acc).
%% @hidden
ecs_server2(IP, Port, Acc) when length(IP) > 0 ->
	NewAcc = [Acc, $,, $", "ip", $", $:, $", IP, $"],
	ecs_server3(Port, NewAcc);
ecs_server2(_IP, Port, Acc) ->
	ecs_server3(Port, Acc).
%% @hidden
ecs_server3([$0], Acc) ->
	ecs_server4(Acc);
ecs_server3(Port, Acc) when length(Port) > 0 ->
	NewAcc = [Acc, $,, $", "port", $", $:, Port],
	ecs_server4(NewAcc);
ecs_server3(_Port, Acc) ->
	ecs_server4(Acc).
%% @hidden
ecs_server4([]) ->
	[];
ecs_server4(Acc) ->
	[$,, $", "server", $", $:, ${, Acc, $}].

-spec ecs_client(Address, Domain, IP, Port) -> iodata()
	when
		Address :: binary() | string(),
		Domain :: binary() | string(),
		IP :: inet:ip_address() | string(),
		Port :: non_neg_integer() | string().
%% @doc Elastic Common Schema (ECS): Client attributes.
ecs_client(Address, Domain, IP, Port) when is_tuple(IP) ->
	ecs_client(Address, Domain, inet:ntoa(IP), Port);
ecs_client(Address, Domain, IP, Port) when is_integer(Port) ->
	ecs_client(Address, Domain, IP, integer_to_list(Port));
ecs_client(Address, Domain, IP, Port)
		when ((length(Address) > 0) or (size(Address) > 0)) ->
	Acc = [$", "address", $", $:, $", Address, $"],
	ecs_client1(Domain, IP, Port, Acc);
ecs_client(_Address, Domain, IP, Port)
		when ((length(Domain) > 0) or (size(Domain) > 0)) ->
	Acc = [$", "address", $", $:, $", Domain, $"],
	ecs_client1(Domain, IP, Port, Acc);
ecs_client(_Address, Domain, IP, Port) when length(IP) > 0 ->
	Acc = [$", "address", $", $:, $", IP, $"],
	ecs_client1(Domain, IP, Port, Acc);
ecs_client(_Address, _Domain, _IP, Port) ->
	ecs_client3(Port, []).
%% @hidden
ecs_client1(Domain, IP, Port, Acc)
		when ((length(Domain) > 0) or (size(Domain) > 0)) ->
	NewAcc = [Acc, $,, $", "domain", $", $:, $", Domain, $"],
	ecs_client2(IP, Port, NewAcc);
ecs_client1(_Domain, IP, Port, Acc) ->
	ecs_client2(IP, Port, Acc).
%% @hidden
ecs_client2(IP, Port, Acc) when length(IP) > 0 ->
	NewAcc = [Acc, $,, $", "ip", $", $:, $", IP, $"],
	ecs_client3(Port, NewAcc);
ecs_client2(_IP, Port, Acc) ->
	ecs_client3(Port, Acc).
%% @hidden
ecs_client3([$0], Acc) ->
	ecs_client4(Acc);
ecs_client3(Port, Acc) when length(Port) > 0 ->
	NewAcc = [Acc, $,, $", "port", $", $:, Port],
	ecs_client4(NewAcc);
ecs_client3(_Port, Acc) ->
	ecs_client4(Acc).
%% @hidden
ecs_client4([]) ->
	[];
ecs_client4(Acc) ->
	[$,, $", "client", $", $:, ${, Acc, $}].

-spec ecs_network(Application, Protocol) -> iodata()
	when
		Application :: string(),
		Protocol :: string().
%% @doc Elastic Common Schema (ECS): Network attributes.
ecs_network(Application, Protocol) ->
	Napplication = [$", "application", $", $:, $", Application, $"],
	Nprotocol = [$", "protocol", $", $:, $", Protocol, $"],
	[$", "network", $", $:, ${, Napplication, $,, Nprotocol, $}].

-spec ecs_source(Address, Domain, SubDomain,
		UserName, UserIds) -> iodata()
	when
		Address :: binary() | string(),
		Domain :: binary() | string(),
		SubDomain :: binary() | string(),
		UserName :: binary() | string(),
		UserIds :: [string()].
%% @doc Elastic Common Schema (ECS): Source attributes.
ecs_source(Address, Domain, SubDomain, UserName, UserIds) ->
	Saddress = [$", "address", $", $:, $", Address, $"],
	Sdomain = [$", "domain", $", $:, $", Domain, $"],
	Ssubdomain = [$", "subdomain", $", $:, $", SubDomain, $"],
	{UserId, OtherIds} = case UserIds of
		[H]  ->
			{H, []};
		[H | T] ->
			{H, T};
		[] ->
			{[], []}
	end,
	User = [$", "user", $", $:, ${,
			$", "name", $", $:, $", UserName, $", $,,
			$", "id", $", $:, $", UserId, $", $}],
	Related = [$", "related", $", $:, ${,
			$", "user", $", $:, $[, $", UserId, $",
			[[$,, $", R, $"] || R <- OtherIds], $], $}],
	[$", "source", $", $:, ${, Saddress, $,, Sdomain, $,,
			Ssubdomain, $,, User, $,, Related, $}].

-spec ecs_destination(SubDomain) -> iodata()
	when
		SubDomain :: binary() | string().
%% @doc Elastic Common Schema (ECS): Destination attributes.
ecs_destination(SubDomain) ->
	Dsubdomain = [$", "subdomain", $", $:, $", SubDomain, $"],
	[$", "destination", $", $:, ${, Dsubdomain, $}].

-spec ecs_service(Name, Type) -> iodata()
	when
		Name :: string(),
		Type :: string().
%% @doc Elastic Common Schema (ECS): Service attributes.
ecs_service(Name, Type) ->
	Sname = [$", "name", $", $:, $", Name, $"],
	Stype = [$", "type", $", $:, $", Type, $"],
	Snode = [$", "node", $", $:, ${,
			$", "name", $", $:, $", atom_to_list(node()), $", $}],
	[$", "service", $", $:, ${, Sname, $,, Stype, $,, Snode, $}].

-spec ecs_event(Start, End, Duration,
		Kind, Category, Type, Outcome) -> iodata()
	when
		Start :: string(),
		End:: string(),
		Duration :: string(),
		Kind :: string(),
		Category :: string(),
		Type :: [string()],
		Outcome :: string().
%% @doc Elastic Common Schema (ECS): Event attributes.
ecs_event(Start, End, Duration, Kind, Category, Type, Outcome) ->
	Estart = [$", "start", $", $:, $", Start, $"],
	Eend = [$", "end", $", $:, $", End, $"],
	Eduration = [$", "duration", $", $:, $", Duration, $"],
	Ekind = [$", "kind", $", $:, $", Kind, $"],
	Ecategory = [$", "category", $", $:, $[, $", Category, $", $]],
	Etypes = case Type of
		[H] ->
			[$", H, $"];
		[H | T] ->
			[$", H, $" | [[$,, $", E, $"] || E <- T]]
	end,
	Etype = [$", "type", $", $:, $[, Etypes, $]],
	Eoutcome  = [$", "outcome", $", $:, $", Outcome, $"],
	[$", "event", $", $:, ${,
			Estart, $,, Eend, $,, Eduration, $,,
			Ekind, $,, Ecategory, $,, Etype, $,,
			Eoutcome, $}].

-spec ecs_user(Name, Id, Domain) -> iodata()
	when
		Name :: string(),
		Id :: string(),
		Domain :: string().
%% @doc Elastic Common Schema (ECS): User attributes.
ecs_user(Name, Id, Domain) ->
	Uname = [$", "name", $", $:, $", Name, $"],
	Uid = [$", "id", $", $:, $", Id, $"],
	Udomain = [$", "domain", $", $:, $", Domain, $"],
	[$", "user", $", $:, ${,
			Uname, $,, Uid, $,, Udomain, $}].

-spec subscriber_id(SubscriptionId) -> Result
	when
		SubscriptionId :: [#'3gpp_ro_Subscription-Id'{}],
		Result :: [string()].
%% @doc Parse a DIAMETER 'Subscription-Id' AVP.
subscriber_id(SubscriptionId) ->
	subscriber_id(SubscriptionId, []).
%% @hidden
subscriber_id([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = 0,
		'Subscription-Id-Data' = MSISDN} | T], Acc) ->
	subscriber_id(T, ["msisdn-" ++ binary_to_list(MSISDN) | Acc]);
subscriber_id([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = 1,
		'Subscription-Id-Data' = IMSI} | T], Acc) ->
	subscriber_id(T, ["imsi-" ++ binary_to_list(IMSI) | Acc]);
subscriber_id([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = 2,
		'Subscription-Id-Data' = SIPURI} | T], Acc) ->
	subscriber_id(T, ["sip-" ++ binary_to_list(SIPURI) | Acc]);
subscriber_id([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = 3,
		'Subscription-Id-Data' = NAI} | T], Acc) ->
	subscriber_id(T, ["nai-" ++ binary_to_list(NAI) | Acc]);
subscriber_id([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Type' = 4,
		'Subscription-Id-Data' = PRIVATE} | T], Acc) ->
	subscriber_id(T, ["private-" ++ binary_to_list(PRIVATE) | Acc]);
subscriber_id([], Acc) ->
	lists:reverse(Acc).

-spec ecs_url(URL) -> iodata()
	when
		URL :: uri_string:uri_string() | uri_string:uri_map().
%% @doc Elastic Common Schema (ECS): URL attributes.
ecs_url(URL) when is_list(URL) ->
	ecs_url(uri_string:parse(URL));
ecs_url(URL) when is_map(URL) ->
	Acc1 = case maps:get(host, URL, undefined)  of
		undefined ->
			[];
		Host ->
			[[$", "domain", $", $:, $", Host, $"]]
	end,
	Acc2 = case maps:get(port, URL, undefined) of
		undefined ->
			Acc1;
		Port ->
			[[$", "port", $", $:, integer_to_list(Port)] | Acc1]
	end,
	Acc3 = case maps:get(path, URL, undefined) of
		undefined ->
			Acc2;
		Path ->
			[[$", "path", $", $:, $", Path, $"] | Acc2]
	end,
	Acc4 = case maps:get(query, URL, undefined) of
		undefined ->
			Acc3;
		Query ->
			[[$", "query", $", $:, $", Query, $"] | Acc3]
	end,
	Acc5 = case maps:get(scheme, URL, undefined) of
		undefined ->
			Acc4;
		Scheme ->
			[[$", "scheme", $", $:, $", Scheme, $"] | Acc4]
	end,
	Acc6 = case maps:get(fragment, URL, undefined) of
		undefined ->
			Acc5;
		Fragment ->
			[[$", "fragment", $", $:, $", Fragment, $"] | Acc5]
	end,
	Acc7 = case maps:get(userinfo, URL, undefined) of
		undefined ->
			Acc6;
		Userinfo ->
			[[$", "username", $", $:, $", Userinfo, $"] | Acc6]
	end,
	case Acc7 of
		[H] ->
			[$", "url", $", $:, ${, H, $}];
		[H | T] ->
			[[$", "url", $", $:, ${, H | [[$,, E] || E <- T]], $}]
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
ecs_3gpp_ro(#'3gpp_ro_CCR'{'Session-Id' = SessionId,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNumber,
			'Auth-Application-Id' = _ApplicationId,
			'Service-Context-Id' = ServiceContextId,
			'Service-Information' = _ServiceInfo},
		#'3gpp_ro_CCA'{'Result-Code' = ResultCode}) ->
	[$", "3gpp_ro", $", $:, ${,
			$", "session_id", $", $:, $", SessionId, $", $,,
			$", "cc_request_type", $", $:, integer_to_list(RequestType), $,,
			$", "cc_request_number", $", $:, integer_to_list(RequestNumber), $,,
			$", "service_context_id", $", $:, $", ServiceContextId, $", $,,
			$", "result_code", $", $:, integer_to_list(ResultCode), $}].

%% @hidden
ecs_3gpp_rf(#'3gpp_rf_ACR'{'Session-Id' = SessionId,
			'Accounting-Record-Type' = RecordType,
			'Accounting-Record-Number' = RecordNumber,
			'Acct-Application-Id' = _ApplicationId,
			'Service-Context-Id' = ServiceContextId,
			'Service-Information' = _ServiceInfo},
		#'3gpp_rf_ACA'{'Result-Code' = ResultCode}) ->
	[$", "3gpp_ro", $", $:, ${,
			$", "session_id", $", $:, $", SessionId, $", $,,
			$", "acct_record_type", $", $:, integer_to_list(RecordType), $,,
			$", "acct_record_number", $", $:, integer_to_list(RecordNumber), $,,
			$", "service_context_id", $", $:, $", ServiceContextId, $", $,,
			$", "result_code", $", $:, integer_to_list(ResultCode), $}].

%% @hidden
ecs_prepaid(State, Call, Network, OCS) ->
	Acc = [$", "prepaid", $", $:, ${,
			$", "state", $", $:, $", atom_to_list(State), $"],
	ecs_prepaid1(Call, Network, OCS, Acc).
%% @hidden
ecs_prepaid1(#{direction := Direction} = Call, Network, OCS, Acc)
		when is_atom(Direction) ->
	Acc1 = [Acc, $,,
			$", "direction", $", $:, $", atom_to_list(Direction), $", $,,
			$", "calling", $", $:, $", get_string(calling, Call), $", $,,
			$", "called", $", $:, $", get_string(called, Call), $"],
	ecs_prepaid2(Network, OCS, Acc1);
ecs_prepaid1(#{originator := Originator, recipient := Recipient},
		Network, OCS, Acc) when is_list(Originator), is_list(Recipient) ->
	Acc1 = [Acc, $,,
			$", "originator", $", $:, $", Originator, $", $,,
			$", "recipient", $", $:, $", Recipient, $"],
	ecs_prepaid2(Network, OCS, Acc1);
ecs_prepaid1(_Call, Network, OCS, Acc) ->
	ecs_prepaid2(Network, OCS, Acc).
%% @hidden
ecs_prepaid2(#{hplmn := _HPLMN} = Network, OCS, Acc) ->
	Acc1 = [Acc, $,,
			$", "hplmn", $", $:, $", get_string(hplmn, Network), $", $,,
			$", "vplmn", $", $:, $", get_string(vplmn, Network), $"],
	ecs_prepaid3(Network, OCS, Acc1);
ecs_prepaid2(Network, OCS, Acc) ->
	ecs_prepaid3(Network, OCS, Acc).
%% @hidden
ecs_prepaid3(#{context := Context, session_id := SessionId}, OCS, Acc)
		when is_list(Context), is_binary(SessionId) ->
	Acc1 = [Acc, $,,
			$", "context", $", $:, $", Context, $", $,,
			$", "session", $", $:, $", binary_to_list(SessionId), $"],
	ecs_prepaid4(OCS, Acc1);
ecs_prepaid3(_Network, OCS, Acc) ->
	ecs_prepaid4(OCS, Acc).
%% @hidden
ecs_prepaid4(OCS, Acc) when map_size(OCS) == 0 ->
	[Acc, $}];
ecs_prepaid4(OCS, Acc) ->
	[Acc, $,, $", "ocs", $", $:, ${,
			$", "result", $", $:, $", get_string(nrf_result, OCS), $", $,,
			$", "cause", $", $:, $", get_string(nrf_cause, OCS), $", $}, $}].

%% @hidden
ecs_postpaid(State, Call, Network) ->
	Acc = [$", "postpaid", $", $:, ${,
			$", "state", $", $:, $", atom_to_list(State), $"],
	ecs_postpaid1(Call, Network, Acc).
%% @hidden
ecs_postpaid1(#{direction := Direction} = Call, Network, Acc)
		when is_atom(Direction) ->
	Acc1 = [Acc, $,,
			$", "direction", $", $:, $", atom_to_list(Direction), $", $,,
			$", "calling", $", $:, $", get_string(calling, Call), $", $,,
			$", "called", $", $:, $", get_string(called, Call), $"],
	ecs_postpaid2(Network, Acc1);

ecs_postpaid1(#{originator := Originator, recipient := Recipient},
		Network, Acc) when is_list(Originator), is_list(Recipient) ->
	Acc1 = [Acc, $,,
			$", "originator", $", $:, $", Originator, $", $,,
			$", "recipient", $", $:, $", Recipient, $"],
	ecs_postpaid2(Network, Acc1);
ecs_postpaid1(_Call, Network, Acc) ->
	ecs_postpaid2(Network, Acc).
%% @hidden
ecs_postpaid2(#{hplmn := _HPLMN} = Network, Acc) ->
	Acc1 = [Acc, $,,
			$", "hplmn", $", $:, $", get_string(hplmn, Network), $", $,,
			$", "vplmn", $", $:, $", get_string(vplmn, Network), $"],
	ecs_postpaid3(Network, Acc1);
ecs_postpaid2(Network, Acc) ->
	ecs_postpaid3(Network, Acc).
%% @hidden
ecs_postpaid3(#{context := Context, session_id := SessionId}, Acc)
		when is_list(Context), is_binary(SessionId) ->
	[Acc, $,,
			$", "context", $", $:, $", Context, $", $,,
			$", "session", $", $:, $", binary_to_list(SessionId), $", $}];
ecs_postpaid3(_Network, Acc) ->
	[Acc, $}].

%% @hidden
get_string(Key, Map) ->
	case maps:get(Key, Map, undefined) of
		Value when is_atom(Value) ->
			atom_to_list(Value);
		Value when is_integer(Value) ->
			integer_to_list(Value);
		Value when is_float(Value) ->
			float_to_list(Value);
		Value when is_list(Value) ->
			Value
	end.

%% @hidden
imsi(#{imsi := IMSI} = _Subscriber) when is_list(IMSI) ->
	"imsi-" ++ IMSI;
imsi(_Subscriber) ->
	"".

%% @hidden
msisdn(#{msisdn := MSISDN} = _Subscriber) when is_list(MSISDN) ->
	"msisdn-" ++ MSISDN;
msisdn(_Subscriber) ->
	"".

