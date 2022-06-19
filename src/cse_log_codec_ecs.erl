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
-export([codec_diameter_ecs/1]).
-export([ecs_base/1, ecs_server/4, ecs_client/2, ecs_network/2,
		ecs_source/5, ecs_destination/1, ecs_service/2, ecs_event/7]).
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
		Peer :: diameter:peer(),
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
		Request, Reply}) ->
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
		'Auth-Application-Id' = _ApplicationId,
		'Service-Context-Id' = _ServiceContextId,
		'User-Name' = UserName,
		'Subscription-Id' = SubscriptionId} = _Request,
		Reply, Start, Stop, Duration, Acc) ->
	EventType = case RequestType of
		1 ->  % INITIAL_REQUEST
			"start";
		2 ->  % UPDATE_REQUEST
			"info";
		3 ->  % TERMINATION_REQUEST
			"end";
		4 ->  % EVENT_REQUEST
			"info"
	end,
	UserIds = subscriber_id(SubscriptionId),
	NewAcc = [Acc, $,,
			ecs_service("sigscale-cse", "ocf"), $,,
			ecs_source(OriginHost, OriginHost, OriginRealm,
					UserName, UserIds), $,,
			ecs_destination(DestinationRealm)],
	codec_diameter_ecs3(Reply, EventType, Start, Stop, Duration, NewAcc).
%% @hidden
codec_diameter_ecs3({reply, #'3gpp_ro_CCA'{
		'Result-Code' = ResultCode}} = _Reply,
		EventType, Start, Stop, Duration, Acc) ->
	Outcome = case ResultCode of
		RC when RC >= 1000, RC < 2000 ->
			"unknown";
		RC when RC >= 2000, RC < 3000 ->
			"success";
		RC when RC >= 3000 ->
			"failure"
	end,
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "session", EventType, Outcome), $}];
codec_diameter_ecs3({answer_message, ResultCode},
		EventType, Start, Stop, Duration, Acc) ->
	Outcome = case ResultCode of
		RC when RC >= 1000, RC < 2000 ->
			"unknown";
		RC when RC >= 2000, RC < 3000 ->
			"success";
		RC when RC >= 3000 ->
			"failure"
	end,
	[Acc, $,,
			ecs_event(Start, Stop, Duration,
					"event", "session", EventType, Outcome), $}].

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
ecs_server(Address, Domain, IP, Port) ->
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
ecs_client(Address, Domain) ->
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
		Type :: string(),
		Outcome :: string().
%% @doc Elastic Common Schema (ECS): Event attributes.
ecs_event(Start, Stop, Duration, Kind, Category, Type, Outcome) ->
	Estart = [$", "start", $", $:, $", Start, $"],
	Estop = [$", "stop", $", $:, $", Stop, $"],
	Eduration = [$", "duration", $", $:, $", Duration, $"],
	Ekind = [$", "kind", $", $:, $", Kind, $"],
	Ecategory = [$", "category", $", $:, $", Category, $"],
	Etype = [$", "type", $", $:, $", Type, $"],
	Eoutcome  = [$", "outcome", $", $:, $", Outcome, $"],
	[$", "event", $", $:, ${,
			Estart, $,, Estop, $,, Eduration, $,,
			Ekind, $,, Ecategory, $,, Etype, $,,
			Eoutcome, $}].

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

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

