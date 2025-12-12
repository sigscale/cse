%%% cse_rest_res_health.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022 - 2025 SigScale Global Inc.
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //cse. cse} application.
%%%
%%% This module reports on the health of the system.
%%%
%%% @reference <a href="https://tools.ietf.org/id/draft-inadarei-api-health-check-06.html">
%%% 	Health Check Response Format for HTTP APIs</a>
%%%
-module(cse_rest_res_health).
-copyright('Copyright (c) 2022 - 2025 SigScale Global Inc.').

-export([content_types_accepted/0, content_types_provided/0,
		get_health/2, head_health/2,
		get_applications/2, head_applications/2,
		get_application/2, head_application/2]).

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: [string()].
%% @doc Provide list of resource representations accepted.
content_types_accepted() ->
	[].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: [string()].
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/health+json", "application/problem+json"].

-spec get_health(Query, RequestHeaders) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		RequestHeaders :: [tuple()],
		Result :: {ok, ResponseHeaders, ResponseBody}
				| {error, 503, ResponseHeaders, ResponseBody},
		ResponseHeaders :: [tuple()],
		ResponseBody :: iolist().
%% @doc Body producing function for
%% 	`GET /health'
%% 	requests.
get_health([] = _Query, _RequestHeaders) ->
	try
		Applications = application([cse,
				inets, m3ua, gtt, diameter, snmp]),
		Checks1 = #{"application" => Applications},
		F = fun(#{"componentId" := "cse"}) ->
					true;
				(_) ->
					false
		end,
		Status = case lists:search(F, Applications) of
			{value, #{"status" := S}} ->
				S;
			false ->
				undefined
		end,
		Checks2 = Checks1#{"table:size" => table_size([resource,
				resource_spec, cse_service, cse_context,
				m3ua_as, m3ua_asp, gtt_as, gtt_ep, gtt_pc])},
		Checks3 = Checks2#{"uptime" => up()},
		Checks4 = Checks3#{"slp:instances" => slpi()},
		Checks5 = maps:merge(Checks4,
				maps:from_list(get_diameter_statistics())),
		case scheduler() of
			{ok, HeadOptions, Scheds} ->
				{HeadOptions, Status,
						Checks5#{"scheduler:utilization" => Scheds}};
			{error, _Reason1} ->
				{[], Status, Checks5}
		end
	of
		{CacheControl, "up" = _Status, Checks} ->
			Health = #{"status" => "pass",
					"serviceId" => atom_to_list(node()),
					"description" => "Health of SigScale CSE",
					"checks" => Checks},
			ResponseBody = zj:encode(Health),
			ResponseHeaders = [{content_type, "application/health+json"}
					| CacheControl],
			{ok, ResponseHeaders, ResponseBody};
		{_CacheControl, _Status, Checks} ->
			Health = #{"status" => "fail",
					"serviceId" => atom_to_list(node()),
					"description" => "Health of SigScale CSE",
					"checks" => Checks},
			ResponseBody = zj:encode(Health),
			ResponseHeaders = [{content_type, "application/health+json"}],
			{error, 503, ResponseHeaders, ResponseBody}
	catch
		_:_Reason2 ->
			{error, 500}
	end.

-spec head_health(Query, RequestHeaders) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		RequestHeaders :: [tuple()],
		Result :: {ok, ResponseHeaders, ResponseBody}
				| {error, 503, ResponseHeaders, ResponseBody},
		ResponseHeaders :: [tuple()],
		ResponseBody :: [].
%% @doc Body producing function for
%% 	`HEAD /health'
%% 	requests.
head_health([] = _Query, _RequestHeaders) ->
	try
		Applications = application([cse]),
		Checks = #{"application" => Applications},
		Status = case hd(Applications) of
			#{"status" := S} ->
				S;
			_ ->
				undefined
		end,
		case scheduler() of
			{ok, HeadOptions, _Scheds} ->
				{HeadOptions, Status, Checks};
			{error, _Reason1} ->
				{[], Status, Checks}
		end
	of
		{CacheControl, "up" = _Status, _Checks} ->
			ResponseHeaders = [{content_type, "application/health+json"}
					| CacheControl],
			{ok, ResponseHeaders, []};
		{_CacheControl, _Status, _Checks} ->
			ResponseHeaders = [{content_type, "application/health+json"}],
			{error, 503, ResponseHeaders, []}
	catch
		_:_Reason2 ->
			{error, 500}
	end.

