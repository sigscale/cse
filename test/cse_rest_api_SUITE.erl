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
-export([resource_spec_add/0, resource_spec_add/1,
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
		add_range_row_resource/0, add_range_row_resource/1]).

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
	ok = cse_test_lib:init_tables(),
	ok = cse_test_lib:start(),
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
	[resource_spec_add, resource_spec_retrieve_static,
			resource_spec_retrieve_dynamic, resource_spec_delete_static,
			resource_spec_delete_dynamic, resource_spec_query_based,
			add_static_table_resource, add_dynamic_table_resource,
			add_static_row_resource, add_dynamic_row_resource,
			get_resource, query_resource, delete_static_table_resource,
			delete_dynamic_table_resource, delete_row_resource,
			add_range_row_resource].

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
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	TableId = integer_to_list(TS) ++ "-" ++ integer_to_list(N),
	ResourceSpec = row_resource_spec(Name, TableId, "RangeTable1"),
	RequestBody = zj:encode(cse_rest_res_resource:resource_spec(ResourceSpec)),
	Request = {HostUrl ++ ?specPath,
			[Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceSpecMap} = zj:decode(ResponseBody),
	true = is_resource_spec(ResourceSpecMap).

resource_spec_retrieve_static() ->
	[{userdata, [{doc, "Retrieve Static Resource Specifications"}]}].

resource_spec_retrieve_static(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	TableId = cse_rest_res_resource:prefix_table_spec_id(),
	Request1 = {Host ++ ?specPath ++ TableId, [Accept]},
	{ok, Result1} = httpc:request(get, Request1, [], []),
	{{"HTTP/1.1", 200, _}, Headers1, Body1} = Result1,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers1),
	{ok, TableSpec} = zj:decode(Body1),
	RowId = cse_rest_res_resource:prefix_row_spec_id(),
	Request2 = {Host ++ ?specPath ++ RowId, [Accept]},
	{ok, Result2} = httpc:request(get, Request2, [], []),
	{{"HTTP/1.1", 200, _}, Headers2, Body2} = Result2,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers2),
	{ok, RowSpec} = zj:decode(Body2),
	true = lists:all(fun is_resource_spec/1, [TableSpec, RowSpec]).

resource_spec_retrieve_dynamic() ->
	[{userdata, [{doc, "Retrieve  Resource Specification collection"}]}].

resource_spec_retrieve_dynamic(Config) ->
	HostUrl = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Name = "DynamicRowSpec2",
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	TableId = integer_to_list(TS) ++ "-" ++ integer_to_list(N),
	ResourceSpec = row_resource_spec(Name, TableId, "RangeTable2"),
	RequestBody = zj:encode(cse_rest_res_resource:resource_spec(ResourceSpec)),
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
	TableId = cse_rest_res_resource:prefix_table_spec_id(),
	Request = {Host ++ ?specPath ++ TableId, [Accept]},
	{ok, Result} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 405, _BadRequest}, _Headers, _Body} = Result.

resource_spec_delete_dynamic() ->
	[{userdata, [{doc,"Delete Dynamic Resource Specification"}]}].

resource_spec_delete_dynamic(Config) ->
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	ResourceSpec = table_resource_spec("DynamicTableSpec1"),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(ResourceSpec),
	Request = {Host ++ ?specPath ++ Id, [Accept]},
	{ok, Result1} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers1, []} = Result1,
	{ok, Result2} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers2, _Response} = Result2.

resource_spec_query_based() ->
	[{userdata, [{doc,"Query Resource Specifications based on"
			"resource specification relathioship type"}]}].

