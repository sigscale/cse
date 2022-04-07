%%% cse_rest_api_SUITE.erl
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
%%% Test suite for the REST API of the {@link //cse. cse} application.
%%%
-module(cse_rest_api_SUITE).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([resource_spec_add/0, resource_spec_add/1, get_specs/0, get_specs/1]).

-include("cse.hrl").
-include_lib("common_test/include/ct.hrl").

-define(specPath, "/resourceCatalogManagement/v4/resourceSpecification/").
-define(inventoryPath, "/resourceInventoryManagement/v1/resource/").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before the whole suite.
%%
init_per_suite(Config) ->
	catch application:unload(mnesia),
	PrivDir = ?config(priv_dir, Config),
	application:load(mnesia),
	ok = application:set_env(mnesia, dir, PrivDir),
	ok = cse_test_lib:init_tables(),
	ok = cse_test_lib:start([inets]),
	Modules = [mod_responsecontrol,
			mod_cse_rest_accepted_content, mod_cse_rest_get,
			mod_get, mod_cse_rest_post, mod_cse_rest_delete,
			mod_cse_rest_patch],
	Options = [{bind_address, {0,0,0,0}}, {port, 0},
			{server_name, atom_to_list(?MODULE)},
			{server_root, PrivDir},
			{document_root, "/"},
			{modules, Modules}],
	{ok, Httpd} = inets:start(httpd, Options),
	[{port, Port}] = httpd:info(Httpd, [port]),
	Url = "http://localhost:" ++ integer_to_list(Port),
	[{host, Url} | Config].

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = cse_test_lib:stop().

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(_TestCase, Config) ->
   Config.

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, _Config) ->
	ok.

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[resource_spec_add, get_specs].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

resource_spec_add() ->
	[{userdata, [{doc, "POST to Resource Specification collection"}]}].

resource_spec_add(Config) ->
	HostUrl = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Name = "DynamicRowSpec",
	ResourceSpec = row_resource_spec(Name),
	RequestBody = zj:encode(cse_rest_res_resource:resource_spec(ResourceSpec)),
	Request = {HostUrl ++ ?specPath,
			[Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceSpecMap} = zj:decode(ResponseBody),
	is_resource_spec(ResourceSpecMap).

get_specs() ->
	[{userdata, [{doc, "Retrieve Resource Specification collection"}]}].

get_specs(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?specPath, [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{ok, L} = zj:decode(Body),
	true = length(L) >= 2,
	F = fun(#{"id" := Id, "href" := Href,
					"resourceSpecCharacteristic" := Chars})
					when is_list(Id), is_list(Href), is_list(Chars) ->
				true;
			(#{}) ->
				false
	end,
	lists:all(F, L).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

row_resource_spec(Name) ->
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	Id = integer_to_list(TS) ++ "-" ++ integer_to_list(N),
	TableId = cse_rest_res_resource:prefix_table_spec_id(),
	#resource_spec{name = Name,
			description = "Dynamic table row specification",
			version = "1.1",
			status = active,
			category = "DynamicPrefixRow",
			related = [#resource_spec_rel{id = Id,
					href = ?specPath ++ Id, name = "DynamicPrefixTable",
					rel_type = "contained"},
				#resource_spec_rel{id = TableId,
					href = ?specPath ++ TableId,
					name = "PrefixTable", rel_type = "based"}],
			characteristic = [#resource_spec_char{name = "prefix",
					description = "Prefix to match",
					value_type = "String"},
				#resource_spec_char{name = "value",
					description = "Value returned from prefix match",
					value_type = "Integer"}]}.

is_resource_spec(#{"id" := Id, "href" := Href, "name" := Name,
		"description" := Description, "version" := Version,
		"lifecycleStatus" := Status, "category" := Category,
		"resourceSpecRelationship" := Rels,
		"resourceSpecCharacteristic" := Chars})
		when is_list(Id), is_list(Href), is_list(Name), is_list(Description),
		is_list(Version), is_list(Status), is_list(Category),
		is_list(Rels), is_list(Chars) ->
	true = lists:all(fun is_resource_spec_rel/1, Rels),
	lists:all(fun is_resource_spec_char/1, Chars);
is_resource_spec(_S) ->
	false.

is_resource_spec_rel(#{"id" := Id, href := Href, "name" := Name,
		"relationshipType" := RelType}) when is_list(Id), is_list(Href),
		is_list(Name), is_list(RelType) ->
	true;
is_resource_spec_rel(_R) ->
	false.

is_resource_spec_char(#{"name" := Name, "description" := Des,
		"valueType" := ValType}) when is_list(Name),
		is_list(Des), is_list(ValType) ->
	true;
is_resource_spec_char(_C) ->
	false.

