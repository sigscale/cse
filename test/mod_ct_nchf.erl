%%% mod_ct_nchf.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% @doc This {@link //inets/httpd. httpd} callback module is used in
%%% 	the test suite for the 3GPP SBI `Nchf_SpendingLimitControl' service.
%%%
-module(mod_ct_nchf).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').

-export([do/1]).

-include_lib("inets/include/httpd.hrl").

-define(BASE_PATH, "/nchf-spendinglimitcontrol/v1").

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE > 23).
		-define(URI_DECODE(URI), uri_string:percent_decode(URI)).
	-else.
		-define(URI_DECODE(URI), http_uri:decode(URI)).
	-endif.
-else.
	-define(URI_DECODE(URI), http_uri:decode(URI)).
-endif.

-spec do(ModData) -> Result when
	ModData :: #mod{},
	Result :: {proceed, OldData} | {proceed, NewData} | {break, NewData} | done,
	OldData :: list(),
	NewData :: [{response,{StatusCode,Body}}] | [{response,{response,Head,Body}}]
			| [{response,{already_sent,StatusCode,Size}}],
	StatusCode :: integer(),
	Body :: iolist() | nobody | {Fun, Arg},
	Head :: [HeaderOption],
	HeaderOption :: {Option, Value} | {code, StatusCode},
	Option :: accept_ranges | allow
			| cache_control | content_MD5
			| content_encoding | content_language
			| content_length | content_location
			| content_range | content_type | date
			| etag | expires | last_modified
			| location | pragma | retry_after
			| server | trailer | transfer_encoding,
	Value :: string(),
	Size :: term(),
	Fun :: fun((Arg) -> sent| close | Body),
	Arg :: [term()].
%% @doc Erlang web server API callback function.
%% @hidden
do(#mod{data = Data} = ModData) ->
	case proplists:get_value(status, Data) of
		{_StatusCode, _PhraseArgs, _Reason} ->
			{proceed, Data};
		undefined ->
			do1(ModData)
	end.
%% @hidden
do1(#mod{data = Data} = ModData) ->
	case proplists:get_value(response, Data) of
		undefined ->
			do2(ModData);
		_Response ->
			{proceed, Data}
	end.
%% @hidden
do2(#mod{method = Method, parsed_header = Headers} = ModData)
		when Method == "POST"; Method == "PUT" ->
	case lists:keyfind("accept", 1, Headers) of
		{_, "application/json" ++ _} ->
			do3(ModData);
		{_, _} ->
			do_response(ModData, {error, 415});
		_ ->
			do_response(ModData, {error, 400})
	end;
do2(ModData) ->
	do3(ModData).
%% @hidden
do3(#mod{method = "POST" = _Method, request_uri = Path} = ModData) ->
	case string:lexemes(?URI_DECODE(Path),  [$/]) of
		["nchf-spendinglimitcontrol", "v1" | T] ->
			do_post(ModData, T);
		_Other ->
			do_response(ModData, {error, 404})
	end;
do3(#mod{method = "PUT" = _Method, request_uri = Path} = ModData) ->
	case string:lexemes(?URI_DECODE(Path),  [$/]) of
		["nchf-spendinglimitcontrol", "v1" | T] ->
			do_put(ModData, T);
		_ ->
			do_response(ModData, {error, 404})
	end;
do3(#mod{method = "DELETE" = _Method, request_uri = Path} = ModData) ->
	case string:lexemes(?URI_DECODE(Path),  [$/]) of
		["nchf-spendinglimitcontrol", "v1" | T] ->
			do_delete(ModData, T);
		_ ->
			do_response(ModData, {error, 404})
	end;
do3(#mod{method = _Method, request_uri = Path} = ModData) ->
	case string:lexemes(?URI_DECODE(Path),  [$/]) of
		["nchf-spendinglimitcontrol", "v1" | _] ->
			do_response(ModData, {error, 405});
		_ ->
			do_response(ModData, {error, 404})
	end.

%% @hidden
do_post(#mod{entity_body = Body} = ModData,
		["subscriptions"] = _Path) ->
	add_subscription(ModData, zj:decode(Body));
do_post(ModData, _Path) ->
	ProblemDetails = #{cause => "RESOURCE_URI_STRUCTURE_NOT_FOUND"},
	do_response(ModData, {error, 404}, ProblemDetails).

%% @hidden
do_put(#mod{entity_body = Body} = ModData,
		["subscriptions", SubscriptionId] = _Path) ->
	update_subscription(ModData, SubscriptionId, zj:decode(Body));
do_put(ModData, _Path) ->
	ProblemDetails = #{cause => "RESOURCE_URI_STRUCTURE_NOT_FOUND"},
	do_response(ModData, {error, 404}, ProblemDetails).

%% @hidden
do_delete(ModData,
		["subscriptions", _SubscriptionId] = _Path) ->
	do_response(ModData, {204, [], []});
do_delete(ModData, _Path) ->
	ProblemDetails = #{cause => "RESOURCE_URI_STRUCTURE_NOT_FOUND"},
	do_response(ModData, {error, 404}, ProblemDetails).

%% @hidden
add_subscription(ModData,
		{ok, #{"supi" := SUPI} = SpendingLimitContext})
		when is_list(SUPI) ->
	SubscriptionId = integer_to_list(rand:uniform(16#ffff)),
	SpendingLimitStatus = #{"supi" => SUPI},
	add_subscription1(ModData, SubscriptionId,
			SpendingLimitContext, SpendingLimitStatus);
add_subscription(ModData, {ok, #{} = _SpendingLimitContext}) ->
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => "/supi"}]},
	do_response(ModData, {error, 400}, ProblemDetails);
add_subscription(ModData, {error, _Partial, _Remaining}) ->
	ProblemDetails = #{cause => "INVALID_MSG_FORMAT"},
	do_response(ModData, {error, 400}, ProblemDetails).
%% @hidden
add_subscription1(ModData, SubscriptionId,
		#{"notifUri" := NotifyURI} = SpendingLimitContext,
		SpendingLimitStatus) when is_list(NotifyURI) ->
	add_subscription2(ModData, SubscriptionId,
			SpendingLimitContext, SpendingLimitStatus);
add_subscription1(ModData, SubscriptionId,
		#{} = SpendingLimitContext, SpendingLimitStatus) ->
	add_subscription2(ModData, SubscriptionId,
			SpendingLimitContext, SpendingLimitStatus).
%% @hidden
add_subscription2(ModData, SubscriptionId,
		#{"policyCounterIds" := PolicyCounterIds} = SpendingLimitContext,
		SpendingLimitStatus)
		when is_list(PolicyCounterIds) ->
	add_subscription3(ModData, SubscriptionId, SpendingLimitContext,
			SpendingLimitStatus, PolicyCounterIds);
add_subscription2(ModData, SubscriptionId,
		SpendingLimitContext, SpendingLimitStatus) ->
	F = fun F(0, Acc) ->
				Acc;
			F(N, Acc) ->
				F(N - 1, [cse_test_lib:rand_name() | Acc])
	end,
	PolicyCounterIds = F(rand:uniform(5), []),
	add_subscription3(ModData, SubscriptionId, SpendingLimitContext,
			SpendingLimitStatus, PolicyCounterIds).
%% @hidden
add_subscription3(ModData, SubscriptionId,
		SpendingLimitContext, SpendingLimitStatus, PolicyCounterIds) ->
	F = fun(E, Acc) ->
				Acc#{E => #{"policyCounterId" => E, 
						"currentStatus" => "active"}}
	end,
	StatusInfos = lists:foldl(F, #{}, PolicyCounterIds),
	add_subscription4(ModData, SubscriptionId, SpendingLimitContext,
			SpendingLimitStatus#{"statusInfos" => StatusInfos}).
%% @hidden
add_subscription4(ModData, SubscriptionId,
		#{"supportedFeatures" := _} = _SpendingLimitContext,
		SpendingLimitStatus) ->
	add_subscription5(ModData, SubscriptionId,
			SpendingLimitStatus#{"supportedFeatures" => "0"});
add_subscription4(ModData, SubscriptionId,
		_SpendingLimitContext, SpendingLimitStatus) ->
	add_subscription5(ModData, SubscriptionId, SpendingLimitStatus).
%% @hidden
add_subscription5(ModData, SubscriptionId, SpendingLimitStatus) ->
	Location = ?BASE_PATH ++ "/subscriptions/" ++ SubscriptionId,
	Headers = [{content_type, "application/json"}, {location, Location}],
	Body = zj:encode(SpendingLimitStatus),
	do_response(ModData, {201, Headers, Body}).

%% @hidden
update_subscription(ModData, SubscriptionId,
		{ok, #{"supi" := SUPI} = SpendingLimitContext})
		when is_list(SUPI) ->
	SubscriptionId = integer_to_list(rand:uniform(16#ffff)),
	SpendingLimitStatus = #{"supi" => SUPI},
	update_subscription1(ModData, SubscriptionId,
			SpendingLimitContext, SpendingLimitStatus);
update_subscription(ModData, _SubscriptionId,
		{ok, #{} = _SpendingLimitContext}) ->
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => "/supi"}]},
	do_response(ModData, {error, 400}, ProblemDetails);
update_subscription(ModData, _SubscriptionId,
		{error, _Partial, _Remaining}) ->
	ProblemDetails = #{cause => "INVALID_MSG_FORMAT"},
	do_response(ModData, {error, 400}, ProblemDetails).
%% @hidden
update_subscription1(ModData, SubscriptionId,
		#{"policyCounterIds" := PolicyCounterIds} = _SpendingLimitContext,
		SpendingLimitStatus)
		when is_list(PolicyCounterIds) ->
	update_subscription2(ModData, SubscriptionId,
			SpendingLimitStatus, PolicyCounterIds);
update_subscription1(ModData, SubscriptionId,
		_SpendingLimitContext, SpendingLimitStatus) ->
	F = fun F(0, Acc) ->
				Acc;
			F(N, Acc) ->
				F(N - 1, [cse_test_lib:random_dn() | Acc])
	end,
	PolicyCounterIds = F(rand:uniform(10), []),
	update_subscription2(ModData, SubscriptionId,
			SpendingLimitStatus, PolicyCounterIds).
%% @hidden
update_subscription2(ModData, SubscriptionId,
		SpendingLimitStatus, PolicyCounterIds) ->
	F = fun(E, Acc) ->
				Acc#{E => #{"policyCounterId" => E, 
						"currentStatus" => "active"}}
	end,
	StatusInfos = lists:foldl(F, #{}, PolicyCounterIds),
	update_subscription3(ModData, SubscriptionId,
			SpendingLimitStatus#{"statusInfos" => StatusInfos}).
%% @hidden
update_subscription3(ModData, _SubscriptionId, SpendingLimitStatus) ->
	Headers = [{content_type, "application/json"}],
	Body = zj:encode(SpendingLimitStatus),
	do_response(ModData, {201, Headers, Body}).

%% @hidden
do_response(#mod{data = Data} = ModData, {Code, Headers, ResponseBody}) ->
	Size = integer_to_list(iolist_size(ResponseBody)),
	NewHeaders = Headers ++ [{content_length, Size},
			{content_type, "application/json"}],
	send(ModData, Code, NewHeaders, ResponseBody),
	{proceed,[{response,{already_sent, Code, Size}} | Data]};
do_response(#mod{data = Data} = _ModData, {error, Status}) ->
	{proceed, [{response, {Status, []}} | Data]}.

%% @hidden
do_response(#mod{data = Data, parsed_header = RequestHeaders} = ModData,
		{error, 404},
		#{cause := "RESOURCE_URI_STRUCTURE_NOT_FOUND"} = ProblemDetails) ->
	ProblemDetails1 = ProblemDetails#{status => 404,
			title => "TS 29.594 API resource path is not found",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/404"},
	{ContentType, ResponseBody} = cse_rest:format_problem(ProblemDetails1, RequestHeaders),
	Size = integer_to_list(iolist_size(ResponseBody)),
	ResponseHeaders = [{content_length, Size}, {content_type, ContentType}],
	send(ModData, 404, ResponseHeaders, ResponseBody),
	{proceed, [{response, {already_sent, 404, Size}} | Data]};
do_response(#mod{data = Data, parsed_header = RequestHeaders} = ModData,
		{error, 400},
		#{cause := "INVALID_MSG_FORMAT"} = ProblemDetails) ->
	ProblemDetails1 = ProblemDetails#{status => 404,
			title => "Decode SpendingLimitContext failed",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{ContentType, ResponseBody} = cse_rest:format_problem(ProblemDetails1, RequestHeaders),
	Size = integer_to_list(iolist_size(ResponseBody)),
	ResponseHeaders = [{content_length, Size}, {content_type, ContentType}],
	send(ModData, 400, ResponseHeaders, ResponseBody),
	{proceed, [{response, {already_sent, 400, Size}} | Data]};
do_response(#mod{data = Data, parsed_header = RequestHeaders} = ModData,
		{error, 400},
		#{cause := "MANDATORY_IE_MISSING"} = ProblemDetails) ->
	ProblemDetails1 = ProblemDetails#{status => 404,
			title => "TS 29.594 API resource path is not found",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/404"},
	{ContentType, ResponseBody} = cse_rest:format_problem(ProblemDetails1, RequestHeaders),
	Size = integer_to_list(iolist_size(ResponseBody)),
	ResponseHeaders = [{content_length, Size}, {content_type, ContentType}],
	send(ModData, 400, ResponseHeaders, ResponseBody),
	{proceed, [{response, {already_sent, 400, Size}} | Data]}.

%% @hidden
send(#mod{socket = Socket, socket_type = SocketType} = Info,
		StatusCode, Headers, ResponseBody) ->
	httpd_response:send_header(Info, StatusCode, Headers),
	httpd_socket:deliver(SocketType, Socket, ResponseBody).