resource_spec_query_based(Config) ->
	Host = ?config(host, Config),
	TableName = "DynamicTableSpec2",
	ResTableSpec = table_resource_spec(TableName),
	{ok, #resource_spec{id = TableId}} = cse:add_resource_spec(ResTableSpec),
	ResRowSpec = row_resource_spec("DynamicRowSpec3", TableId, TableName),
	{ok, #resource_spec{}} = cse:add_resource_spec(ResRowSpec),
	Accept = {"accept", "application/json"},
	Filter = "resourceSpecRelationship[?(@.relationshipType=='based')]",
	Request = {Host ++ lists:droplast(?specPath)
			++ "?filter=" ++ ?QUOTE(Filter), [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(Body)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, ResSpecs} = zj:decode(Body),
	true = length(ResSpecs) >= 2,
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
	[{userdata, [{doc,"Add prefix table resource in rest interface"}]}].

add_static_table_resource(Config) ->
	TableName = "examplePrefixTable",
	Options = [{disc_copies, [node() | nodes()]}],
	{atomic, ok} = mnesia:create_table(list_to_atom(TableName), Options ++
			[{attributes, record_info(fields, gtt)}, {record_name, gtt}]),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Resource = static_prefix_table(TableName),
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{} = ResourceMap} = zj:decode(ResponseBody),
	true = is_resource(ResourceMap).

add_dynamic_table_resource() ->
	[{userdata, [{doc,"Add dynamic prefix table resource"}]}].

add_dynamic_table_resource(Config) ->
	TableName = "examplePrefixTable3",
	Options = [{disc_copies, [node() | nodes()]}],
	{atomic, ok} = mnesia:create_table(list_to_atom(TableName), Options ++
			[{attributes, record_info(fields, gtt)}, {record_name, gtt}]),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Resource = dynamic_prefix_table(TableName),
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result} = httpc:request(post, Request, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers, ResponseBody} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(ResponseBody)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, #{"id" := Id} = ResourceMap} = zj:decode(ResponseBody),
	true = is_resource(ResourceMap),
	{ok, #resource{id = Id}} = cse:find_resource(Id).

add_static_row_resource() ->
	[{userdata, [{doc,"Add prefix row resource in rest interface"}]}].

add_static_row_resource(Config) ->
	TableName = "examplePrefixTable2",
	cse_gtt:new(TableName, []),
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	TableRes = #resource{name = TableName,
			description = TableName ++ " prefix table",
			specification = #resource_spec_ref{id = TableSpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ TableSpecId,
					name = "PrefixTable"}},
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	RowRes = static_prefix_row(TableId, TableName),
	RequestBody = zj:encode(cse_rest_res_resource:resource(RowRes)),
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
	TableName = "sampleDynamicTable",
	Options = [{disc_copies, [node() | nodes()]}],
	{atomic, ok} = mnesia:create_table(list_to_atom(TableName), Options ++
			[{attributes, record_info(fields, gtt)}, {record_name, gtt}]),
	TableRes = dynamic_prefix_table(TableName),
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Resource = dynamic_prefix_row("sampleDynamicRow", TableId, TableName),
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
	#resource_char{value = Prefix}
			= lists:keyfind("prefix", #resource_char.name, Chars),
	#resource_char{value = Value}
			= lists:keyfind("value", #resource_char.name, Chars),
	Value = cse_gtt:lookup_first(TableName, Prefix).

get_resource() ->
	[{userdata, [{doc, "Retrieve Prefix Resource"}]}].

get_resource(Config) ->
	TableName = "tempPrefixTable",
	cse_gtt:new(TableName, []),
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	TableRes = #resource{name = TableName,
			description = TableName ++ " prefix table",
			specification = #resource_spec_ref{id = TableSpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ TableSpecId,
					name = "PrefixTable"}},
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	PrefixRow = static_prefix_row(TableId, TableName),
	{ok, #resource{id = Id}}= cse:add_resource(PrefixRow),
	Request = {Host ++ ?inventoryPath ++ Id, [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	{ok, Resource} = zj:decode(Body),
	true = is_resource(Resource).

query_resource() ->
	[{userdata, [{doc,"Query Resource collection"}]}].

query_resource(Config) ->
	TableName = "testPrefixTable",
	cse_gtt:new(TableName, []),
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	TableRes = #resource{name = TableName,
			description = TableName ++ " prefix table",
			specification = #resource_spec_ref{id = TableSpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ TableSpecId,
					name = "PrefixTable"}},
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	{ok, #resource{}} = cse:add_resource(static_prefix_row(TableId, TableName)),
	Res = static_prefix_row(TableId, TableName),
	PrefixRow2 = Res#resource{name = "testPrefixRow",
			characteristic = [#resource_char{name = "prefix", value = "14736"},
					#resource_char{name = "value", value = "testing"}]},
	{ok, #resource{}} = cse:add_resource(PrefixRow2),
	SpecId = cse_rest_res_resource:prefix_row_spec_id(),
	Accept = {"accept", "application/json"},
	Filter = "resourceRelationship[?(@.resource.name=='" ++ TableName ++ "')]",
	Query = "?resourceSpecification.id=" ++ SpecId
			++ "&filter=" ++ ?QUOTE(Filter),
	Request = {Host ++ lists:droplast(?inventoryPath) ++ Query, [Accept]},
	{ok, Result} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 200, _OK}, Headers, Body} = Result,
	{_, "application/json"} = lists:keyfind("content-type", 1, Headers),
	ContentLength = integer_to_list(length(Body)),
	{_, ContentLength} = lists:keyfind("content-length", 1, Headers),
	{ok, Resources} = zj:decode(Body),
	true = length(Resources) >= 2,
	F1 = fun(#{"resourceRelationship" := Rels,
			"resourceSpecification" := #{"id" := SId}}) when SId == SpecId ->
		F2 = fun F2([#{"relationshipType" := "contained",
				"resource" := #{"name" := TN}} | _]) when TN == TableName ->
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
	cse_gtt:new(TableName, []),
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	TableRes = #resource{name = TableName,
			description = TableName ++ " prefix table",
			specification = #resource_spec_ref{id = TableSpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ TableSpecId,
					name = "PrefixTable"}},
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	Request = {Host ++ ?inventoryPath ++ TableId, [Accept]},
	{ok, Result1} = httpc:request(delete, Request, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers1, []} = Result1,
	{ok, Result2} = httpc:request(get, Request, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers2, _Response} = Result2.

delete_dynamic_table_resource() ->
	[{userdata, [{doc,"Delete dynamic Resource by its id"}]}].

delete_dynamic_table_resource(Config) ->
	TableName = "tempDynamicTable",
	Options = [{disc_copies, [node() | nodes()]}],
	{atomic, ok} = mnesia:create_table(list_to_atom(TableName), Options ++
			[{attributes, record_info(fields, gtt)}, {record_name, gtt}]),
	TableRes = dynamic_prefix_table(TableName),
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Resource = dynamic_prefix_row("sampleDynamicRow", TableId, TableName),
	RequestBody = zj:encode(cse_rest_res_resource:resource(Resource)),
	Request1 = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result1} = httpc:request(post, Request1, [], []),
	{{"HTTP/1.1", 201, _Created}, _Headers1, _ResponseBody} = Result1,
	Request2 = {Host ++ ?inventoryPath ++ TableId, [Accept]},
	{ok, Result2} = httpc:request(delete, Request2, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers2, []} = Result2,
	{ok, Result3} = httpc:request(get, Request2, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers3, _Response} = Result3,
	0 = mnesia:table_info('tempDynamicTable', size).

delete_row_resource() ->
	[{userdata, [{doc,"Delete Resource by its id"}]}].

delete_row_resource(Config) ->
	TableName = "samplePrefixTable2",
	cse_gtt:new(TableName, []),
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	TableRes = #resource{name = TableName,
			description = TableName ++ " prefix table",
			specification = #resource_spec_ref{id = TableSpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ TableSpecId,
					name = "PrefixTable"}},
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	Accept = {"accept", "application/json"},
	ContentType = "application/json",
	PrefixRow = static_prefix_row("samplePrefixRow", TableId, TableName),
	RequestBody = zj:encode(cse_rest_res_resource:resource(PrefixRow)),
	Request1 = {Host ++ ?inventoryPath, [Accept], ContentType, RequestBody},
	{ok, Result1} = httpc:request(post, Request1, [], []),
	{{"HTTP/1.1", 201, _Created}, Headers1, _ResponseBody} = Result1,
	{_, URI} = lists:keyfind("location", 1, Headers1),
	{?inventoryPath ++ Id, _} = httpd_util:split_path(URI),
	Request2 = {Host ++ ?inventoryPath ++ Id, [Accept]},
	{ok, Result2} = httpc:request(delete, Request2, [], []),
	{{"HTTP/1.1", 204, _NoContent}, _Headers2, []} = Result2,
	{ok, Result3} = httpc:request(get, Request2, [], []),
	{{"HTTP/1.1", 404, "Object Not Found"}, _Headers3, _Response} = Result3,
	Chars = PrefixRow#resource.characteristic,
	#resource_char{value = Prefix}
			= lists:keyfind("prefix", #resource_char.name, Chars),
	undefined = cse_gtt:lookup_first(TableName, Prefix).

add_range_row_resource() ->
	[{userdata, [{doc,"Add dynamic prefix row resource"}]}].

add_range_row_resource(Config) ->
	TableName = 'sampleRangeTable',
	StringTableName = atom_to_list(TableName),
	ok = cse_gtt:new(TableName, []),
	TableRes = range_table(StringTableName),
	{ok, #resource{id = TableId}} = cse:add_resource(TableRes),
	Host = ?config(host, Config),
	ContentType = "application/json",
	Accept = {"accept", "application/json"},
	Start = "14789",
	End = "98741",
	Resource = range_row("sampleRangeRow", TableId, StringTableName, Start, End),
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
				F1(cse_gtt:list(Cont, TableName), [Gtts | Acc])
	end,
	RangeGtts = F1(cse_gtt:list(start, TableName), []),
	Prefixes = cse_gtt:range(Start, End),
	F2 = fun(Prefix) ->
			case lists:keyfind(Prefix, #gtt.num, RangeGtts) of
				#gtt{num = Prefix} ->
					true;
				false ->
					false
			end
	end,
	true = lists:all(F2, Prefixes).

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

static_prefix_table(Name) ->
	SpecId = cse_rest_res_resource:prefix_table_spec_id(),
	#resource{name = Name, description = "Prefix Table", category = "Prefix",
			base_type = "Resource", version = "1.0",
			specification = #resource_spec_ref{id = SpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ SpecId,
					name = "PrefixTable"}}.

dynamic_prefix_table(Name) ->
	SpecName = "sampleDynamicResSpec",
	Spec = table_resource_spec(SpecName),
	{ok, #resource_spec{id = SpecId}} = cse:add_resource_spec(Spec),
	#resource{name = Name, description = "Prefix Table", category = "Prefix",
			base_type = "Resource", version = "1.0",
			specification = #resource_spec_ref{id = SpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ SpecId,
					name = SpecName}}.