-spec get_applications(Query, RequestHeaders) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		RequestHeaders :: [tuple()],
		Result :: {ok, ResponseHeaders, ResponseBody}
				| {error, 503, ResponseHeaders, ResponseBody},
		ResponseHeaders :: [tuple()],
		ResponseBody :: iolist().
%% @doc Body producing function for
%% 	`GET /health/application'
%% 	requests.
get_applications([] = _Query, _RequestHeaders) ->
	try
		application([cse, inets, diameter, m3ua, gtt, snmp])
	of
		Applications ->
			F = fun(#{"status" := "up"}) ->
						false;
					(#{"status" := "down"}) ->
						true
			end,
			case lists:any(F, Applications) of
				false ->
					Application = #{"status" => "pass",
							"serviceId" => atom_to_list(node()),
							"description" => "OTP applications",
							"checks" => [#{"application" => Applications}]},
					ResponseBody = zj:encode(Application),
					ResponseHeaders = [{content_type, "application/health+json"}],
					{ok, ResponseHeaders, ResponseBody};
				true ->
					Application = #{"status" => "fail",
							"serviceId" => atom_to_list(node()),
							"description" => "OTP applications",
							"checks" => [#{"application" => Applications}]},
					ResponseBody = zj:encode(Application),
					ResponseHeaders = [{content_type, "application/health+json"}],
					{error, 503, ResponseHeaders, ResponseBody}
			end
	catch
		_:_Reason ->
			{error, 500}
	end.

-spec head_applications(Query, RequestHeaders) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		RequestHeaders :: [tuple()],
		Result :: {ok, ResponseHeaders, ResponseBody}
				| {error, 503, ResponseHeaders, ResponseBody},
		ResponseHeaders :: [tuple()],
		ResponseBody :: [].
%% @doc Body producing function for
%% 	`HEAD /health/application'
%% 	requests.
head_applications([] = _Query, _RequestHeaders) ->
	try
		application([cse, inets, diameter, m3ua, gtt, snmp])
	of
		Applications ->
			F = fun(#{"status" := "up"}) ->
						false;
					(#{"status" := "down"}) ->
						true
			end,
			case lists:any(F, Applications) of
				false ->
					ResponseHeaders = [{content_type, "application/health+json"}],
					{ok, ResponseHeaders, []};
				true ->
					ResponseHeaders = [{content_type, "application/health+json"}],
					{error, 503, ResponseHeaders, []}
			end
	catch
		_:_Reason ->
			{error, 500}
	end.

-spec get_application(Id, RequestHeaders) -> Result
	when
		Id :: string(),
		RequestHeaders :: [tuple()],
		Result :: {ok, ResponseHeaders, ResponseBody}
				| {error, 503, ResponseHeaders, ResponseBody},
		ResponseHeaders :: [tuple()],
		ResponseBody :: iolist().
%% @doc Body producing function for
%% 	`GET /health/application/{Id}'
%% 	requests.
get_application(Id, _RequestHeaders) ->
	try
		Running = application:which_applications(),
		case lists:keymember(list_to_existing_atom(Id), 1, Running) of
			true ->
				Application = #{"status" => "up", "serviceId" => Id},
				ResponseHeaders = [{content_type, "application/health+json"}],
				ResponseBody = zj:encode(Application),
				{ok, ResponseHeaders, ResponseBody};
			false ->
				Application = #{"status" => "down", "serviceId" => Id},
				ResponseHeaders = [{content_type, "application/health+json"}],
				ResponseBody = zj:encode(Application),
				{error, 503, ResponseHeaders, ResponseBody}
		end
	catch
		_:badarg ->
			{error, 404};
		_:_Reason ->
			{error, 500}
	end.

-spec head_application(Id, RequestHeaders) -> Result
	when
		Id :: string(),
		RequestHeaders :: [tuple()],
		Result :: {ok, ResponseHeaders, ResponseBody}
				| {error, 503, ResponseHeaders, ResponseBody},
		ResponseHeaders :: [tuple()],
		ResponseBody :: iolist().
%% @doc Body producing function for
%% 	`HEAD /health/application/{Id}'
%% 	requests.
head_application(Id, _RequestHeaders) ->
	try
		Running = application:which_applications(),
		case lists:keymember(list_to_existing_atom(Id), 1, Running) of
			true ->
				ResponseHeaders = [{content_type, "application/health+json"}],
				{ok, ResponseHeaders, []};
			false ->
				ResponseHeaders = [{content_type, "application/health+json"}],
				{error, 503, ResponseHeaders, []}
		end
	catch
		_:badarg ->
			{error, 404};
		_:_Reason ->
			{error, 500}
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec scheduler() -> Result
	when
		Result :: {ok, HeadOptions, Components} | {error, Reason},
		HeadOptions :: [{Option, Value}],
		Option :: etag | cache_control,
		Value :: string(),
		Components :: [map()],
		Reason :: term().
%% @doc Check scheduler component.
%% @hidden
scheduler() ->
	scheduler(cse:statistics(scheduler_utilization)).
scheduler({ok, {Etag, Interval, Report}}) ->
	[TS, _] = string:tokens(Etag, [$-]),
	Next = case (list_to_integer(TS) + Interval)
			- erlang:system_time(millisecond) of
		N when N =< 0 ->
			0;
		N when (N rem 1000) >= 500 ->
			(N div 1000) + 1;
		N ->
			N div 1000
	end,
	MaxAge = "max-age=" ++ integer_to_list(Next),
	HeadOptions = [{etag, Etag}, {cache_control, MaxAge}],
	F = fun({SchedulerId, Utilization}) ->
				#{"componentId" => integer_to_list(SchedulerId),
						"observedValue" => Utilization,
						"observedUnit" => "percent",
						"componentType" => "system"}
	end,
	Components = lists:map(F, Report),
	{ok, HeadOptions, Components};
scheduler({error, Reason}) ->
	{error, Reason}.

-spec application(Names) -> Check
	when
		Names :: [atom()],
		Check :: [map()].
%% @doc Check application component.
%% @hidden
application(Names) ->
	application(Names, application:which_applications(), []).
%% @hidden
application([Name | T], Running, Acc) ->
	Status = case lists:keymember(Name, 1, Running) of
		true ->
			"up";
		false ->
			"down"
	end,
	Application = #{"componentId" => atom_to_list(Name),
			"componentType" => "component",
			"status" => Status},
	application(T, Running, [Application | Acc]);
