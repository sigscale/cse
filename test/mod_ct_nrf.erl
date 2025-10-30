%%% mod_ct_nrf.erl
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
%%%
-module(mod_ct_nrf).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').

-export([do/1]).

-include_lib("inets/include/httpd.hrl").

-define(PS,  "32251@3gpp.org").
-define(IMS, "32260@3gpp.org").
-define(MMS, "32270@3gpp.org").
-define(SMS, "32274@3gpp.org").
-define(VCS, "32276@3gpp.org").

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
							Path = ?URI_DECODE(Uri),
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
		{_, "application/json" ++ _} ->
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
		{ok, #{"invocationSequenceNumber" := SequenceNumber,
				"subscriptionId" := SubscriptionId} = Request} ->
			Now = erlang:system_time(millisecond),
			Subscriber = get_sub_id(SubscriptionId),
			ServiceRatingResponse = rate(Subscriber, Request, ModData),
			Response = #{"invocationSequenceNumber" => SequenceNumber,
					"invocationTimeStamp" => cse_log:iso8601(Now),
					"serviceRating" => ServiceRatingResponse},
			RatingDataRef = integer_to_list(rand:uniform(16#ffff)),
			Headers = [{location, "/ratingdata/" ++ RatingDataRef}],
			do_response(ModData, {201, Headers, zj:encode(Response)});
		{error, _Partial, _Remaining} ->
			do_response(ModData, {error, 400})
	end;
do_post(ModData, Body, ["ratingdata", _RatingDataRef, "update"]) ->
	case zj:decode(Body) of
		{ok, #{"invocationSequenceNumber" := SequenceNumber,
				"subscriptionId" := SubscriptionId} = Request} ->
			Now = erlang:system_time(millisecond),
			Subscriber = get_sub_id(SubscriptionId),
			ServiceRatingResponse = rate(Subscriber, Request, ModData),
			Response = #{"invocationSequenceNumber" => SequenceNumber,
					"invocationTimeStamp" => cse_log:iso8601(Now),
					"serviceRating" => ServiceRatingResponse},
			do_response(ModData, {200, [], zj:encode(Response)});
		{error, _Partial, _Remaining} ->
			do_response(ModData, {error, 400})
	end;
do_post(ModData, Body, ["ratingdata", _RatingDataRef, "release"]) ->
	case zj:decode(Body) of
		{ok, #{"invocationSequenceNumber" := SequenceNumber,
				"subscriptionId" := SubscriptionId} = Request} ->
			Now = erlang:system_time(millisecond),
			Subscriber = get_sub_id(SubscriptionId),
			ServiceRatingResponse = rate(Subscriber, Request, ModData),
			{ok, {_, 0} = _Account} = gen_server:call(ocs,
					{release, Subscriber}),
			Response = #{"invocationSequenceNumber" => SequenceNumber,
					"invocationTimeStamp" => cse_log:iso8601(Now),
					"serviceRating" => ServiceRatingResponse},
			do_response(ModData, {200, [], zj:encode(Response)});
		{error, _Partial, _Remaining} ->
			do_response(ModData, {error, 400})
	end.

-spec rate(Subscriber, Request, ModData) -> Response
	when
		Subscriber :: string(),
		Request :: map(),
		ModData :: #mod{},
		Response :: map().
%% @doc Build a rating response.
rate(Subscriber, #{"serviceContextId" := Context,
		"serviceRating" := ServiceRating} = _Request,
		ModData) when length(Context) > 14 ->
	Context1 = lists:sublist(Context, length(Context) - 13, 14),
	rate1(Subscriber, Context1, ServiceRating, ModData, []);
rate(Subscriber, #{"serviceContextId" := Context,
		"serviceRating" := ServiceRating} = _Request,
		ModData) ->
	rate1(Subscriber, Context, ServiceRating, ModData, []).
