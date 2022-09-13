%%% cse_api_SUITE.erl
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
%%% Test suite for the public API of the {@link //cse. cse} application.
%%%
-module(cse_api_SUITE).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([start_cse/0, start_cse/1, stop_cse/0, stop_cse/1]).
-export([add_service/0, add_service/1,
		find_service/0, find_service/1,
		get_services/0, get_services/1,
		delete_service/0, delete_service/1,
		no_service/0, no_service/1]).
-export([announce/0, announce/1]).
-export([add_index_table_spec/0, add_index_table_spec/1,
		add_prefix_table_spec/0, add_prefix_table_spec/1,
		add_range_table_spec/0, add_range_table_spec/1,
		get_prefix_table_spec/0, get_prefix_table_spec/1,
		get_range_table_spec/0, get_range_table_spec/1,
		add_prefix_table/0, add_prefix_table/1,
		add_range_table/0, add_range_table/1,
		get_prefix_table/0, get_prefix_table/1,
		get_range_table/0, get_range_table/1]).

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
			delete_service, no_service, announce,
			add_prefix_table_spec, add_range_table_spec,
			get_prefix_table_spec, get_range_table_spec,
			add_prefix_table, add_range_table,
			get_prefix_table, get_range_table].

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
	EDP = edp(),
	{ok, Service} = cse:add_service(ServiceKey, Module, EDP),
	#service{key = ServiceKey, module = Module, edp = EDP} = Service.

find_service() ->
	[{userdata, [{doc, "Find an IN service logic processing program (SLP)"}]}].

find_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	Module = cse_slp_prepaid_cap_fsm,
	EDP = edp(),
	cse:add_service(ServiceKey, Module, EDP),
	{ok, Service} = cse:find_service(ServiceKey),
	#service{key = ServiceKey, module = Module, edp = EDP} = Service.

get_services() ->
	[{userdata, [{doc, "List all IN service logic processing programs (SLP)"}]}].

get_services(_Config) ->
	cse:add_service(rand:uniform(2147483647), cse_slp_prepaid_inap_fsm, edp()),
	cse:add_service(rand:uniform(2147483647), cse_slp_prepaid_inap_fsm, edp()),
	cse:add_service(rand:uniform(2147483647), cse_slp_prepaid_inap_fsm, edp()),
	F = fun(S) -> is_record(S, service) end,
	lists:all(F, cse:get_services()).

delete_service() ->
	[{userdata, [{doc, "Remove an IN service logic processing program (SLP)"}]}].

delete_service(_Config) ->
	ServiceKey = rand:uniform(2147483647),
	cse:add_service(ServiceKey, cse_slp_prepaid_cap_fsm, edp()),
	ok = cse:delete_service(ServiceKey).

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

add_prefix_table_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for a prefix table"}]}].

add_prefix_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_prefix_table_spec(Name),
	{ok, #resource_spec{name = Name}} = cse:add_resource_spec(Specification).

add_range_table_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for a prefix range table"}]}].

add_range_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_range_table_spec(Name),
	{ok, #resource_spec{name = Name}} = cse:add_resource_spec(Specification).

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

add_prefix_table() ->
	[{userdata, [{doc, "Add a Resource for a prefix table"}]}].

add_prefix_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	ok = cse_gtt:new(Name, []),
	SpecificationT = dynamic_prefix_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_prefix_table(Name, SpecificationR),
	{ok, #resource{name = Name}} = cse:add_resource(ResourceT).

add_range_table() ->
	[{userdata, [{doc, "Add a Resource for a prefix range table"}]}].

add_range_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	ok = cse_gtt:new(Name, []),
	SpecificationT = dynamic_range_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_range_table(Name, SpecificationR),
	{ok, #resource{name = Name}} = cse:add_resource(ResourceT).

get_prefix_table() ->
	[{userdata, [{doc, "Get a Resource for a prefix table"}]}].

get_prefix_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	ok = cse_gtt:new(Name, []),
	SpecificationT = dynamic_prefix_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_prefix_table(Name, SpecificationR),
	{ok, #resource{id = Id} = ResourceR} = cse:add_resource(ResourceT),
	{ok, ResourceR} = cse:find_resource(Id).

get_range_table() ->
	[{userdata, [{doc, "Get a Resource for a prefix range table"}]}].

get_range_table(_Config) ->
	Name = cse_test_lib:rand_name(10),
	ok = cse_gtt:new(Name, []),
	SpecificationT = dynamic_range_table_spec(Name),
	{ok, SpecificationR} = cse:add_resource_spec(SpecificationT),
	ResourceT = dynamic_range_table(Name, SpecificationR),
	{ok, #resource{id = Id} = ResourceR} = cse:add_resource(ResourceT),
	{ok, ResourceR} = cse:find_resource(Id).

add_index_table_spec() ->
	[{userdata, [{doc, "Add a Resource Specification for an index table"}]}].

add_index_table_spec(_Config) ->
	Name = cse_test_lib:rand_name(10),
	Specification = dynamic_index_table_spec(Name),
	{ok, _} = cse:add_resource_spec(Specification).

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

dynamic_prefix_table_spec(Name) ->
	PrefixSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	SpecRel = #resource_spec_rel{id = PrefixSpecId,
			href = ?specPath ++ PrefixSpecId,
			name = "PrefixTable",
			rel_type = "based"},
	#resource_spec{name = Name,
			description = "Dynamic prefix table specification",
			category = "PrefixTable",
			version = "1.0",
			related = [SpecRel]}.

dynamic_range_table_spec(Name) ->
	RangeSpecId = cse_rest_res_resource:prefix_range_table_spec_id(),
	SpecRel = #resource_spec_rel{id = RangeSpecId,
			href = ?specPath ++ RangeSpecId,
			name = "PrefixRangeTable",
			rel_type = "based"},
	#resource_spec{name = Name,
			description = "Dynamic prefix range table specification",
			category = "PrefixTable",
			version = "1.0",
			related = [SpecRel]}.

dynamic_index_table_spec(Name) ->
	IndexSpecId = cse_rest_res_resource:index_table_spec_id(),
	SpecRel = #resource_spec_rel{id = IndexSpecId,
			href = ?specPath ++ IndexSpecId,
			name = "IndexTable",
			rel_type = "based"},
	#resource_spec{name = Name,
			description = "Dynamic index table specification",
			category = "IndexTable",
			version = "1.0",
			related = [SpecRel]}.

dynamic_prefix_table(Name,
		#resource_spec{id = SpecId,
				href = SpecHref,
				name = SpecName}) ->
	SpecRef = #resource_spec_ref{id = SpecId,
			href = SpecHref,
			name = SpecName},
	#resource{name = Name,
			description = "Dynamic prefix table",
			category = "Prefix",
			version = "1.0",
			specification = SpecRef}.

dynamic_range_table(Name,
		#resource_spec{id = SpecId,
				href = SpecHref,
				name = SpecName}) ->
	SpecRef = #resource_spec_ref{id = SpecId,
			href = SpecHref,
			name = SpecName},
	#resource{name = Name,
			description = "Dynamic prefix range table",
			category = "Prefix",
			version = "1.0",
			specification = SpecRef}.