range_table(Name) ->
	SpecId = cse_rest_res_resource:prefix_range_table_spec_id(),
	#resource{name = Name, description = "Range Table", category = "Prefix",
			base_type = "Resource", version = "1.0",
			specification = #resource_spec_ref{id = SpecId,
					href = "/resourceCatalogManagement/v4/resourceSpecification/"
							++ SpecId,
					name = "PrefixRangeTable"}}.

static_prefix_row(TableId, TableName) ->
	static_prefix_row("examplePrefixRow", TableId, TableName).
static_prefix_row(Name, TableId, TableName) ->
	SpecId = cse_rest_res_resource:prefix_row_spec_id(),
	#resource{name = Name, description = "Prefix Row",
			category = "Prefix", base_type = "Resource", version = "1.0",
			related = [#resource_rel{id = TableId,
					href = "/resourceInventoryManagement/v4/resource/"
					++ TableId, name = TableName, rel_type = "contained"}],
			specification = #resource_spec_ref{id = SpecId,
					href = "/resourceCatalogManagement/v2/resourceSpecification/"
							++ SpecId,
					name = "PrefixRow"},
			characteristic = [#resource_char{name = "prefix", value = "15796"},
					#resource_char{name = "value", value = "hello world"}]}.

dynamic_prefix_row(Name, TableId, TableName) ->
	TableSpecName = "tempDynamicResSpec",
	TableSpec = table_resource_spec(TableSpecName),
	{ok, #resource_spec{id = TableSpecId}}
			= cse:add_resource_spec(TableSpec),
	SpecName = "sampleDynamicRowResSpec",
	Spec = row_resource_spec(SpecName, TableSpecId, TableSpecName),
	{ok, #resource_spec{id = SpecId}} = cse:add_resource_spec(Spec),
	#resource{name = Name, description = "Prefix Row",
			category = "Prefix", base_type = "Resource", version = "1.0",
			related = [#resource_rel{id = TableId,
					href = "/resourceInventoryManagement/v4/resource/"
					++ TableId, name = TableName, rel_type = "contained"}],
			specification = #resource_spec_ref{id = SpecId,
					href = "/resourceCatalogManagement/v2/resourceSpecification/"
							++ SpecId,
					name = SpecName},
			characteristic = [#resource_char{name = "prefix", value = "46892"},
					#resource_char{name = "value", value = 64}]}.

%% @hidden
range_row(Name, TableId, TableName, Start, End) ->
	SpecId = cse_rest_res_resource:prefix_range_row_spec_id(),
	#resource{name = Name, description = "Range Row",
			category = "Prefix", base_type = "Resource", version = "1.0",
			related = [#resource_rel{id = TableId,
					href = "/resourceInventoryManagement/v4/resource/"
					++ TableId, name = TableName, rel_type = "contained"}],
			specification = #resource_spec_ref{id = SpecId,
					href = "/resourceCatalogManagement/v2/resourceSpecification/"
							++ SpecId,
					name = "PrefixRangeRow"},
			characteristic = [#resource_char{name = "start", value = Start},
					#resource_char{name = "end", value = End},
					#resource_char{name = "value", value = "hello range"}]}.

row_resource_spec(Name, TableId, TableName) ->
	StaticRowId = cse_rest_res_resource:prefix_row_spec_id(),
	#resource_spec{name = Name,
			description = "Dynamic table row specification",
			version = "1.1",
			status = "active",
			category = "DynamicPrefixRow",
			related = [#resource_spec_rel{id = TableId,
					href = ?specPath ++ TableId, name = TableName,
					rel_type = "contained"},
				#resource_spec_rel{id = StaticRowId,
					href = ?specPath ++ StaticRowId,
					name = "PrefixRow", rel_type = "based"}],
			characteristic = [#resource_spec_char{name = "prefix",
					description = "Prefix to match",
					value_type = "String"},
				#resource_spec_char{name = "value",
					description = "Value returned from prefix match",
					value_type = "Integer"}]}.

table_resource_spec(Name) ->
	TableId = cse_rest_res_resource:prefix_table_spec_id(),
	#resource_spec{name = Name,
			description = "Dynamic table specification",
			version = "1.1",
			status = "active",
			category = "DynamicPrefixTable",
			related = [#resource_spec_rel{id = TableId,
					href = ?specPath ++ TableId,
					name = "PrefixTable", rel_type = "based"}]}.

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

