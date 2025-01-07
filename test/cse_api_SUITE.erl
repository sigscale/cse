%%% cse_api_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2026 SigScale Global Inc.
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
%%% Test suite for the public API of the {@link //cse. cse} application.
%%%
-module(cse_api_SUITE).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([start_cse/0, start_cse/1, stop_cse/0, stop_cse/1]).
-export([add_service/0, add_service/1,
		get_service/0, get_service/1,
		find_service/0, find_service/1,
		get_services/0, get_services/1,
		delete_service/0, delete_service/1,
		add_context/0, add_context/1,
		get_context/0, get_context/1,
		find_context/0, find_context/1,
		get_contexts/0, get_contexts/1,
		delete_context/0, delete_context/1,
		no_service/0, no_service/1]).
-export([announce/0, announce/1]).
-export([add_index_table_spec/0, add_index_table_spec/1,
		add_prefix_table_spec/0, add_prefix_table_spec/1,
		add_range_table_spec/0, add_range_table_spec/1,
		get_index_table_spec/0, get_index_table_spec/1,
		get_prefix_table_spec/0, get_prefix_table_spec/1,
		get_range_table_spec/0, get_range_table_spec/1,
		delete_index_table_spec/0, delete_index_table_spec/1,
		delete_prefix_table_spec/0, delete_prefix_table_spec/1,
		delete_range_table_spec/0, delete_range_table_spec/1,
		add_index_table/0, add_index_table/1,
		add_prefix_table/0, add_prefix_table/1,
		add_range_table/0, add_range_table/1,
		get_index_table/0, get_index_table/1,
		get_prefix_table/0, get_prefix_table/1,
		get_range_table/0, get_range_table/1,
		delete_index_table/0, delete_index_table/1,
		delete_prefix_table/0, delete_prefix_table/1,
		delete_range_table/0, delete_range_table/1,
		add_index_row_spec/0, add_index_row_spec/1,
		add_prefix_row_spec/0, add_prefix_row_spec/1,
		add_range_row_spec/0, add_range_row_spec/1,
		get_index_row_spec/0, get_index_row_spec/1,
		get_prefix_row_spec/0, get_prefix_row_spec/1,
		get_range_row_spec/0, get_range_row_spec/1,
		delete_index_row_spec/0, delete_index_row_spec/1,
		delete_prefix_row_spec/0, delete_prefix_row_spec/1,
		delete_range_row_spec/0, delete_range_row_spec/1,
		add_index_row/0, add_index_row/1,
		add_prefix_row/0, add_prefix_row/1,
		add_range_row/0, add_range_row/1,
		get_index_row/0, get_index_row/1,
		get_index_row_extra/0, get_index_row_extra/1,
		get_prefix_row/0, get_prefix_row/1,
		get_range_row/0, get_range_row/1,
		delete_index_row/0, delete_index_row/1,
		delete_prefix_row/0, delete_prefix_row/1,
		delete_range_row/0, delete_range_row/1]).

-include("cse.hrl").
-include_lib("common_test/include/ct.hrl").

-define(specPath, "/resourceCatalogManagement/v4/resourceSpecification/").
-define(inventoryPath, "/resourceInventoryManagement/v4/resource/").

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
	ok = cse_test_lib:start([diameter, inets, snmp, sigscale_mibs, m3ua, tcap, gtt]),
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = cse_test_lib:stop().

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
%%
init_per_testcase(start_cse, Config) ->
	Config;
init_per_testcase(_TestCase, Config) ->
	ok = cse:start(),
   Config.

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(stop_cse, _Config) ->
	ok;
end_per_testcase(_TestCase, _Config) ->
	ok = cse:stop().

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[start_cse, stop_cse, add_service, find_service, get_services,
			delete_service, add_context, get_context, find_context,
			get_contexts, delete_context, no_service, announce,
			add_index_table_spec, add_prefix_table_spec, add_range_table_spec,
			get_index_table_spec, get_prefix_table_spec, get_range_table_spec,
			delete_index_table_spec, delete_prefix_table_spec, delete_range_table_spec,
			add_index_table, add_prefix_table, add_range_table,
			get_index_table, get_prefix_table, get_range_table,
			delete_index_table, delete_prefix_table, delete_range_table,
			add_index_row_spec, add_prefix_row_spec, add_range_row_spec,
			get_index_row_spec, get_prefix_row_spec, get_range_row_spec,
			delete_index_row_spec, delete_prefix_row_spec, delete_range_row_spec,
			add_index_row, add_prefix_row, add_range_row,
			get_index_row, get_index_row_extra, get_prefix_row, get_range_row,
			delete_index_row, delete_prefix_row, delete_range_row].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

start_cse() ->
	[{userdata, [{doc, "Start the CAMEL Service Enviromnment (CSE)"}]}].

start_cse(_Config) ->
	ok = cse:start().

stop_cse() ->
	[{userdata, [{doc, "Stop the CAMEL Service Enviromnment (CSE)"}]}].

stop_cse(_Config) ->
	ok = cse:stop().

add_service() ->
	[{userdata, [{doc, "Add an IN service logic processing program (SLP)"}]}].

add_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	Module = cse_slp_prepaid_cap_fsm,
	Data = #{edp => edp()},
	Opts = [],
	ok = cse:add_service(ServiceKey, Module, Data, Opts).

get_service() ->
	[{userdata, [{doc, "Get an IN service logic processing program (SLP)"}]}].

get_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	Module = cse_slp_prepaid_cap_fsm,
	Data = #{edp => edp()},
	Opts = [],
	cse:add_service(ServiceKey, Module, Data, Opts),
	#in_service{key = ServiceKey, module = Module,
			data = Data, opts = Opts} = cse:get_service(ServiceKey).

