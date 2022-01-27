%%% cse_rest.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022 SigScale Global Inc.
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
%%% @doc This library module implements utility functions
%%% 	for REST servers in the {@link //cse. cse} application.
%%%
-module(cse_rest).
-copyright('Copyright (c) 2022 SigScale Global Inc.').

-export([format_problem/2]).

%%----------------------------------------------------------------------
%%  The cse_rest public API
%%----------------------------------------------------------------------

-type uri() :: string().
-type problem() :: #{type := uri(), title := string(),
		code := string(), cause => string(), detail => string(),
		invalidParams => [#{param := string(), reason => string()}],
		status => 200..599}.
-spec format_problem(Problem, Headers) -> Result
	when
		Problem :: problem(),
		Headers :: [tuple()],
		Result :: {ContentType, Body},
		ContentType :: string(),
		Body :: string().
%% @doc Format a problem report in an accepted content type.
%%
%% 	`Problem' MUST contain `type', `title', and `code'.
%% 	RFC7807 specifies `type' as a URI reference to
%% 	human-readable documentation for the problem type.
%% 	Use `title' for a short summary of the problem type.
%% 	TMF630 mandates `code' to provide an application
%% 	related code which may be included in an API
%% 	specification. 3GPP SBI adds `cause' and `invalidParams'.
%%
%% 	The result shall be formatted in one of the following
%% 	media types, in priority order:
%%
%%		ContentType :: "application/problem+json"
%%				| "application/json" | "text/html"
%% @private
format_problem(Problem, Headers) ->
	case lists:keyfind("accept", 1, Headers) of
		{_, Accept} ->
			format_problem1(Problem, string:tokens(Accept, ", "));
		false ->
			format_problem1(Problem, [])
	end.
%% @hidden
format_problem1(Problem, Accepted) ->
	F = fun(AcceptedType) ->
			lists:prefix("application/problem+json", AcceptedType)
	end,
	case lists:any(F, Accepted) of
		true ->
			Type = ["\t\"type\": \"", maps:get(type, Problem), "\",\n"],
			Title = ["\t\"title\": \"", maps:get(title, Problem), "\""],
			Detail = case maps:find(detail, Problem) of
				{ok, Value1} ->
					[",\n\t\"detail\": \"", Value1, "\""];
				error ->
					[]
			end,
			Cause = case maps:find(cause, Problem) of
				{ok, Value2} ->
					[",\n\t\"cause\": \"", Value2, "\""];
				error ->
					[]
			end,
			InvalidParams = case maps:find(invalidParams, Problem) of
				{ok, Value3} ->
					Fold = fun(#{param := P, reason := R}, Acc) ->
								Comma = case length(Acc) of
									0 ->
										[];
									_ ->
										",\n"
								end,
								Param = ["\t\t{\n\t\t\t\"param\": \"", P, "\",\n"],
								Reason = ["\t\t\t\"reason\": \"", R, "\"\n\t\t}"],
								Acc ++ [Comma, Param, Reason];
							(#{param := P}, Acc) ->
								Comma = case length(Acc) of
									0 ->
										[];
									_ ->
										",\n"
								end,
								Param = ["\t\t{\n\t\t\t\"param\": \"", P, "\"\n\t\t}"],
								Acc ++ [Comma, Param]
					end,
					[",\n\t\"invalidParams\": [\n",
							lists:foldl(Fold, [], Value3), "\n\t]"];
				error ->
					[]
			end,
			Status = case maps:find(status, Problem) of
				{ok, Value4} ->
					[",\n\t\"status\": ", integer_to_list(Value4)];
				error ->
					[]
			end,
			Code = case maps:get(code, Problem) of
				C1 when length(C1) > 0 ->
					[",\n\t\"code\": \"", C1, "\"\n"];
				_C1 ->
					[]
			end,
			{"application/problem+json",
					[${, $\n, Type, Title, Detail, Cause,
					InvalidParams, Status, Code, $\n, $}]};
		false ->
			format_problem2(Problem, Accepted)
	end.
%% @hidden
format_problem2(Problem, Accepted) ->
	F = fun(AcceptedType) ->
			lists:prefix("application/json", AcceptedType)
	end,
	case lists:any(F, Accepted) of
		true ->
			Class = "\t\"@type\": \"Error\",\n",
			Type = ["\t\"referenceError\": \"", maps:get(type, Problem), "\",\n"],
			Code = ["\t\"code\": \"", maps:get(code, Problem), "\",\n"],
			Reason = ["\t\"reason\": \"", maps:get(title, Problem), "\""],
			Message = case maps:find(detail, Problem) of
				{ok, Value1} ->
					[",\n\t\"message\": \"", Value1, "\""];
				error ->
					[]
			end,
			Status = case maps:find(status, Problem) of
				{ok, Value2} ->
					[",\n\t\"status\": \"", integer_to_list(Value2), "\""];
				error ->
					[]
			end,
			Body = [${, $\n, Class, Type, Code, Reason, Message, Status, $\n, $}],
			{"application/json", Body};
		false ->
			format_problem3(Problem)
	end.
%% @hidden
format_problem3(Problem) ->
	H1 = "\n\t\t\t<h1>SigScale CSE REST API</h1>\n",
	Paragraph  = "\t\t\t<p>Oops! Something went wrong.</p>\n",
	Header = ["\t\t<header>\n", H1, Paragraph, "\t\t</header>\n"],
	ProblemType = maps:get(type, Problem),
	Link = ["<a href=\"", ProblemType, "\">", ProblemType, "</a>"],
	Type = ["\t\t\t\<dt>Problem Type</dt>\n\t\t\t<dd>",
			Link, "</dd>\n"],
	Title = ["\t\t\t<dt>Title</dt>\n\t\t\t<dd>",
			maps:get(title, Problem), "</dd>\n"],
	Detail = case maps:find(detail, Problem) of
		{ok, Value1} ->
			["\t\t\t<dt>Detail</dt>\n\t\t\t<dd>",
					Value1, "</dd>\n"];
		error ->
			[]
	end,
	Cause = case maps:find(cause, Problem) of
		{ok, Value2} ->
			["\t\t\t<dt>Cause</dt>\n\t\t\t<dd>",
					Value2, "</dd>\n"];
		error ->
			[]
	end,
	InvalidParams = case maps:find(invalidParams, Problem) of
		{ok, Value3} ->
			F = fun(#{param := P, reason := R}, Acc) ->
						Acc ++ ["\t\t\t\t\t<tr>\n",
						"\t\t\t\t\t\t<td>", P, "</td>\n",
						"\t\t\t\t\t\t<td>", R, "</td>\n",
						"\t\t\t\t\t</tr>\n"];
					(#{param := P}, Acc) ->
						Acc ++ ["\t\t\t\t\t<tr>\n",
						"\t\t\t\t\t\t<td>", P, "</td>\n",
						"\t\t\t\t\t</tr>\n"]
			end,
			["\t\t\t<dt>Invalid Parameters</dt>\n\t\t\t<dd>\n",
					"\t\t\t\t<table>\n",
					"\t\t\t\t\t<tr>\n",
					"\t\t\t\t\t\t<th>Parameter</th>\n",
					"\t\t\t\t\t\t<th>Reason</th>\n",
					"\t\t\t\t\t</tr>\n",
					lists:foldl(F, [], Value3),
					"\t\t\t</dd>\n"];
		error ->
			[]
	end,
	Status = case maps:find(status, Problem) of
		{ok, Value4} ->
			["\t\t\t<dt>Status</dt>\n\t\t\t<dd>",
					integer_to_list(Value4), "</dd>\n"];
		error ->
			[]
	end,
	Code = case maps:get(code, Problem) of
		C1 when length(C1) > 0 ->
			["\t\t\t<dt>Code<dt>\n\t\t\t<dd>", C1, "</dd>\n"];
		_C1 ->
			[]
	end,
	Definitions = ["\t\t<dl>\n", Type, Title, Detail, Cause,
			InvalidParams, Status, Code, "\t\t</dl>\n"],
	Body = ["\t<body>\n", Header, Definitions, "\t</body>\n"],
	Head = "\t<head>\n\t\t<title>Error</title>\n\t</head>\n",
	HTML = ["<!DOCTYPE html>\n<html lang=\"en\">\n", Head, Body, "</html>"],
	{"text/html", HTML}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

