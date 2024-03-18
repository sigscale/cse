%%% cse_rest_api_SUITE.erl
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
%%% Test suite for the REST API of the {@link //cse. cse} application.
%%%
-module(cse_rest_api_SUITE).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([resource_spec_add/0, resource_spec_add/1,
		resource_spec_exists/0, resource_spec_exists/1,
		resource_spec_retrieve_static/0, resource_spec_retrieve_static/1,
		resource_spec_retrieve_dynamic/0, resource_spec_retrieve_dynamic/1,
		resource_spec_delete_static/0, resource_spec_delete_static/1,
		resource_spec_delete_dynamic/0, resource_spec_delete_dynamic/1,
		resource_spec_query_based/0, resource_spec_query_based/1,
		add_static_table_resource/0, add_static_table_resource/1,
		add_dynamic_table_resource/0, add_dynamic_table_resource/1,
		add_static_row_resource/0, add_static_row_resource/1,
		add_dynamic_row_resource/0, add_dynamic_row_resource/1,
		get_resource/0, get_resource/1, query_resource/0, query_resource/1,
		delete_static_table_resource/0, delete_static_table_resource/1,
		delete_dynamic_table_resource/0, delete_dynamic_table_resource/1,
		delete_row_resource/0, delete_row_resource/1,
		delete_row_query/0, delete_row_query/1,
		delete_range_row/0, delete_range_row/1,
		add_index_row_resource/0, add_index_row_resource/1,
		add_range_row_resource/0, add_range_row_resource/1,
		query_table_row/0, query_table_row/1,
		head_resources/0, head_resources/1,
		head_resource/0, head_resource/1,
		head_resource_specs/0, head_resource_specs/1,
		head_resource_spec/0, head_resource_spec/1,
		get_health/0, get_health/1,
		head_health/0, head_health/1]).

-include("cse.hrl").
-include_lib("common_test/include/ct.hrl").

-define(specPath, "/resourceCatalogManagement/v4/resourceSpecification/").
-define(inventoryPath, "/resourceInventoryManagement/v4/resource/").

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 25).
		-define(QUOTE(Data), uri_string:quote(Data)).
	-else.
		-define(QUOTE(Data), http_uri:encode(Data)).
	-endif.
-else.
	-define(QUOTE(Data), http_uri:encode(Data)).
-endif.

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
	ok = cse_test_lib:load(cse),
	ok = cse_test_lib:init_tables(),
	ok = cse_test_lib:start(),
	Modules = [mod_responsecontrol,
			mod_cse_rest_accepted_content, mod_cse_rest_get,
			mod_cse_rest_head, mod_get, mod_cse_rest_post,
			mod_cse_rest_delete, mod_cse_rest_patch],
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
	[resource_spec_add, resource_spec_exists, resource_spec_retrieve_static,
			resource_spec_retrieve_dynamic, resource_spec_delete_static,
			resource_spec_delete_dynamic, resource_spec_query_based,
			add_static_table_resource, add_dynamic_table_resource,
			add_static_row_resource, add_dynamic_row_resource,
			get_resource, query_resource, delete_static_table_resource,
			delete_dynamic_table_resource, delete_row_resource,
			delete_range_row, delete_row_query, query_table_row,
			add_index_row_resource, add_range_row_resource,
			head_resource_specs, head_resource_spec, head_resources,
			head_resource, get_health, head_health].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

resource_spec_add() ->
	[{userdata, [{doc, "POST to Resource Specification collection"}]}].

resource_spec_add(Config) ->
	SpecName = cse_test_lib:rand_name(8),
	SpecT = dynamic_prefix_table_spec(SpecName),
	SpecM = cse_rest_res_resource:resource_spec(SpecT),
	HostUrl = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(SpecM),
	Request = {HostUrl ++ ?specPath,
			[Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceSpecMap} = zj:decode(ResponseBody),
	true = is_resource_spec(ResourceSpecMap).

resource_spec_exists() ->
	[{userdata, [{doc, "Existing table spec with same name is a conflict"}]}].

resource_spec_exists(Config) ->
	HostUrl = ?config(host, Config),
	Fill = fun F(0, Acc) ->
				Acc;
			F(N, Acc) ->
				SpecName1 = cse_test_lib:rand_name(8),
				SpecT1 = dynamic_prefix_table_spec(SpecName1),
				{ok, _} = cse:add_resource_spec(SpecT1),
				F(N - 1, [SpecName1 | Acc])
	end,
	SpecNames = Fill(1000, []),
	SpecName2 = lists:nth(rand:uniform(length(SpecNames)), SpecNames),
	SpecT2 = dynamic_prefix_table_spec(SpecName2),
	SpecM = cse_rest_res_resource:resource_spec(SpecT2),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(SpecM),
	Request = {HostUrl ++ ?specPath,
			[Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 409, "Conflict"}, _Headers, _Body} = Result.

resource_spec_retrieve_static() ->
	[{userdata, [{doc, "Retrieve Static Resource Specifications"}]}].

resource_spec_retrieve_static(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	TableId = binary_to_list(cse_rest_res_resource:prefix_table_spec_id()),
	Request1 = {Host ++ ?specPath ++ TableId, [Accept]},
	{ok, Result1} = httpc:request(get, Request1, [], []),
	{{"HTTP/1.1", 200, _}, Headers1, Body1} = Result1,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers1),
	{ok, TableSpec} = zj:decode(Body1),
	RowId = binary_to_list(cse_rest_res_resource:prefix_row_spec_id()),
	Request2 = {Host ++ ?specPath ++ RowId, [Accept]},
	{ok, Result2} = httpc:request(get, Request2, [], []),
	{{"HTTP/1.1", 200, _}, Headers2, Body2} = Result2,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers2),
	{ok, RowSpec} = zj:decode(Body2),
	true = lists:all(fun is_resource_spec/1, [TableSpec, RowSpec]).