application([], _Running, Acc) ->
	lists:reverse(Acc).

-spec table_size(Names) -> Check
	when
		Names :: [atom()],
		Check :: [map()].
%% @doc Check table component size.
%% @hidden
table_size(Names) ->
	table_size(Names, []).
%% @hidden
table_size([Name | T], Acc) ->
	TableSize = #{"componentId" => atom_to_list(Name),
			"componentType" => "component",
			"observedUnit" => "rows",
			"observedValue" => mnesia:table_info(Name, size)},
	table_size(T, [TableSize | Acc]);
table_size([], Acc) ->
	lists:reverse(Acc).

-spec up() -> Time
	when
		Time :: [map()].
%% @doc Check uptime in seconds.
%% @hidden
up() ->
	CurrentTime = erlang:system_time(second),
	StartTime = erlang:convert_time_unit(erlang:system_info(start_time)
			+  erlang:time_offset(), native, second),
	Uptime = CurrentTime - StartTime,
	[#{"componentType" =>"system",
			"observedUnit" => "s",
			"observedValue" => Uptime}].

-spec slpi() -> Check
	when
		Check :: [map()].
%% @doc Check service logic program instance (SLPI) instance count.
%% @hidden
slpi() ->
	Counts = supervisor:count_children(cse_slp_sup),
	{active, Count} = lists:keyfind(active, 1, Counts),
	[#{"componentType" => "system",
			"observedValue" => Count}].

