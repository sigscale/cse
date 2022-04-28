%%% mod_ct_nrf.erl
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
%%%
-module(mod_ct_nrf).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').

-export([do/1]).

-include_lib("inets/include/httpd.hrl").

-define(DIAMETERDATA, 32251).
-define(DIAMETERVOICE, 32260).
-define(DIAMETERSMS, 32274).

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
do(#mod{method = Method, parsed_header = Headers, request_uri = Uri,
		entity_body = Body, data = Data} = ModData) ->
	case Method of
		"POST" ->
			case proplists:get_value(status, Data) of
				{_StatusCode, _PhraseArgs, _Reason} ->
					{proceed, Data};
				undefined ->
					case proplists:get_value(response, Data) of
						undefined ->
							Path = http_uri:decode(Uri),
							content_type_available(Headers, Path, Body, ModData);
						_Response ->
							{proceed,  Data}
					end
			end;
		_ ->
			{proceed, Data}
	end.

%% @hidden
content_type_available(Headers, Uri, Body, #mod{data = Data} = ModData) ->
	case lists:keyfind("accept", 1, Headers) of
		{_, "application/json"} ->
			do_post(ModData, Body, string:tokens(Uri, "/"));
		{_, _} ->
			Response = "<h2>HTTP Error 415 - Unsupported Media Type</h2>",
			{proceed, [{response, {415, Response}} | Data]};
		_ ->
			do_response(ModData, {error, 400})
	end.

%% @hidden
do_post(ModData, Body, ["ratingdata"]) ->
	case zj:decode(Body) of
		{ok, #{"invocationSequenceNumber" := SequenceNumber} = Request} ->
			Now = erlang:system_time(millisecond),
			ServiceRatingResponse = rate(Request, ModData),
			Response = #{"invocationSequenceNumber" => SequenceNumber,
					"invocationTimeStamp" => cse_log:iso8601(Now),
					"serviceRating" => ServiceRatingResponse},
			RatingDataRef = integer_to_list(rand:uniform(16#ffff)),
			Headers = [{location, "/ratingdata/" ++ RatingDataRef}],
			do_response(ModData, {201, Headers, zj:encode(Response)});
		{error, _Partial, _Remaining} ->
			do_response(ModData, {error, 400})
	end;
do_post(ModData, Body, ["ratingdata", _RatingDataRef, Op])
		when Op == "update"; Op == "release" ->
	case zj:decode(Body) of
		{ok, #{"invocationSequenceNumber" := SequenceNumber,
				"serviceRating" := ServiceRatingRequests}} ->
			Now = erlang:system_time(millisecond),
			ServiceRatingResults = rate(ServiceRatingRequests, ModData),
			Response = #{"invocationSequenceNumber" => SequenceNumber,
					"invocationTimeStamp" => cse_log:iso8601(Now),
					"serviceRating" => ServiceRatingResults},
			do_response(ModData, {200, [], zj:encode(Response)});
		{error, _Partial, _Remaining} ->
			do_response(ModData, {error, 400})
	end.

-spec rate(Request, ModData) -> Response
	when
		Request :: map(),
		ModData :: #mod{},
		Response :: map().
%% @doc Build a rating response.
rate(#{"subscriptionId" := Subscriber, "serviceRating" := ServiceRating}, ModData) ->
	MSISDN = get_msisdn(Subscriber),
	case gen_server:call(ocs, {get_subscriber, MSISDN}) of
		{ok, {MSISDN, Balance}} when Balance < 0 ->
			Problem = #{cause => "QUOTA_LIMIT_REACHED",
					type => "https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0#/",
					title => "Request denied due to insufficient credit (usage applied)"},
			do_response(ModData, {error, 403, Problem});
		{ok, {MSISDN, Balance}} when Balance > 0 ->
			rate1(MSISDN, Balance, ServiceRating, ModData, []);
		{error, not_found} ->
			InvalidParams = [#{param => "/subscriptionId",
					reason => "Unknown subscriber identifier"}],
			Problem = #{cause => "USER_UNKNOWN",
					type => "https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0#/",
					title => "Request denied because the subscriber identity is unrecognized",
					invalidParams => InvalidParams},
			do_response(ModData, {error, 404, Problem});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end.