find_service() ->
	[{userdata, [{doc, "Find an IN service logic processing program (SLP)"}]}].

find_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	Module = cse_slp_prepaid_cap_fsm,
	Data = #{edp => edp()},
	Opts = [],
	cse:add_service(ServiceKey, Module, Data, Opts),
	{ok, Service} = cse:find_service(ServiceKey),
	#in_service{key = ServiceKey, module = Module,
			data = Data, opts = Opts} = Service.

get_services() ->
	[{userdata, [{doc, "List all IN service logic processing programs (SLP)"}]}].

get_services(_Config) ->
	cse:add_service(rand:uniform(2147483647), cse_slp_prepaid_inap_fsm, #{}, []),
	cse:add_service(rand:uniform(2147483647), cse_slp_prepaid_inap_fsm, #{}, []),
	cse:add_service(rand:uniform(2147483647), cse_slp_prepaid_inap_fsm, #{}, []),
	F = fun(S) -> is_record(S, in_service) end,
	lists:all(F, cse:get_services()).

delete_service() ->
	[{userdata, [{doc, "Remove an IN service logic processing program (SLP)"}]}].

delete_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	cse:add_service(ServiceKey, cse_slp_prepaid_cap_fsm, #{}, []),
	ok = cse:delete_service(ServiceKey).

add_context() ->
	[{userdata, [{doc, "Add a DIAMETER logic processing program (SLP)"}]}].

add_context(_Config) ->
	ContextId = list_to_binary(cse_test_lib:rand_name(20)),
	Module = cse_slp_prepaid_diameter_ims_fsm,
	ok = cse:add_context(ContextId, Module, [], []).

get_context() ->
	[{userdata, [{doc, "Get a DIAMETER SLP"}]}].

get_context(_Config) ->
	ContextId = list_to_binary(cse_test_lib:rand_name(20)),
	Module = cse_slp_prepaid_diameter_ims_fsm,
	cse:add_context(ContextId, Module, [], []),
	#diameter_context{id = ContextId, module = Module,
			args = [], opts = []} = cse:get_context(ContextId).

find_context() ->
	[{userdata, [{doc, "Find a DIAMETER SLP"}]}].

find_context(_Config) ->
	ContextId = list_to_binary(cse_test_lib:rand_name(20)),
	Module = cse_slp_prepaid_diameter_ims_fsm,
	cse:add_context(ContextId, Module, [], []),
	{ok, Context} = cse:find_context(ContextId),
	#diameter_context{id = ContextId, module = Module,
			args = [], opts = []} = Context.

get_contexts() ->
	[{userdata, [{doc, "List all DIAMETER contexts"}]}].

get_contexts(_Config) ->
	Module = cse_slp_prepaid_diameter_ims_fsm,
	cse:add_context(list_to_binary(cse_test_lib:rand_name(20)), Module, [], []),
	cse:add_context(list_to_binary(cse_test_lib:rand_name(20)), Module, [], []),
	cse:add_context(list_to_binary(cse_test_lib:rand_name(20)), Module, [], []),
	F = fun(S) -> is_record(S, diameter_context) end,
	lists:all(F, cse:get_contexts()).

delete_context() ->
	[{userdata, [{doc, "Remove a DIAMETER SLP"}]}].

delete_context(_Config) ->
	ContextId = list_to_binary(cse_test_lib:rand_name(20)),
	Module = cse_slp_prepaid_diameter_ims_fsm,
	cse:add_context(ContextId, Module, [], []),
	ok = cse:delete_context(ContextId).

no_service() ->
	[{userdata, [{doc, "Attempt to find a non-existent SLP"}]}].

no_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	{error, not_found} = cse:find_service(ServiceKey).

announce() ->
	[{userdata, [{doc, "Make announcement word list"}]}].

announce(_Config) ->
	Amount = rand:uniform(1000000000000),
	Words = [zero, one, two, three, four, five, six, seven,
			eight, nine, ten, eleven, twelve, thirteen, fourteen,
			fifteen, sixteen, seventeen, eighteen, nineteen,
			twenty, thirty, forty, fifty, sixty, seventy, eighty,
			ninety, hundred, thousand, million, billion, trillion,
			dollar, dollars, cent, cents, 'and', negative],
	F = fun(Word) ->
			lists:member(Word, Words)
	end,
	lists:all(F, cse:announce(Amount)).

add_index_table_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for an index table"}]}].

add_index_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_index_table_spec(Name),
	{ok, _} = cse:add_resource_spec(Specification).

add_prefix_table_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for a prefix table"}]}].

add_prefix_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	NameB = list_to_binary(Name),
	Specification = dynamic_prefix_table_spec(Name),
	{ok, #resource_spec{name = NameB}} = cse:add_resource_spec(Specification).

add_range_table_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for a prefix range table"}]}].

add_range_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	NameB = list_to_binary(Name),
	Specification = dynamic_range_table_spec(Name),
	{ok, #resource_spec{name = NameB}} = cse:add_resource_spec(Specification).

get_index_table_spec() ->
	[{userdata, [{doc, "Get a dynamic index table Resource Specification"}]}].

get_index_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_index_table_spec(Name),
	{ok, #resource_spec{id = Id} = RS} = cse:add_resource_spec(Specification),
	{ok, RS} = cse:find_resource_spec(Id).

get_prefix_table_spec() ->
	[{userdata, [{doc, "Get a dynamic prefix table Resource Specification"}]}].

get_prefix_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_prefix_table_spec(Name),
	{ok, #resource_spec{id = Id} = RS} = cse:add_resource_spec(Specification),
	{ok, RS} = cse:find_resource_spec(Id).

get_range_table_spec() ->
	[{userdata, [{doc, "Get a dynamic prefix range table Resource Specification"}]}].

get_range_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_range_table_spec(Name),
	{ok, #resource_spec{id = Id} = RS} = cse:add_resource_spec(Specification),
	{ok, RS} = cse:find_resource_spec(Id).

delete_index_table_spec() ->
	[{userdata, [{doc, "Delete a dynamic index table Resource Specification"}]}].

delete_index_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_index_table_spec(Name),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(Specification),
	ok = cse:delete_resource_spec(Id),
	{error, not_found} = cse:find_resource_spec(Id).

delete_prefix_table_spec() ->
	[{userdata, [{doc, "Delete a dynamic prefix table Resource Specification"}]}].

delete_prefix_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_prefix_table_spec(Name),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(Specification),
	ok = cse:delete_resource_spec(Id),
	{error, not_found} = cse:find_resource_spec(Id).

delete_range_table_spec() ->
	[{userdata, [{doc, "Delete a dynamic prefix range table Resource Specification"}]}].

delete_range_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_range_table_spec(Name),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(Specification),
	ok = cse:delete_resource_spec(Id),
	{error, not_found} = cse:find_resource_spec(Id).

add_index_table() ->
	[{userdata, [{doc, "Add a Resource for an index table"}]}].

add_index_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	NameB = list_to_binary(Name),
	SpecificationT = dynamic_index_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_index_table(Name, SpecificationR),
	ok = new_index_table(Name, []),
	{ok, #resource{name = NameB}} = cse:add_resource(ResourceT).

add_prefix_table() ->
	[{userdata, [{doc, "Add a Resource for a prefix table"}]}].

add_prefix_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	NameB = list_to_binary(Name),
	SpecificationT = dynamic_prefix_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_prefix_table(Name, SpecificationR),
	ok = cse_gtt:new(Name, []),
	{ok, #resource{name = NameB}} = cse:add_resource(ResourceT).

add_range_table() ->
	[{userdata, [{doc, "Add a Resource for a prefix range table"}]}].

add_range_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	NameB = list_to_binary(Name),
	SpecificationT = dynamic_range_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_range_table(Name, SpecificationR),
	ok = cse_gtt:new(Name, []),
	{ok, #resource{name = NameB}} = cse:add_resource(ResourceT).

get_index_table() ->
	[{userdata, [{doc, "Get a Resource for an index table"}]}].

get_index_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	SpecificationT = dynamic_index_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_index_table(Name, SpecificationR),
	ok = new_index_table(Name, []),
	{ok, #resource{id = Id} = ResourceR} = cse:add_resource(ResourceT),
	{ok, ResourceR} = cse:find_resource(Id).

get_prefix_table() ->
	[{userdata, [{doc, "Get a Resource for a prefix table"}]}].

get_prefix_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	SpecificationT = dynamic_prefix_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_prefix_table(Name, SpecificationR),
	ok = cse_gtt:new(Name, []),
	{ok, #resource{id = Id} = ResourceR} = cse:add_resource(ResourceT),
	{ok, ResourceR} = cse:find_resource(Id).

get_range_table() ->
	[{userdata, [{doc, "Get a Resource for a prefix range table"}]}].

get_range_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	SpecificationT = dynamic_range_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_range_table(Name, SpecificationR),
	ok = cse_gtt:new(Name, []),
	{ok, #resource{id = Id} = ResourceR} = cse:add_resource(ResourceT),
	{ok, ResourceR} = cse:find_resource(Id).

delete_index_table() ->
	[{userdata, [{doc, "Delete a Resource for an index table"}]}].

delete_index_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	SpecificationT = dynamic_index_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_index_table(Name, SpecificationR),
	ok = new_index_table(Name, []),
	{ok, #resource{id = Id}} = cse:add_resource(ResourceT),
	ok = cse:delete_resource(Id),
	{error, not_found} = cse:find_resource(Id).

delete_prefix_table() ->
	[{userdata, [{doc, "Delete a Resource for a prefix table"}]}].

delete_prefix_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	SpecificationT = dynamic_prefix_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_prefix_table(Name, SpecificationR),
	ok = cse_gtt:new(Name, []),
	{ok, #resource{id = Id}} = cse:add_resource(ResourceT),
	ok = cse:delete_resource(Id),
	{error, not_found} = cse:find_resource(Id).

delete_range_table() ->
	[{userdata, [{doc, "Delete a Resource for a prefix range table"}]}].

delete_range_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	SpecificationT = dynamic_range_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_range_table(Name, SpecificationR),
	ok = cse_gtt:new(Name, []),
	{ok, #resource{id = Id}} = cse:add_resource(ResourceT),
	ok = cse:delete_resource(Id),
	{error, not_found} = cse:find_resource(Id).

add_index_row_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for an index table row"}]}].

add_index_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, _RowSpecR} = cse:add_resource_spec(RowSpecT).

add_prefix_row_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for a prefix table row"}]}].

add_prefix_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_prefix_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_prefix_row_spec(Name, TableSpecR),
	{ok, _RowSpecR} = cse:add_resource_spec(RowSpecT).

add_range_row_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for a prefix range table row"}]}].

add_range_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_range_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_range_row_spec(Name, TableSpecR),
	{ok, _RowSpecR} = cse:add_resource_spec(RowSpecT).

get_index_row_spec() ->
	[{userdata, [{doc, "Get a Resource Specification for an index table row"}]}].

get_index_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, #resource_spec{id = Id} = RowSpecR} = cse:add_resource_spec(RowSpecT),
	{ok, RowSpecR} = cse:find_resource_spec(Id).

get_prefix_row_spec() ->
	[{userdata, [{doc, "Get a Resource Specification for a prefix table row"}]}].

get_prefix_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_prefix_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_prefix_row_spec(Name, TableSpecR),
	{ok, #resource_spec{id = Id} = RowSpecR} = cse:add_resource_spec(RowSpecT),
	{ok, RowSpecR} = cse:find_resource_spec(Id).

get_range_row_spec() ->
	[{userdata, [{doc, "Get a Resource Specification for a prefix range table row"}]}].

get_range_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_range_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_range_row_spec(Name, TableSpecR),
	{ok, #resource_spec{id = Id} = RowSpecR} = cse:add_resource_spec(RowSpecT),
	{ok, RowSpecR} = cse:find_resource_spec(Id).

delete_index_row_spec() ->
	[{userdata, [{doc, "Delete a Resource Specification for an index table row"}]}].

delete_index_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(RowSpecT),
	ok = cse:delete_resource_spec(Id),
	{error, not_found} = cse:find_resource_spec(Id).

delete_prefix_row_spec() ->
	[{userdata, [{doc, "Delete a Resource Specification for a prefix table row"}]}].

delete_prefix_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_prefix_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_prefix_row_spec(Name, TableSpecR),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(RowSpecT),
	ok = cse:delete_resource_spec(Id),
	{error, not_found} = cse:find_resource_spec(Id).

delete_range_row_spec() ->
	[{userdata, [{doc, "Delete a Resource Specification for a prefix range table row"}]}].

delete_range_row_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	TableSpecT = dynamic_range_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_range_row_spec(Name, TableSpecR),
	{ok, #resource_spec{id = Id}} = cse:add_resource_spec(RowSpecT),
	ok = cse:delete_resource_spec(Id),
	{error, not_found} = cse:find_resource_spec(Id).

add_index_row() ->
	[{userdata, [{doc, "Add a Resource for an index table row"}]}].

add_index_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Key = cse_test_lib:rand_dn(10),
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_index_table(Name, TableSpecR),
	ok = new_index_table(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_index_row(Name, RowSpecR, TableR, Key, Value),
	{ok, _RowR} = cse:add_resource(RowT).

add_prefix_row() ->
	[{userdata, [{doc, "Add a Resource for a prefix table row"}]}].

add_prefix_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Prefix = cse_test_lib:rand_dn(8),
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_prefix_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_prefix_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_prefix_table(Name, TableSpecR),
	ok = cse_gtt:new(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_prefix_row(Name, RowSpecR, TableR, Prefix, Value),
	{ok, _RowR} = cse:add_resource(RowT).

add_range_row() ->
	[{userdata, [{doc, "Add a Resource for a prefix range table row"}]}].

add_range_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Prefix = cse_test_lib:rand_dn(6),
	Start = Prefix ++ "000",
	End =  Prefix ++ "999",
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_range_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_range_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_range_table(Name, TableSpecR),
	ok = cse_gtt:new(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_range_row(Name, RowSpecR, TableR, Start, End, Value),
	{ok, _RowR} = cse:add_resource(RowT).

get_index_row() ->
	[{userdata, [{doc, "Get a Resource for an index table row"}]}].

get_index_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Key = cse_test_lib:rand_dn(10),
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_index_table(Name, TableSpecR),
	ok = new_index_table(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_index_row(Name, RowSpecR, TableR, Key, Value),
	{ok, #resource{id = Id} = RowR} = cse:add_resource(RowT),
	{ok, RowR} = cse:find_resource(Id).

get_index_row_extra() ->
	[{userdata, [{doc, "Get a Resource for an index table row with extra characteristics"}]}].

get_index_row_extra(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Key = cse_test_lib:rand_value(),
	KeyChar = #characteristic{name = <<"key">>, value = Key},
	CharMap = char_map(rand:uniform(15)),
	Chars = maps:put(<<"key">>, KeyChar, CharMap),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_index_table(Name, TableSpecR),
	ok = new_index_table(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_index_row_extra(Name, RowSpecR, TableR, Key, Chars),
	{ok, #resource{id = Id} = RowR} = cse:add_resource(RowT),
	{ok, RowR} = cse:find_resource(Id),
	Fmap = fun(_K, C) ->
				C#characteristic.value
	end,
	ValueMap = maps:map(Fmap, CharMap),
	Ftran = fun() ->
				mnesia:read(list_to_existing_atom(Name), Key, read)
	end,
	{atomic, [{_, Key, ValueMap}]} = mnesia:transaction(Ftran).

get_prefix_row() ->
	[{userdata, [{doc, "Get a Resource for a prefix table row"}]}].

get_prefix_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Prefix = cse_test_lib:rand_dn(8),
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_prefix_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_prefix_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_prefix_table(Name, TableSpecR),
	ok = cse_gtt:new(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_prefix_row(Name, RowSpecR, TableR, Prefix, Value),
	{ok, #resource{id = Id} = RowR} = cse:add_resource(RowT),
	{ok, RowR} = cse:find_resource(Id).

get_range_row() ->
	[{userdata, [{doc, "Get a Resource for a prefix range table row"}]}].

get_range_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Prefix = cse_test_lib:rand_dn(6),
	Start = Prefix ++ "000",
	End =  Prefix ++ "999",
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_range_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_range_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_range_table(Name, TableSpecR),
	ok = cse_gtt:new(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_range_row(Name, RowSpecR, TableR, Start, End, Value),
	{ok, #resource{id = Id} = RowR} = cse:add_resource(RowT),
	{ok, RowR} = cse:find_resource(Id).

delete_index_row() ->
	[{userdata, [{doc, "Delete a Resource for an index table row"}]}].

delete_index_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Key = cse_test_lib:rand_dn(10),
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_index_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_index_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_index_table(Name, TableSpecR),
	ok = new_index_table(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_index_row(Name, RowSpecR, TableR, Key, Value),
	{ok, #resource{id = Id}} = cse:add_resource(RowT),
	ok = cse:delete_resource(Id),
	{error, not_found} = cse:find_resource(Id).

delete_prefix_row() ->
	[{userdata, [{doc, "Delete a Resource for a prefix table row"}]}].

delete_prefix_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Prefix = cse_test_lib:rand_dn(8),
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_prefix_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_prefix_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_prefix_table(Name, TableSpecR),
	ok = cse_gtt:new(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_prefix_row(Name, RowSpecR, TableR, Prefix, Value),
	{ok, #resource{id = Id}} = cse:add_resource(RowT),
	ok = cse:delete_resource(Id),
	{error, not_found} = cse:find_resource(Id).

delete_range_row() ->
	[{userdata, [{doc, "Delete a Resource for a prefix range table row"}]}].

delete_range_row(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Prefix = cse_test_lib:rand_dn(6),
	Start = Prefix ++ "000",
	End =  Prefix ++ "999",
	Value = cse_test_lib:rand_name(20),
	TableSpecT = dynamic_range_table_spec(Name),
	{ok, TableSpecR} = cse:add_resource_spec(TableSpecT),
	RowSpecT = dynamic_range_row_spec(Name, TableSpecR),
	{ok, RowSpecR} = cse:add_resource_spec(RowSpecT),
	TableT = dynamic_range_table(Name, TableSpecR),
	ok = cse_gtt:new(Name, []),
	{ok, TableR} = cse:add_resource(TableT),
	RowT = dynamic_range_row(Name, RowSpecR, TableR, Start, End, Value),
	{ok, #resource{id = Id}} = cse:add_resource(RowT),
	ok = cse:delete_resource(Id),
	{error, not_found} = cse:find_resource(Id).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

edp() ->
	#{abandon => notifyAndContinue,
			answer => notifyAndContinue,
			busy => interrupted,
			disconnect1 => interrupted,
			disconnect2 => interrupted,
			no_answer => interrupted,
			route_fail => interrupted}.

dynamic_index_table_spec(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:index_table_spec_id(),
	SpecRel = #resource_spec_rel{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"IndexTable">>,
			rel_type = <<"based">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic index table specification">>,
			category = <<"IndexTable">>,
			version = <<"1.0">>,
			related = [SpecRel]}.

dynamic_index_row_spec(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:index_row_spec_id(),
	SpecRel1 = #resource_spec_rel{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"IndexRow">>,
			rel_type = <<"based">>},
	SpecRel2 = #resource_spec_rel{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name,
			rel_type = <<"contained">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic index table row specification">>,
			category = <<"IndexRow">>,
			version = <<"1.0">>,
			related = [SpecRel1, SpecRel2]}.

dynamic_prefix_table_spec(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:prefix_table_spec_id(),
	SpecRel = #resource_spec_rel{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"PrefixTable">>,
			rel_type = <<"based">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic prefix table specification">>,
			category = <<"PrefixTable">>,
			version = <<"1.0">>,
			related = [SpecRel]}.

dynamic_prefix_row_spec(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:prefix_row_spec_id(),
	SpecRel1 = #resource_spec_rel{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"PrefixTable">>,
			rel_type = <<"based">>},
	SpecRel2 = #resource_spec_rel{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name,
			rel_type = <<"contained">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic prefix table row specification">>,
			category = <<"PrefixRow">>,
			version = <<"1.0">>,
			related = [SpecRel1, SpecRel2]}.

dynamic_range_table_spec(Name)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:prefix_range_table_spec_id(),
	SpecRel = #resource_spec_rel{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"RangeTable">>,
			rel_type = <<"based">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic prefix range table specification">>,
			category = <<"RangeTable">>,
			version = <<"1.0">>,
			related = [SpecRel]}.

dynamic_range_row_spec(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecId = cse_rest_res_resource:prefix_range_row_spec_id(),
	SpecRel1 = #resource_spec_rel{id = SpecId,
			href = iolist_to_binary([?specPath, SpecId]),
			name = <<"RangeTable">>,
			rel_type = <<"based">>},
	SpecRel2 = #resource_spec_rel{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name,
			rel_type = <<"contained">>},
	#resource_spec{name = NameB,
			description = <<"Dynamic prefix range table row specification">>,
			category = <<"RangeRow">>,
			version = <<"1.0">>,
			related = [SpecRel1, SpecRel2]}.

dynamic_index_table(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecRef = #resource_spec_ref{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name},
	#resource{name = NameB,
			description = <<"Dynamic index table">>,
			category = <<"IndexTable">>,
			version = <<"1.0">>,
			specification = SpecRef}.

dynamic_index_row(Name, RowSpec, Table, Key, Value)
		when is_list(Name), is_list(Key), is_list(Value)  ->
	NameB = list_to_binary(Name),
	KeyB = list_to_binary(Key),
	ValueB = list_to_binary(Value),
	SpecRef = #resource_spec_ref{id = RowSpec#resource_spec.id,
			href = RowSpec#resource_spec.href,
			name = RowSpec#resource_spec.name},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"key">>, value = KeyB},
	Column2 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Dynamic index table row">>,
			category = <<"IndexRow">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"key">> => Column1, <<"value">> => Column2}}.

dynamic_index_row_extra(Name, RowSpec, Table, Key, Chars)
		when is_list(Name), is_map(Chars)  ->
	NameB = list_to_binary(Name),
	KeyChar = #characteristic{name = <<"key">>, value = Key},
	SpecRef = #resource_spec_ref{id = RowSpec#resource_spec.id,
			href = RowSpec#resource_spec.href,
			name = RowSpec#resource_spec.name},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	#resource{name = NameB,
			description = <<"Dynamic index table row">>,
			category = <<"IndexRow">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = maps:put(<<"key">>, KeyChar, Chars)}.

dynamic_prefix_table(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecRef = #resource_spec_ref{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name},
	#resource{name = NameB,
			description = <<"Dynamic prefix table">>,
			category = <<"PrefixTable">>,
			version = <<"1.0">>,
			specification = SpecRef}.

dynamic_prefix_row(Name, RowSpec, Table, Prefix, Value)
		when is_list(Name), is_list(Prefix), is_list(Value)  ->
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
			description = <<"Dynamic prefix table row">>,
			category = <<"PrefixRow">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"prefix">> => Column1, <<"value">> => Column2}}.

dynamic_range_table(Name, TableSpec)
		when is_list(Name) ->
	NameB = list_to_binary(Name),
	SpecRef = #resource_spec_ref{id = TableSpec#resource_spec.id,
			href = TableSpec#resource_spec.href,
			name = TableSpec#resource_spec.name},
	#resource{name = NameB,
			description = <<"Dynamic prefix range table">>,
			category = <<"RangeTable">>,
			version = <<"1.0">>,
			specification = SpecRef}.

dynamic_range_row(Name, RowSpec, Table, Start, End, Value)
		when is_list(Name), is_list(Start), is_list(End), is_list(Value)  ->
	NameB = list_to_binary(Name),
	StartB = list_to_binary(Start),
	EndB = list_to_binary(End),
	ValueB = list_to_binary(Value),
	SpecRef = #resource_spec_ref{id = RowSpec#resource_spec.id,
			href = RowSpec#resource_spec.href,
			name = RowSpec#resource_spec.name},
	ResourceRef = #resource_ref{id = Table#resource.id,
			href = Table#resource.href,
			name = Table#resource.name},
	ResourceRel = #resource_rel{rel_type = <<"contained">>,
			resource = ResourceRef},
	Column1 = #characteristic{name = <<"start">>, value = StartB},
	Column2 = #characteristic{name = <<"end">>, value = EndB},
	Column3 = #characteristic{name = <<"value">>, value = ValueB},
	#resource{name = NameB,
			description = <<"Dynamic prefix range table row">>,
			category = <<"RangeRow">>,
			version = <<"1.0">>,
			related = #{<<"contained">> => ResourceRel},
			specification = SpecRef,
			characteristic = #{<<"start">> => Column1,
					<<"end">> => Column2, <<"value">> => Column3}}.

new_index_table(Name, Options) when is_list(Name) ->
	case mnesia:create_table(list_to_atom(Name), Options) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end.

char_map(N) ->
	char_map(N, #{}).
char_map(0, Acc) ->
	Acc;
char_map(N, Acc) ->
	Name = list_to_binary(cse_test_lib:rand_name(10)),
	Value = cse_test_lib:rand_value(),
	Char = #characteristic{name = Name, value = Value}, 
	NewAcc = maps:put(Name, Char, Acc), 
	char_map(N - 1, NewAcc).