-spec get_diameter_statistics() -> DiameterChecks
	when
		DiameterChecks :: [tuple()].
%% @doc Get Diameter statistics checks.
get_diameter_statistics() ->
	Services = diameter:services(),
	Dictionaries = diameter_all_dictionaries(Services, []),
	get_diameter_checks(Dictionaries, Services, []).

%% @hidden
get_diameter_checks([Dictionary | T], Services, Acc) ->
	case get_diameter_counters(Dictionary, Services, #{}) of
		{_, []} = _Check ->
			get_diameter_checks(T, Services, Acc);
		Check ->
			get_diameter_checks(T, Services, [Check | Acc])
	end;
get_diameter_checks([], _Services, Acc) ->
	Acc.

%% @doc Get all dictionaries.
%% @hidden
diameter_all_dictionaries([Service | T], Acc) ->
	Applications = diameter:service_info(Service, applications),
	Dictionaries = diameter_dictionaries(Applications, []),
	diameter_all_dictionaries(T, [Dictionaries | Acc]);
diameter_all_dictionaries([], Acc) ->
	lists:sort(lists:flatten(Acc)).

%% @hidden
diameter_dictionaries([Application | T], Acc) ->
	{dictionary, Dictionary} = lists:keyfind(dictionary, 1, Application),
	diameter_dictionaries(T, [Dictionary | Acc]);
diameter_dictionaries([], Acc) ->
	Acc.

-spec get_diameter_counters(Dictionary, Services, Counters) -> Components
	when
		Dictionary :: atom(),
		Services :: [diameter:service_name()],
		Counters :: map(),
		Components :: tuple().
%% @doc Get Diameter count.
%% @hidden
get_diameter_counters(diameter_gen_base_rfc6733, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(0, Statistics, Counters),
	get_diameter_counters(diameter_gen_base_rfc6733, T, NewCounters);
get_diameter_counters(diameter_gen_base_rfc6733, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-base:counters", Components};
get_diameter_counters(diameter_gen_3gpp_ro_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(4, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_ro_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_ro_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-ro:counters", Components};
get_diameter_counters(diameter_gen_3gpp_rf_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(3, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_rf_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_rf_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-rf:counters", Components};
get_diameter_counters(diameter_gen_3gpp_gx_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777238, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_gx_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_gx_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-gx:counters", Components};
get_diameter_counters(diameter_gen_3gpp_s6a_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777251, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_s6a_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_s6a_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-s6a:counters", Components};
get_diameter_counters(diameter_gen_3gpp_s6b_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777272, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_s6b_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_s6b_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-s6b:counters", Components};
get_diameter_counters(diameter_gen_3gpp_sta_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777250, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_sta_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_sta_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-sta:counters", Components};
get_diameter_counters(diameter_gen_3gpp_swm_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777264, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_swm_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_swm_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-swm:counters", Components};
get_diameter_counters(diameter_gen_3gpp_swx_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777265, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_swx_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_swx_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-swx:counters", Components};
get_diameter_counters(diameter_gen_3gpp_sy_application, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(16777302, Statistics, Counters),
	get_diameter_counters(diameter_gen_3gpp_sy_application, T, NewCounters);
get_diameter_counters(diameter_gen_3gpp_sy_application, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-sy:counters", Components};
get_diameter_counters(diameter_gen_eap_application_rfc4072, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(5, Statistics, Counters),
	get_diameter_counters(diameter_gen_eap_application_rfc4072, T, NewCounters);
get_diameter_counters(diameter_gen_eap_application_rfc4072, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-eap:counters", Components};
get_diameter_counters(diameter_gen_nas_application_rfc7155, [Service | T], Counters) ->
	Statistics = diameter:service_info(Service, statistics),
	NewCounters = service_counters(1, Statistics, Counters),
	get_diameter_counters(diameter_gen_nas_application_rfc7155, T, NewCounters);
get_diameter_counters(diameter_gen_nas_application_rfc7155, [], Counters) ->
	Components = get_components(Counters),
	{"diameter-nas:counters", Components}.

%% @hidden
get_components(Counters) ->
	F = fun({CommandCode, ResultCode}, Count, Acc) ->
				[dia_count(CommandCode, ResultCode, Count) | Acc]
	end,
	maps:fold(F, [], Counters).

-spec service_counters(Application, Statistics, Counters) -> Counters
	when
		Application :: integer(),
		Statistics :: [tuple()],
		Counters :: #{{CommandCode, ResultCode} := Count},
		CommandCode :: pos_integer(),
		ResultCode :: pos_integer(),
		Count :: non_neg_integer().
%% @doc Parse service name statistics.
%% @hidden
service_counters(Application, [{_, PeerStat} | T] = _Statistics, Counters) ->
	NewCounters = peer_stat(Application, PeerStat, Counters),
	service_counters(Application, T, NewCounters);
service_counters(_Application, [], Counters) ->
	Counters.

%% @doc Parse peer statistics.
%% @hidden
peer_stat(Application, PeerStats, Counters) ->
	peer_stat1(Application, PeerStats, Counters).
%% @hidden
peer_stat1(Application, [{{{Application, CommandCode, 0}, send,
		{'Result-Code', ResultCode}}, Count} | T], Acc) ->
	NewAcc = case maps:find({CommandCode, ResultCode}, Acc) of
		{ok, Value} ->
			Acc#{{CommandCode, ResultCode} => Value + Count};
		error->
			Acc#{{CommandCode, ResultCode} => Count}
	end,
	peer_stat1(Application, T, NewAcc);
peer_stat1(Application, [_ | T], Acc) ->
	peer_stat1(Application, T, Acc);
peer_stat1(_Application, [], Acc) ->
	Acc.

-spec dia_count(CommandCode, ResultCode, Count) -> Component
	when
		CommandCode :: non_neg_integer(),
		ResultCode :: non_neg_integer(),
		Count :: non_neg_integer(),
		Component :: map().
%% @doc Returns JSON object for a diameter count.
dia_count(257, ResultCode, Count) ->
		ComponentId = "CEA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(280, ResultCode, Count) ->
		ComponentId = "DWA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(271, ResultCode, Count) ->
		ComponentId = "ACA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(282, ResultCode, Count) ->
		ComponentId = "DPA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(258, ResultCode, Count) ->
		ComponentId = "RAA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(274, ResultCode, Count) ->
		ComponentId = "ASA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(275, ResultCode, Count) ->
		ComponentId = "STA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(272, ResultCode, Count) ->
		ComponentId = "CCA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(265, ResultCode, Count) ->
		ComponentId = "AAA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(268, ResultCode, Count) ->
		ComponentId = "DEA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(301, ResultCode, Count) ->
		ComponentId = "SAA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(303, ResultCode, Count) ->
		ComponentId = "MAA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(304, ResultCode, Count) ->
		ComponentId = "RTA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(316, ResultCode, Count) ->
		ComponentId = "ULA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(318, ResultCode, Count) ->
		ComponentId = "AIA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count};
dia_count(321, ResultCode, Count) ->
		ComponentId = "PUA Result-Code: " ++ integer_to_list(ResultCode),
		#{"componentId" => ComponentId,
			"componentType" => "Protocol",
			"observedValue" => Count}.

