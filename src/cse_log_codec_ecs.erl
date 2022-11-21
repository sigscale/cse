%%% cse_log_codec_ecs.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
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
-copyright('Copyright (c) 2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse_log_codec_ecs  public API
-export([codec_diameter_ecs/1, codec_prepaid_ecs/1]).
-export([ecs_base/1, ecs_server/4, ecs_client/2, ecs_network/2,
		ecs_source/5, ecs_destination/1, ecs_service/2, ecs_event/7,
		ecs_url/1]).
-export([subscriber_id/1]).

-include("diameter_gen_3gpp_ro_application.hrl").
-include_lib("diameter/include/diameter.hrl").
%-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").

%%----------------------------------------------------------------------
%%  The cse_log_codec_ecs public API
%%----------------------------------------------------------------------

-spec codec_diameter_ecs(Term) -> iodata()
	when
		Term :: {Start, Stop, ServiceName, Peer, Request, Reply},
		Start :: pos_integer(),
		Stop :: pos_integer(),
		ServiceName :: diameter:service_name(),
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
	ServiceIp = inet:ntoa(Address),
	ServicePort = integer_to_list(Port),
	{ServerAddress, ClientAddress} = Capabilities#diameter_caps.origin_host,
	{ServerDomain, ClientDomain} = Capabilities#diameter_caps.origin_realm,
	Acc = [${,
			ecs_base(StartTime), $,,
			ecs_server(ServerAddress, ServerDomain, ServiceIp, ServicePort), $,,
			ecs_client(ClientAddress, ClientDomain)],
	codec_diameter_ecs1(Request, Reply, StartTime, StopTime, Duration, Acc).
%% @hidden
%% @todo TCP/SCTP transport attributes.
codec_diameter_ecs1(Request, Reply, Start, Stop, Duration, Acc) ->
	NewAcc = [Acc, $,,
			ecs_network("ro", "diameter")],
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
		1 ->  % INITIAL_REQUEST
			["protocol", "start"];
		2 ->  % UPDATE_REQUEST
			["protocol"];
		3 ->  % TERMINATION_REQUEST
			["protocol", "end"];
		4 ->  % EVENT_REQUEST
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
codec_diameter_ecs3(CCR,
		{reply, #'3gpp_ro_CCA'{'Result-Code' = ResultCode} = CCA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 1000, ResultCode < 2000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", EventType, "unknown"), $,,
			ecs_3gpp_ro(CCR, CCA), $}];
codec_diameter_ecs3(CCR,
		{reply, #'3gpp_ro_CCA'{'Result-Code' = ResultCode} = CCA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 2000, ResultCode  < 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["allowed" | EventType], "success"), $,,
			ecs_3gpp_ro(CCR, CCA), $}];
codec_diameter_ecs3(CCR,
		{reply, #'3gpp_ro_CCA'{'Result-Code' = ResultCode} = CCA},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["denied" | EventType], "failure"), $,,
			ecs_3gpp_ro(CCR, CCA), $}];
codec_diameter_ecs3(CCR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 1000, ResultCode < 2000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", EventType, "unknown"), $,,
			ecs_3gpp_ro(CCR, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(CCR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 2000, ResultCode  < 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["allowed" | EventType], "success"), $,,
			ecs_3gpp_ro(CCR, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}), $}];
codec_diameter_ecs3(CCR,
		{answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc)
		when ResultCode >= 3000 ->
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "network", ["denied" | EventType], "failure"), $,,
			ecs_3gpp_ro(CCR, #'3gpp_ro_CCA'{'Result-Code' = ResultCode}), $}].

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
		Call :: #{direction := Direction, calling := Calling, called := Called},
		Direction :: originating | terminating,
		Calling :: [$0..$9],
		Called :: [$0..$9],
		Network :: #{context => Context, session_id => SessionId,
				hplmn => PLMN, vplmn => PLMN},
		Context :: string(),
		SessionId :: binary(),
		PLMN :: string(),
		OCS :: #{nrf_location => NrfLocation},
		NrfLocation :: string().
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
codec_prepaid_ecs({Start, Stop, ServiceName,
		State, Subscriber, Call, Network, OCS} = _Term) ->
	StartTime = cse_log:iso8601(Start),
	StopTime = cse_log:iso8601(Stop),
	Duration = integer_to_list((Stop - Start) * 1000000),
	#{imsi := IMSI, msisdn := MSISDN} = Subscriber,
	Outcome = case State of
		exception ->
			"failure";
		_ ->
			"success"
	end,
	[${,
			ecs_base(StartTime), $,,
			ecs_service(ServiceName, "slp"), $,,
			ecs_network("nrf", "http"), $,,
			ecs_user("msisdn-" ++ MSISDN, "imsi-" ++ IMSI, []), $,,
			ecs_event(StartTime, StopTime, Duration,
					"event", "session", ["protocol", "end"], Outcome), $,,
			ecs_url(map_get(nrf_location, OCS)), $,,
			ecs_prepaid(State, Call, Network, OCS), $}].

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
			$", "version", $", $:, $", "8.2", $", $}],
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
		when (is_list(Address) or is_binary(Address)),
		(is_list(Domain) or is_binary(Domain)) ->
	Saddress = [$", "address", $", $:, $", Address, $"],
	Sdomain = [$", "domain", $", $:, $", Domain, $"],
	Sip = [$", "ip", $", $:, $", IP, $"],
	Sport = [$", "port", $", $:, $", Port, $"],
	[$", "server", $", $:, ${, Saddress, $,, Sdomain, $,, Sip, $,, Sport, $}].