%% @hidden
rate1(Subscriber, ?PS = Context,
		[#{"requestSubType" := "RESERVE"} = H | T], ModData, Acc) ->
	Amount = (rand:uniform(10) + 5) * 1048576,
	case gen_server:call(ocs, {reserve, Subscriber, Amount}) of
		{ok, {_Balance, Reserve}} when Reserve > 0 ->
			H1 = maps:remove("requestedUnit", H),
			ServiceRating = H1#{"resultCode" => "SUCCESS",
					"grantedUnit" => #{"totalVolume" => Reserve}},
			rate1(Subscriber, Context, T, ModData, [ServiceRating | Acc]);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, ?IMS = Context,
		[#{"requestSubType" := "RESERVE"} = H | T],
		ModData, Acc) ->
	Amount = rand:uniform(50) * 30,
	case gen_server:call(ocs, {reserve, Subscriber, Amount}) of
		{ok, {_Balance, Reserve}} when Reserve > 0 ->
			H1 = maps:remove("requestedUnit", H),
			ServiceRating = H1#{"resultCode" => "SUCCESS",
					"grantedUnit" => #{"time" => Reserve}},
			rate1(Subscriber, Context, T, ModData, [ServiceRating | Acc]);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, Context,
		[#{"requestSubType" := "DEBIT"} = H | T],
		ModData, Acc)
		when Context == ?SMS; Context == ?MMS ->
	Amount = rand:uniform(5),
	case gen_server:call(ocs, {debit, Subscriber, Amount}) of
		{ok, {_Balance, _Reserve}} ->
			H1 = maps:remove("requestedUnit", H),
			ServiceRating = H1#{"resultCode" => "SUCCESS",
					"grantedUnit" => #{"serviceSpecificUnit" => 1}},
			rate1(Subscriber, Context, T, ModData, [ServiceRating | Acc]);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, Context,
		[#{"requestSubType" := "RESERVE"} = H | T],
		ModData, Acc)
		when Context == ?SMS; Context == ?MMS ->
	Amount = rand:uniform(5),
	case gen_server:call(ocs, {reserve, Subscriber, Amount}) of
		{ok, {_Balance, Reserve}} when Reserve > 0 ->
			H1 = maps:remove("requestedUnit", H),
			ServiceRating = H1#{"resultCode" => "SUCCESS",
					"grantedUnit" => #{"serviceSpecificUnit" => 1}},
			rate1(Subscriber, Context, T, ModData, [ServiceRating | Acc]);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, ?VCS = Context,
		[#{"requestSubType" := "RESERVE"} = H | T],
		ModData, Acc) ->
	Amount = rand:uniform(50) * 30,
	case gen_server:call(ocs, {reserve, Subscriber, Amount}) of
		{ok, {_Balance, Reserve}} when Reserve > 0 ->
			H1 = maps:remove("requestedUnit", H),
			ServiceRating = H1#{"resultCode" => "SUCCESS",
					"grantedUnit" => #{"time" => Reserve}},
			rate1(Subscriber, Context, T, ModData, [ServiceRating | Acc]);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, Context,
		[#{"requestSubType" := "DEBIT",
		"consumedUnit" := ConsumedUnit} = _H | T],
		ModData, Acc) ->
	Amount = get_units(ConsumedUnit),
	case gen_server:call(ocs, {debit, Subscriber, Amount}) of
		{ok, {Balance, _Reserve}} when Balance >= 0 ->
			rate1(Subscriber, Context, T, ModData, Acc);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(Subscriber, Context,
		[#{"requestSubType" := "RELEASE"} = _H | T],
		ModData, Acc) ->
	case gen_server:call(ocs, {debit, Subscriber, 0}) of
		{ok, {_Balance, _Reserve}} ->
			rate1(Subscriber, Context, T, ModData, Acc);
		{error, out_of_credit} ->
			do_response(ModData, {error, 403});
		{error, not_found} ->
			do_response(ModData, {error, 404});
		{error, _Reason} ->
			do_response(ModData, {error, 500})
	end;
rate1(_, _, [], _, Acc) ->
	lists:reverse(Acc).

%% @hidden
do_response(#mod{data = Data, parsed_header = RequestHeaders} = ModData, {error, 404}) ->
	InvalidParams = [#{param => "/subscriptionId",
			reason => "Unknown subscriber identifier"}],
	Problem = #{cause => "USER_UNKNOWN",
			type => "https://app.swaggerhub.com/apis-docs/SigScale/nrf-rating/1.2.0#/",
			title => "Request denied because the subscriber identity is unrecognized",
			code => "", status => 404,
			invalidParams => InvalidParams},
	{ContentType, ResponseBody} = cse_rest:format_problem(Problem, RequestHeaders),
	Size = integer_to_list(iolist_size(ResponseBody)),
	ResponseHeaders = [{content_length, Size}, {content_type, ContentType}],
	send(ModData, 404, ResponseHeaders, ResponseBody),
	{proceed, [{response, {already_sent, 404, Size}} | Data]};
do_response(#mod{data = Data, parsed_header = RequestHeaders} = ModData, {error, 403}) ->
	Problem = #{cause => "QUOTA_LIMIT_REACHED",
			type => "https://app.swaggerhub.com/apis-docs/SigScale/nrf-rating/1.2.0#/",
			code => "", status => 403,
			title => "Request denied due to insufficient credit (usage applied)"},
	{ContentType, ResponseBody} = cse_rest:format_problem(Problem, RequestHeaders),
	Size = integer_to_list(iolist_size(ResponseBody)),
	ResponseHeaders = [{content_length, Size}, {content_type, ContentType}],
	send(ModData, 403, ResponseHeaders, ResponseBody),
	{proceed, [{response, {already_sent, 403, Size}} | Data]};
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

-spec get_sub_id(SubscriptionIds) -> Subscriber
	when
		SubscriptionIds :: [Id],
		Id :: string(),
		Subscriber :: string().
%% @hidden Get an ID from list of subscription identifiers.
get_sub_id(["imsi-" ++ IMSI | _]) ->
	IMSI;
get_sub_id(["msisdn-" ++ MSISDN| _]) ->
	MSISDN;
get_sub_id(["nai-" ++ NAI | _]) ->
	NAI;
get_sub_id([_ | T]) ->
	get_sub_id(T);
get_sub_id([]) ->
	undefined.

%% @hidden
get_units(#{"time" := Time}) ->
	Time;
get_units(#{"totalVolume" := TotalVolume}) ->
	TotalVolume;
get_units(#{"serviceSpecificUnit" := ServiceSpecificUnit}) ->
	ServiceSpecificUnit.