resource_spec_retrieve_dynamic() ->
	[{userdata, [{doc, "Retrieve  Resource Specification collection"}]}].

resource_spec_retrieve_dynamic(Config) ->
	SpecName = cse_test_lib:rand_name(8),
	SpecT = dynamic_prefix_table_spec(SpecName),
	SpecM = cse_rest_res_resource:resource_spec(SpecT),
	HostUrl = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(SpecM),
	Request1 = {HostUrl ++ ?specPath, [Accept], ContentType, RequestBody},
	{ok, Result1} = httpc:request(post, Request1, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers1, _ResponseBody1} = Result1,
	{_, URI} = lists:keyfind("location", 1, Headers1),
	{?specPath ++ ID, _} = httpd_util:split_path(URI),
	Request2 = {HostUrl ++ ?specPath ++ ID, [Accept]},
	{ok, Result2} = httpc:request(get, Request2, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers2, Body2} = Result2,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers2),
	{ok, RowSpec} = zj:decode(Body2),
	true = is_resource_spec(RowSpec).

resource_spec_delete_static() ->
	[{userdata, [{doc,"Delete Static Resource Specification"}]}].

resource_spec_delete_static(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	TableId = binary_to_list(cse_rest_res_resource:prefix_table_spec_id()),
	Request = {Host ++ ?specPath ++ TableId, [Accept]},
	{ok, Result} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 405, _BadRequest}, _Headers, _Body} = Result.

resource_spec_delete_dynamic() ->
	[{userdata, [{doc,"Delete Dynamic Resource Specification"}]}].

resource_spec_delete_dynamic(Config) ->
	TableSpecName = cse_test_lib:rand_name(8),
	TableSpecT = dynamic_prefix_table_spec(TableSpecName),
	{ok, #resource_spec{id = TableId}} = cse:add_resource_spec(TableSpecT),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?specPath ++ TableId, [Accept]},
	{ok, Result1} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers1, []} = Result1,
	{ok, Result2} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers2, _Response} = Result2.

resource_spec_query_based() ->
	[{userdata, [{doc,"Query Resource Specifications based on"
			"resource specification relathioship type"}]}].