-spec ecs_client(Address, Domain) -> iodata()
	when
		Address :: binary() | string(),
		Domain :: binary() | string().
%% @doc Elastic Common Schema (ECS): Client attributes.
ecs_client(Address, Domain)
		when (is_list(Address) or is_binary(Address)),
		(is_list(Domain) or is_binary(Domain)) ->
	Caddress = [$", "address", $", $:, $", Address, $"],
	Cdomain = [$", "domain", $", $:, $", Domain, $"],
	[$", "client", $", $:, ${, Caddress, $,, Cdomain, $}].

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
	User = [$", "user", $", $:, ${,
			$", "name", $", $:, $", UserName, $", $,,
			$", "id", $", $:, $", hd(UserIds), $", $}],
	Related = [$", "related", $", $:, ${,
			$", "user", $", $:, $[, $", hd(UserIds), $",
			[[$,, $", R, $"] || R <- tl(UserIds)], $], $}],
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

-spec ecs_event(Start, Stop, Duration,
		Kind, Category, Type, Outcome) -> iodata()
	when
		Start :: string(),
		Stop :: string(),
		Duration :: string(),
		Kind :: string(),
		Category :: string(),
		Type :: [string()],
		Outcome :: string().
%% @doc Elastic Common Schema (ECS): Event attributes.
ecs_event(Start, Stop, Duration, Kind, Category, Type, Outcome) ->
	Estart = [$", "start", $", $:, $", Start, $"],
	Estop = [$", "stop", $", $:, $", Stop, $"],
	Eduration = [$", "duration", $", $:, $", Duration, $"],
	Ekind = [$", "kind", $", $:, $", Kind, $"],
	Ecategory = [$", "category", $", $:, $", Category, $"],
	Etypes = case Type of
		[H] ->
			[$", H, $"];
		[H | T] ->
			[$", H, $" | [[$,, $", E, $"] || E <- T]]
	end,
	Etype = [$", "type", $", $:, $[, Etypes, $]],
	Eoutcome  = [$", "outcome", $", $:, $", Outcome, $"],
	[$", "event", $", $:, ${,
			Estart, $,, Estop, $,, Eduration, $,,
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
			[[$", "scheme", $", $:, $", Fragment, $"] | Acc5]
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
ecs_prepaid(State, Call, Network, _OCS) ->
	[$", "prepaid", $", $:, ${,
			$", "state", $", $:, $", atom_to_list(State), $", $,,
			$", "hplmn", $", $:, $", get_string(hplmn, Network), $", $,,
			$", "vplmn", $", $:, $", get_string(vplmn, Network), $", $,,
			$", "direction", $", $:, $", get_string(direction, Call), $", $,,
			$", "calling", $", $:, $", get_string(calling, Call), $", $,,
			$", "called", $", $:, $", get_string(called, Call), $", $}].

%% @hidden
get_string(Key, Map) ->
	case maps:get(Key, Map, undefined) of
		Value when is_atom(Value) ->
			atom_to_list(Value);
		Value ->
			Value
	end.