%% @hidden
rate1(Subscriber, Balance, [#{"requestSubType" := "RESERVE",
		"serviceContextId" := SvcContextId} = H | T], ModData, Acc)
		when Balance > 0 ->
	RSU = case service_type(SvcContextId) of
		?DIAMETERDATA ->
			rand:uniform(10000);
		?DIAMETERVOICE ->
			rand:uniform(3600);
		?DIAMETERSMS ->
			rand:uniform(10)
	end,
	case gen_server:call(ocs, {reserve, Subscriber, RSU}) of
		{ok, {Subscriber, NewBalance}} ->
			Data = maps:remove("requestedUnit", H),
			ServiceRating = Data#{"grantedUnit" => #{"totalVolume" => RSU},
			"resultCode" => "SUCCESS"},
			rate1(Subscriber, NewBalance, T, ModData, [ServiceRating | Acc]);
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, Balance, [#{"requestSubType" := "DEBIT",
		"consumedUnit" := ConsumedUnit} = H | T], ModData, Acc)
		when Balance > 0 ->
	USU = get_units(ConsumedUnit),
	case gen_server:call(ocs, {reserve, Subscriber, USU}) of
		{ok, {Subscriber, NewBalance}} ->
			ServiceRating = H#{"resultCode" => "SUCCESS"},
			rate1(Subscriber, NewBalance, T, ModData, [ServiceRating | Acc]);
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(_, _, [], _, Acc) ->
	lists:reverse(Acc).
	
%% @hidden
do_response(#mod{data = Data} = ModData, {Code, Headers, ResponseBody}) ->
	Size = integer_to_list(iolist_size(ResponseBody)),
	NewHeaders = Headers ++ [{content_length, Size},
			{content_type, "application/json"}],
	send(ModData, Code, NewHeaders, ResponseBody),
	{proceed,[{response,{already_sent, Code, Size}} | Data]};
do_response(#mod{data = Data} = _ModData, {error, 400}) ->
	Response = "<h2>HTTP Error 400 - Bad Request</h2>",
	{proceed, [{response, {400, Response}} | Data]}.

%% @hidden
send(#mod{socket = Socket, socket_type = SocketType} = Info,
		StatusCode, Headers, ResponseBody) ->
	httpd_response:send_header(Info, StatusCode, Headers),
	httpd_socket:deliver(SocketType, Socket, ResponseBody).

-spec get_msisdn(SubscriptionIds) -> Subscriber
	when
		SubscriptionIds :: [Id],
		Id :: string(),
		Subscriber :: string().
%% @hidden Get a subscriber id from list of subscribers.
get_msisdn(["msisdn-" ++ MSISDN | _]) ->
	MSISDN;
get_msisdn([_ | T]) ->
	get_msisdn(T);
get_msisdn([]) ->
	undefined.

%% @hidden
get_units(#{"time" := CCTime}) ->
	CCTime;
get_units(#{"totalVolume" := TotalVolume}) ->
	TotalVolume;
get_units(#{"serviceSpecificUnit" := ServiceSpecificUnit}) ->
	ServiceSpecificUnit.

%% @hidden
service_type(Id)
		when is_list(Id) ->
	service_type(list_to_binary(Id));
service_type(Id) ->
	% allow ".3gpp.org" or the proper "@3gpp.org"
	case binary:part(Id, size(Id), -8) of
		<<"3gpp.org">> ->
			ServiceContext = binary:part(Id, byte_size(Id) - 14, 5),
			case catch binary_to_integer(ServiceContext) of
				{'EXIT', _} ->
					undefined;
				SeviceType ->
					SeviceType
			end;
		_ ->
			undefined
	end.