resource_spec_query_based(Config) ->
	TableSpecName = cse_test_lib:rand_name(8),
	TableSpecT = dynamic_prefix_table_spec(TableSpecName),
	{ok, TableSpec} = cse:add_resource_spec(TableSpecT),
	Fill = fun F(0) ->
				ok;
			F(N) ->
				Name = cse_test_lib:rand_name(8),
				RowSpecT = dynamic_prefix_row_spec(Name, TableSpec),
				{ok, _Spec} = cse:add_resource_spec(RowSpecT),
				F(N-1)
	end,
	TotalSpecs = 10,
	ok = Fill(TotalSpecs),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Filter = "resourceSpecRelationship[?(@.relationshipType=='based'"
			"&&@.name=='" ++ TableSpecName ++ "')]",
	Request = {Host ++ lists:droplast(?specPath)
			++ "?filter=" ++ ?QUOTE(Filter), [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(Body)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, ResSpecs} = zj:decode(Body),
	true = length(ResSpecs) >= TotalSpecs,
	F1 = fun(#{"resourceSpecRelationship" := Rels}) ->
		F2 = fun F2([#{"relationshipType" := "based"} | _]) ->
					true;
				F2([_ | T]) ->
					F2(T);
				F2([]) ->
					false
		end,
		F2(Rels)
	end,
	true = lists:all(F1, ResSpecs).

add_static_table_resource() ->
	[{userdata, [{doc,"Add prefix table resource with POST"}]}].

add_static_table_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	TableT = static_prefix_table(TableName),
	TableM = cse_rest_res_resource:resource(TableT),
	RequestBody = zj:encode(TableM),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceMap} = zj:decode(ResponseBody),
	true = is_resource(ResourceMap).

add_dynamic_table_resource() ->
	[{userdata, [{doc,"Add dynamic prefix table resource with POST"}]}].

add_dynamic_table_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableSpecName = cse_test_lib:rand_name(8),
	TableSpecT = dynamic_prefix_table_spec(TableSpecName),
	{ok, TableSpec} = cse:add_resource_spec(TableSpecT),
	TableT = dynamic_prefix_table(TableName, TableSpec),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(cse_rest_res_resource:resource(TableT)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{"id" := Id} = ResourceMap} = zj:decode(ResponseBody),
	true = is_resource(ResourceMap),
	IdB = list_to_binary(Id),
	{ok, #resource{id = IdB}} = cse:find_resource(Id).

add_static_row_resource() ->
	[{userdata, [{doc,"Add prefix row resource in rest interface"}]}].

add_static_row_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableT = static_prefix_table(TableName),
	{ok, Table} = cse:add_resource(TableT),
	RowName = cse_test_lib:rand_name(8),
	Prefix = cse_test_lib:rand_name(6),
	Value = cse_test_lib:rand_name(20),
	Row = static_prefix_row(RowName, Table, Prefix, Value),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(cse_rest_res_resource:resource(Row)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceMap} = zj:decode(ResponseBody),
	true = is_resource(ResourceMap).

add_dynamic_row_resource() ->
	[{userdata, [{doc,"Add dynamic prefix row resource"}]}].

add_dynamic_row_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableSpecName = cse_test_lib:rand_name(8),
	TableSpecT = dynamic_prefix_table_spec(TableSpecName),
	{ok, TableSpec} = cse:add_resource_spec(TableSpecT),
	TableT = dynamic_prefix_table(TableName, TableSpec),
	{ok, Table} = cse:add_resource(TableT),
	RowSpecName = cse_test_lib:rand_name(8),
	RowSpecT = dynamic_prefix_row_spec(RowSpecName, TableSpec),
	{ok, RowSpec} = cse:add_resource_spec(RowSpecT),
	RowName = cse_test_lib:rand_name(8),
	Prefix1 = cse_test_lib:rand_name(6),
	Value1 = cse_test_lib:rand_name(20),
	Resource = dynamic_prefix_row(RowName, RowSpec, Table, Prefix1, Value1),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceMap} = zj:decode(ResponseBody),
	true = is_resource(ResourceMap),
	Chars = Resource#resource.characteristic,
	{ok, #characteristic{value = Prefix2}} = maps:find(<<"prefix">>, Chars),
	Prefix1 = binary_to_list(Prefix2),
	{ok, #characteristic{value = Value2}} = maps:find(<<"value">>, Chars),
	Value1 = binary_to_list(Value2),
	Value2 = cse_gtt:lookup_first(TableName, Prefix2).

get_resource() ->
	[{userdata, [{doc, "Retrieve Prefix Resource"}]}].

get_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableT = static_prefix_table(TableName),
	{ok, Table} = cse:add_resource(TableT),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	RowName = cse_test_lib:rand_name(8),
	Prefix = cse_test_lib:rand_name(6),
	Value = cse_test_lib:rand_name(20),
	Row = static_prefix_row(RowName, Table, Prefix, Value),
	{ok, #resource{id = Id}}= cse:add_resource(Row),
	Request = {Host ++ ?inventoryPath ++ Id, [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{ok, Resource} = zj:decode(Body),
	true = is_resource(Resource).

query_resource() ->
	[{userdata, [{doc,"Query Resource collection"}]}].

query_resource(Config) ->
	TableName1 = cse_test_lib:rand_name(8),
	TableName2 = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName1, []),
	ok = cse_gtt:new(TableName2, []),
	TableT1 = static_prefix_table(TableName1),
	TableT2 = static_prefix_table(TableName2),
	{ok, Table1} = cse:add_resource(TableT1),
	{ok, Table2} = cse:add_resource(TableT2),
	Fill = fun F(0, _Table) ->
				ok;
			F(N, Table) ->
				Name = cse_test_lib:rand_name(8),
				Prefix = cse_test_lib:rand_name(6),
				Value = cse_test_lib:rand_name(20),
				RowT = static_prefix_row(Name, Table, Prefix, Value),
				{ok, _Row} = cse:add_resource(RowT),
				F(N - 1, Table)
	end,
	TotalRows = 10,
	ok = Fill(TotalRows, Table1),
	ok = Fill(TotalRows, Table2),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	SpecId = binary_to_list(cse_rest_res_resource:prefix_row_spec_id()),
	Accept = {"accept", "application/json"},
	Filter = "resourceRelationship[?(@.relationshipType=='contained'"
			"&&@.resource.name=='" ++ TableName1 ++ "')]",
	Query = "?resourceSpecification.id=" ++ SpecId
			++ "&filter=" ++ ?QUOTE(Filter),
	Request = {Host ++ lists:droplast(?inventoryPath) ++ Query, [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(Body)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, Resources} = zj:decode(Body),
	true = length(Resources) == TotalRows,
	F1 = fun(#{"resourceRelationship" := Rels,
			"resourceSpecification" := #{"id" := SId}}) when SId == SpecId ->
		F2 = fun F2([#{"relationshipType" := "contained",
				"resource" := #{"name" := TN}} | _]) when TN == TableName1 ->
					true;
				F2([_ | T]) ->
					F2(T);
				F2([]) ->
					false
		end,
		F2(Rels)
	end,
	true = lists:all(F1, Resources).

delete_static_table_resource() ->
	[{userdata, [{doc,"Delete static table Resource by its id"}]}].

delete_static_table_resource(Config) ->
	TableName = "samplePrefixTable",
	ok = cse_gtt:new(TableName, []),
	TableSpecId = binary_to_list(cse_rest_res_resource:prefix_table_spec_id()),
	TableRes = #resource{name = list_to_binary(TableName),
			description = iolist_to_binary([TableName, " prefix table"]),
			specification = #resource_spec_ref{id = list_to_binary(TableSpecId),
					href = iolist_to_binary(["/resourceCatalogManagement/v4/",
							"resourceSpecification/", TableSpecId]),
					name = "PrefixTable"}},
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?inventoryPath ++binary_to_list( TableId), [Accept]},
	{ok, Result1} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers1, []} = Result1,
	{ok, Result2} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers2, _Response} = Result2.

delete_dynamic_table_resource() ->
	[{userdata, [{doc,"Delete dynamic Resource by its id"}]}].

delete_dynamic_table_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableSpecName = cse_test_lib:rand_name(8),
	TableSpecT = dynamic_prefix_table_spec(TableSpecName),
	{ok, TableSpec} = cse:add_resource_spec(TableSpecT),
	TableT = dynamic_prefix_table(TableName, TableSpec),
	{ok, #resource{id = TableId} = Table} = cse:add_resource(TableT),
	RowSpecName = cse_test_lib:rand_name(8),
	RowSpecT = dynamic_prefix_row_spec(RowSpecName, TableSpec),
	{ok, RowSpec} = cse:add_resource_spec(RowSpecT),
	RowName = cse_test_lib:rand_name(8),
	Prefix = cse_test_lib:rand_name(6),
	Value = cse_test_lib:rand_name(20),
	Resource = dynamic_prefix_row(RowName, RowSpec, Table, Prefix, Value),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request1 = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result1} = httpc:request(post, Request1, [], []),
	{{"HTTP/1.1", 201, _Created}, _Headers1, _ResponseBody} = Result1,
	Request2 = {Host ++ ?inventoryPath ++ binary_to_list(TableId), [Accept]},
	{ok, Result2} = httpc:request(delete, Request2, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers2, []} = Result2,
	{ok, Result3} = httpc:request(get, Request2, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers3, _Response} = Result3,
	0 = mnesia:table_info('tempDynamicTable', size).

delete_row_resource() ->
	[{userdata, [{doc,"Delete row Resource by its id"}]}].

delete_row_resource(Config) ->
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableT = static_prefix_table(TableName),
	{ok, Table} = cse:add_resource(TableT),
	RowName = cse_test_lib:rand_name(8),
	Prefix = cse_test_lib:rand_dn(10),
	Value = cse_test_lib:rand_name(20),
	RowT = static_prefix_row(RowName, Table, Prefix, Value),
	{ok, #resource{id = Id, href = URI}} = cse:add_resource(RowT),
	Host = ?config(host, Config),
	Request = {Host ++ URI, []},
	{ok, Result} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers, []} = Result,
	{error, not_found} = cse:find_resource(Id),
	undefined = cse_gtt:lookup_first(TableName, Prefix).

delete_range_row() ->
	[{userdata, [{doc,"Delete static range row resource"}]}].

delete_range_row(Config) ->
	TableNameS = cse_test_lib:rand_name(8),
	TableNameA = list_to_atom(TableNameS),
	ok = cse_gtt:new(TableNameA, []),
	TableT = static_range_table(TableNameS),
	{ok, Table} = cse:add_resource(TableT),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RowName = cse_test_lib:rand_name(8),
	Prefix = cse_test_lib:rand_dn(4),
	Start = Prefix ++ "00",
	End = Prefix ++ "99",
	Value = cse_test_lib:rand_name(20),
	Resource = static_range_row(RowName, Table, Start, End, Value),
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request1 = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result1} = httpc:request(post, Request1, [], []),
	{{"HTTP/1.1", 201, _Created}, _Headers, ResponseBody} = Result1,
	{ok, #{"id" := RowId, "href" := Href}} = zj:decode(ResponseBody),
	Request2 = {Host ++ Href, []},
	{ok, Result2} = httpc:request(delete, Request2, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _, _} = Result2,
	{error, not_found} = cse:find_resource(RowId),
	Fall = fun(RangePrefix) ->
			case cse_gtt:lookup_last(TableNameA, RangePrefix) of
				undefined ->
					true;
				_ ->
					false
			end
	end,
	true = lists:all(Fall, cse_gtt:range(Start, End)).

delete_row_query() ->
	[{userdata, [{doc,"Delete row by query on column value"}]}].

delete_row_query(Config) ->
	TableName = cse_test_lib:rand_name(8),
	TotalRows =  rand:uniform(100) + 10,
	ok = cse_gtt:new(TableName, []),
	TableSpecName = cse_test_lib:rand_name(8),
	TableSpecT = dynamic_prefix_table_spec(TableSpecName),
	{ok, TableSpec} = cse:add_resource_spec(TableSpecT),
	TableT = dynamic_prefix_table(TableName, TableSpec),
	{ok, Table} = cse:add_resource(TableT),
	RowSpecName = cse_test_lib:rand_name(8),
	RowSpecT = dynamic_prefix_row_spec(RowSpecName, TableSpec),
	{ok, RowSpec} = cse:add_resource_spec(RowSpecT),
	Fill = fun F(0, Acc) ->
				Acc;
			F(N, Acc) ->
				RowName = cse_test_lib:rand_name(6),
				Prefix = cse_test_lib:rand_dn(10),
				Value = cse_test_lib:rand_name(20),
				RowT = dynamic_prefix_row(RowName,
						RowSpec, Table, Prefix, Value),
				{ok, #resource{id = RowId}} = cse:add_resource(RowT),
				F(N - 1, [{RowId, Prefix} | Acc])
	end,
	Rows = Fill(TotalRows, []),
	{RowId, Prefix} = lists:nth(rand:uniform(length(Rows)), Rows),
	Host = ?config(host, Config),
	Filter = "resourceCharacteristic[?(@.name=='prefix' && @.value=='"
			++ Prefix ++ "')]",
	Query = "?resourceSpecification.id=" 
			++ binary_to_list(RowSpec#resource_spec.id)
			++ "&filter=" ++ ?QUOTE(Filter),
	URI =  Host ++ lists:droplast(?inventoryPath) ++ Query,
	Request = {URI, []},
	{ok, Result} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers, []} = Result,
	{error, not_found} = cse:find_resource(RowId),
	undefined = cse_gtt:lookup_first(TableName, Prefix).

add_range_row_resource() ->
	[{userdata, [{doc,"Add dynamic prefix row resource"}]}].

add_range_row_resource(Config) ->
	TableNameS = cse_test_lib:rand_name(8),
	TableNameA = list_to_atom(TableNameS),
	ok = cse_gtt:new(TableNameA, []),
	TableT = static_range_table(TableNameS),
	{ok, Table} = cse:add_resource(TableT),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RowName = cse_test_lib:rand_name(8),
	Prefix = cse_test_lib:rand_dn(4),
	Start = Prefix ++ "00",
	End = Prefix ++ "99",
	Value = cse_test_lib:rand_name(20),
	Resource = static_range_row(RowName, Table, Start, End, Value),
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	F1 = fun F1({eof, Gtts}, Acc) ->
				lists:flatten([Gtts | Acc]);
			F1({Cont, [#gtt{} | _] = Gtts}, Acc) ->
				F1(cse_gtt:list(Cont, TableNameS), [Gtts | Acc])
	end,
	RangeGtts = F1(cse_gtt:list(start, TableNameA), []),
	Prefixes = cse_gtt:range(Start, End),
	F2 = fun(Prefix1) ->
			case lists:keyfind(Prefix1, #gtt.num, RangeGtts) of
				#gtt{num = Prefix1} ->
					true;
				false ->
					false
			end
	end,
	true = lists:all(F2, Prefixes).

add_index_row_resource() ->
	[{userdata, [{doc,"Add static index row resource"}]}].

add_index_row_resource(Config) ->
	TableNameS = cse_test_lib:rand_name(8),
	TableNameA = list_to_atom(TableNameS),
	{atomic, ok} = mnesia:create_table(TableNameA, []),
	TableT = static_index_table(TableNameS),
	{ok, TableR} = cse:add_resource(TableT),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RowName1 = cse_test_lib:rand_name(8),
	Key1 = cse_test_lib:rand_name(6),
	Value1 = cse_test_lib:rand_name(20),
	ResourceT = static_index_row(RowName1, TableR, Key1, Value1),
	RequestBody = zj:encode(cse_rest_res_resource:resource(ResourceT)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{"id" := RowId} = _ResourceM} = zj:decode(ResponseBody),
	{ok, #resource{name = RowName2} = _ResourceR} = cse:find_resource(RowId),
	RowName1 = binary_to_list(RowName2),
	Key2 = list_to_binary(Key1),
	Value2 = list_to_binary(Value1),
	F = fun() ->
			mnesia:read(TableNameA, Key2, read)
	end,
	{atomic, [{TableNameA, Key2, Value2}]} = mnesia:transaction(F).

query_table_row() ->
	[{userdata, [{doc,"Query Resource Characteristics"}]}].

query_table_row(Config) ->
	Host = ?config(host, Config),
	TableName = cse_test_lib:rand_name(8),
	ok = cse_gtt:new(TableName, []),
	TableT = static_prefix_table(TableName),
	{ok, Table} = cse:add_resource(TableT),
	TableSpecT = dynamic_prefix_table_spec(TableName),
	{ok, TableSpec} = cse:add_resource_spec(TableSpecT),
	RowSpecName = cse_test_lib:rand_name(8),
	RowSpecT = dynamic_prefix_row_spec(RowSpecName, TableSpec),
	{ok, RowSpec} = cse:add_resource_spec(RowSpecT),
	Fill = fun F(0, Acc) ->
				Acc;
			F(N, Acc) ->
				RowName = cse_test_lib:rand_name(8),
				Prefix = cse_test_lib:rand_name(10),
				Value = cse_test_lib:rand_name(20),
				Row = dynamic_prefix_row(RowName,
						RowSpec, Table, Prefix, Value),
				{ok, #resource{id = RowId}} = cse:add_resource(Row),
				F(N - 1, [{RowId, Prefix} | Acc])
	end,
	Rows = Fill(1000, []),
	{RowId1, Prefix1} = lists:nth(rand:uniform(length(Rows)), Rows),
	Accept = {"accept", "application/json"},
	Filter = "resourceCharacteristic[?(@.name=='prefix'"
			"&&@.value=='" ++ Prefix1 ++ "')]",
	Request = {Host ++ lists:droplast(?inventoryPath)
			++ "?filter=" ++ ?QUOTE(Filter), [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, [#{"id" := RowId2}]} = zj:decode(ResponseBody),
	RowId1 = list_to_binary(RowId2).

head_resource_specs() ->
	[{userdata, [{doc, "HEAD request on static resource specification collection"}]}].

head_resource_specs(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?specPath, [Accept]},
	{ok, Result} = httpc:request(head, Request, [], []),
	{{"HTTP/1.1", 200, _}, Headers, []} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{_, Range} = lists:keyfind("content-range", 1, Headers),
	[_, N, N] = string:lexemes(Range, [$-, $/]).

head_resource_spec() ->
	[{userdata, [{doc, "HEAD request on static resource specification"}]}].

head_resource_spec(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	TableId = binary_to_list(cse_rest_res_resource:index_table_spec_id()),
	Request = {Host ++ ?specPath ++ TableId, [Accept]},
	{ok, Result} = httpc:request(head, Request, [], []),
	{{"HTTP/1.1", 200, _}, Headers, []} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{_, _Length} = lists:keyfind("content-length", 1, Headers).

head_resources() ->
	[{userdata, [{doc, "HEAD request on Resource collection"}]}].

head_resources(Config) ->
	TableNameS = cse_test_lib:rand_name(8),
	TableNameA = list_to_atom(TableNameS),
	{atomic, ok} = mnesia:create_table(TableNameA, []),
	TableT = static_index_table(TableNameS),
	{ok, _Resource} = cse:add_resource(TableT),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?inventoryPath, [Accept]},
	{ok, Result} = httpc:request(head, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, []} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{_, Range} = lists:keyfind("content-range", 1, Headers),
	[_, N, N] = string:lexemes(Range, [$-, $/]).

head_resource() ->
	[{userdata, [{doc, "HEAD request on static resource"}]}].

head_resource(Config) ->
	Host = ?config(host, Config),
	TableNameS = cse_test_lib:rand_name(8),
	TableNameA = list_to_atom(TableNameS),
	{atomic, ok} = mnesia:create_table(TableNameA, []),
	TableT = static_index_table(TableNameS),
	{ok, #resource{id = TableId}} = cse:add_resource(TableT),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?inventoryPath ++ TableId, [Accept]},
	{ok, Result} = httpc:request(head, Request, [], []),
	{{"HTTP/1.1", 200, _}, Headers, []} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{_, _Length} = lists:keyfind("content-length", 1, Headers).

get_health() ->
	[{userdata, [{doc,"Get health in rest interface"}]}].

get_health(Config) ->
	HostUrl = ?config(host_url, Config),
	HttpOpt = ?config(http_options, Config),
	Accept = {"accept", "application/health+json"},
	Request = {HostUrl ++ "/health", [Accept]},
	{ok, Result} = httpc:request(get, Request, HttpOpt, []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/health+json"} = lists:keyfind("content-type", 1, Headers),
	#{"serviceId" := _Node,
			"description" := "Health of SigScale OCS",
			"checks" := #{"uptime" := [Time]},
			"status" := "pass"} = zj:decode(Body),
	#{"componentType" := "system",
			"observedUnit" := "s",
			"observedValue" := Uptime} = Time,
	Uptime > 0.

head_health() ->
	[{userdata, [{doc,"Get headers (only) of health in rest interface"}]}].

head_health(Config) ->
	HostUrl = ?config(host_url, Config),
	HttpOpt = ?config(http_options, Config),
	Accept = {"accept", "application/health+json"},
	Request = {HostUrl ++ "/health", [Accept]},
	{ok, Result} = httpc:request(head, Request, HttpOpt, []),
	{{"HTTP/1.1", 200, _OK}, Headers, _Body} = Result,
	{_, "application/health+json"} = lists:keyfind("content-type", 1, Headers).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

is_resource(#{"id" := Id, "href" := Href, "name" := Name,
		"description" := Description, "version" := Version,
		"lastUpdate" := LastUpdate, "category" := Category,
		"resourceSpecification" := ResourceSpec,
		"resourceCharacteristic" := Chars, "resourceRelationship" := Rels})
		when is_list(Id), is_list(Href), is_list(Name), is_list(Description),
		is_list(Version), is_list(LastUpdate), is_list(Category),
		is_map(ResourceSpec), is_list(Chars), is_list(Rels) ->
	true = is_resource_spec_ref(ResourceSpec),
	true = lists:all(fun is_resource_rel/1, Rels),
	lists:all(fun is_resource_char/1, Chars);
is_resource(#{"id" := Id, "href" := Href, "name" := Name,
		"description" := Description, "version" := Version,
		"lastUpdate" := LastUpdate, "category" := Category,
		"resourceSpecification" := ResourceSpec})
		when is_list(Id), is_list(Href), is_list(Name), is_list(Description),
		is_list(Version), is_list(LastUpdate),
		is_list(Category), is_map(ResourceSpec) ->
	is_resource_spec_ref(ResourceSpec);
is_resource(_S) ->
	false.

is_resource_spec_ref(#{"id" := SpecId, "href" := SpecHref, "name" := SpecName})
		when is_list(SpecId), is_list(SpecHref), is_list(SpecName) ->
	true;
is_resource_spec_ref(_) ->
	false.

is_resource_rel(#{"relationshipType" := "contained",
		"resource" := #{"id" := ResId, "href" := ResHref, "name" := ResName}})
		when is_list(ResId), is_list(ResHref), is_list(ResName) ->
	true;
is_resource_rel(_R) ->
	false.

is_resource_char(#{"name" := Name}) when is_list(Name) ->
	true;
is_resource_char(_) ->
	false.

static_index_table(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:index_table_spec_id(),
	SpecRef = #resource_spec_ref{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"IndexTable">>},
	#resource{name = NameB,
			description = <<"Index Table">>,
			category = <<"Index">>,
			version = <<"1.0">>,
			specification = SpecRef}.

dynamic_index_table(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecRef = #resource_spec_ref{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name},
	#resource{name = NameB,
			description = <<"Index Table">>,
			category = <<"Index">>,
			version = <<"1.0">>,
			specification = SpecRef}.

static_prefix_table(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:prefix_table_spec_id(),
	SpecRef = #resource_spec_ref{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"PrefixTable">>},
	#resource{name = NameB,
			description = <<"Prefix Table">>,
			category = <<"Prefix">>,
			version = <<"1.0">>,
			specification = SpecRef}.

dynamic_prefix_table(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecRef = #resource_spec_ref{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name},
	#resource{name = NameB,
			description = <<"Prefix Table">>,
			category = <<"Prefix">>,
			version = <<"1.0">>,
			specification = SpecRef}.

static_range_table(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:prefix_range_table_spec_id(),
	SpecRef = #resource_spec_ref{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"PrefixRangeTable">>},
	#resource{name = NameB,
			description = <<"Range Table">>,
			category = <<"Prefix">>,
			version = <<"1.0">>,
			specification = SpecRef}.

static_index_row(Name, Table, Key, Value)
		when is_list(Name), is_list(Key), is_list(Value) ->
	NameB = list_to_binary(Name),
	KeyB = list_to_binary(Key),
	ValueB = list_to_binary(Value),
	SpecId = cse_rest_res_resource:index_row_spec_id(),
	SpecRef = #resource_spec_ref{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"IndexRow">>},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"key">>, value = KeyB},
	Column2 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Index Row">>,
			category = <<"Index">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"key">> => Column1, <<"value">> => Column2}}.

dynamic_index_row(Name, RowSpec, Table, Key, Value)
		when is_list(Name), is_list(Key), is_list(Value) ->
	KeyB = list_to_binary(Key),
	ValueB = list_to_binary(Value),
	NameB = list_to_binary(Name),
	SpecRef = #resource_spec_ref{id = RowSpec#resource_spec.id,
			href = RowSpec#resource_spec.href,
			name = RowSpec#resource_spec.name},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"index">>, value = KeyB},
	Column2 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Index Row">>,
			category = <<"Index">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"key">> => Column1, <<"value">> => Column2}}.

static_prefix_row(Name, Table, Prefix, Value)
		when is_list(Name), is_list(Prefix), is_list(Value) ->
	NameB = list_to_binary(Name),
	PrefixB = list_to_binary(Prefix),
	ValueB = list_to_binary(Value),
	SpecId = cse_rest_res_resource:prefix_row_spec_id(),
	SpecRef = #resource_spec_ref{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"PrefixRow">>},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"prefix">>, value = PrefixB},
	Column2 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Prefix Row">>,
			category = <<"Prefix">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"prefix">> => Column1, <<"value">> => Column2}}.

dynamic_prefix_row(Name, RowSpec, Table, Prefix, Value)
		when is_list(Name), is_list(Prefix), is_list(Value) ->
	NameB = list_to_binary(Name),
	PrefixB = list_to_binary(Prefix),
	ValueB = list_to_binary(Value),
	SpecRef = #resource_spec_ref{id = RowSpec#resource_spec.id,
			href = RowSpec#resource_spec.href,
			name = RowSpec#resource_spec.name},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"prefix">>, value = PrefixB},
	Column2 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Prefix Row">>,
			category = <<"Prefix">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"prefix">> => Column1, <<"value">> => Column2}}.

static_range_row(Name, Table, Start, End, Value)
		when is_list(Name), is_list(Start), is_list(End), is_list(Value) ->
	NameB = list_to_binary(Name),
	StartB = list_to_binary(Start),
	EndB = list_to_binary(End),
	ValueB = list_to_binary(Value),
	SpecId = cse_rest_res_resource:prefix_range_row_spec_id(),
	SpecRef = #resource_spec_ref{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"PrefixRangeRow">>},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"start">>, value = StartB},
	Column2 = #characteristic{name = <<"end">>, value = EndB},
	Column3 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Range Row">>,
			category = <<"Prefix">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"start">> => Column1,
					<<"end">> => Column2, <<"value">> => Column3}}.

dynamic_index_table_spec(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	TableId = cse_rest_res_resource:index_table_spec_id(),
	SpecRel = #resource_spec_rel{id = TableId,
			href = iolist_to_binary([?specPath, TableId]),
			name = <<"IndexTable">>,
			rel_type = <<"based">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic index table specification">>,
			category = <<"IndexTable">>,
			version = <<"1.1">>,
			related = [SpecRel]}.

dynamic_index_row_spec(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	StaticRowId = cse_rest_res_resource:index_row_spec_id(),
	SpecRel1 = #resource_spec_rel{id = StaticRowId,
			href = iolist_to_binary([?specPath, StaticRowId]),
			name = <<"IndexRow">>,
			rel_type = <<"based">>},
	SpecRel2 = #resource_spec_rel{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name,
			rel_type = <<"contained">>},
	Column1 = #resource_spec_char{name = <<"key">>,
			description = <<"Indexed key">>},
	Column2 = #resource_spec_char{name = <<"value">>,
			description = <<"Value for key">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic index table row specification">>,
			category = <<"IndexRow">>,
			version = <<"1.1">>,
			related = [SpecRel1, SpecRel2],
			characteristic = [Column1, Column2]}.

dynamic_prefix_table_spec(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	TableId = cse_rest_res_resource:prefix_table_spec_id(),
	SpecRel = #resource_spec_rel{id = TableId,
			href = iolist_to_binary([?specPath, TableId]),
			name = <<"PrefixTable">>,
			rel_type = <<"based">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic table specification">>,
			category = <<"PrefixTable">>,
			version = <<"1.1">>,
			related = [SpecRel]}.

dynamic_prefix_row_spec(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	StaticRowId = cse_rest_res_resource:prefix_row_spec_id(),
	SpecRel1 = #resource_spec_rel{id = StaticRowId,
			href = iolist_to_binary([?specPath, StaticRowId]),
			name = <<"PrefixRow">>,
			rel_type = <<"based">>},
	SpecRel2 = #resource_spec_rel{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name,
			rel_type = <<"contained">>},
	Column1 = #resource_spec_char{name = <<"prefix">>,
			description = <<"Prefix to match">>,
			value_type = <<"String">>},
	Column2 = #resource_spec_char{name = <<"value">>,
			description = <<"Value returned from prefix match">>,
			value_type = <<"Integer">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic table row specification">>,
			category = <<"PrefixRow">>,
			version = <<"1.1">>,
			related = [SpecRel1, SpecRel2],
			characteristic = [Column1, Column2]}.

is_resource_spec(#{"id" := Id, "href" := Href, "name" := Name,
		"description" := Description, "version" := Version,
		"lastUpdate" := LastUpdate, "category" := Category,
		"resourceSpecRelationship" := Rels,
		"resourceSpecCharacteristic" := Chars})
		when is_list(Id), is_list(Href), is_list(Name), is_list(Description),
		is_list(Version), is_list(LastUpdate), is_list(Category),
		is_list(Rels), is_list(Chars) ->
	true = lists:all(fun is_resource_spec_rel/1, Rels),
	lists:all(fun is_resource_spec_char/1, Chars);
is_resource_spec(#{"id" := Id, "href" := Href, "name" := Name,
		"description" := Description, "version" := Version,
		"lastUpdate" := LastUpdate, "category" := Category})
		when is_list(Id), is_list(Href), is_list(Name), is_list(Description),
		is_list(Version), is_list(LastUpdate), is_list(Category) ->
	true;
is_resource_spec(_S) ->
	false.

is_resource_spec_rel(#{"id" := Id, "href" := Href, "name" := Name,
		"relationshipType" := RelType}) when is_list(Id), is_list(Href),
		is_list(Name), is_list(RelType) ->
	true;
is_resource_spec_rel(_R) ->
	false.

is_resource_spec_char(#{"name" := Name, "description" := Des})
		when is_list(Name), is_list(Des) ->
	true;
is_resource_spec_char(_C) ->
	false.

