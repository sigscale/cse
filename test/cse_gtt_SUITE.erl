
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022-2023 SigScale Global Inc.
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
%%%  @doc Test suite for public API of the {@link //cse_gtt. cse_gtt} application.
%%%
-module(cse_gtt_SUITE).
-copyright('Copyright 2022-2023 SigScale Global Inc.').
-author('dushan@sigscale.org').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% test cases
-export([add_table/0, add_table/1,
		delete_table/0, delete_table/1,
		range/0, range/1,
		add_range/0, add_range/1,
		delete_range/0, delete_range/1]).

-include("cse.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "Test suite for cse_gtt API in CSE"}]}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	ok = cse_test_lib:unload(mnesia),
	DataDir = ?config(priv_dir, Config),
	ok = cse_test_lib:load(mnesia),
	ok = application:set_env(mnesia, dir, DataDir),
	ok = cse_test_lib:unload(cse),
	ok = cse_test_lib:load(cse),
	ok = cse_test_lib:init_tables(),
	ok = cse_test_lib:start([inets, snmp, sigscale_mibs, m3ua, tcap, gtt]),
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = cse_test_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before each test case.
%%
init_per_testcase(add_table = _TestCase, Config) ->
	Table = list_to_atom(cse_test_lib:rand_name()),
	lists:keystore(table, 1, Config, {table, Table});
init_per_testcase(range = _TestCase, Config) ->
	Config;
init_per_testcase(_TestCase, Config) ->
	Table = list_to_atom(cse_test_lib:rand_name()),
	ok = cse_gtt:new(Table, []),
	lists:keystore(table, 1, Config, {table, Table}).

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(TestCase, _Config)
		when TestCase == delete_table;
		TestCase == range ->
	ok;
end_per_testcase(_TestCase, Config) ->
	Table = ?config(table, Config),
	ok = cse_gtt:delete(Table).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[add_table, delete_table, range, add_range, delete_range].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

add_table() ->
	[{userdata, [{doc, "Add a prefix table."}]}].

add_table(Config) ->
	Table = ?config(table, Config),
	ok = cse_gtt:new(Table, []).

delete_table() ->
	[{userdata, [{doc, "Delete a prefix table."}]}].

delete_table(Config) ->
	Table = ?config(table, Config),
	ok = cse_gtt:delete(Table).

range() ->
	[{userdata, [{doc, "Prefixes for range"}]}].

range(_Config) ->
	Start = "5551234",
	End = "5556789",
	Prefixes = ["5551234", "5551235", "5551236", "5551237",
			"5551238", "5551239", "555124", "555125", "555126",
			"555127", "555128", "555129", "55513", "55514",
			"55515", "55516", "55517", "55518", "55519",
			"5552", "5553", "5554", "5555", "55560", "55561",
			"55562", "55563", "55564", "55565", "55566",
			"555670", "555671", "555672", "555673", "555674",
			"555675", "555676", "555677", "555678"],
	Prefixes  = lists:sort(cse_gtt:range(Start, End)).

add_range() ->
	[{userdata, [{doc, "Add prefixes by range"}]}].

add_range(Config) ->
	Table = ?config(table, Config),
	Digits1 = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	Digits2 = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	[Start, End] = lists:sort([Digits1, Digits2]),
	Value = make_ref(),
	ok = cse_gtt:add_range(Table, Start, End, Value).

delete_range() ->
	[{userdata, [{doc, "Delete prefixes by range"}]}].

delete_range(Config) ->
	Table = ?config(table, Config),
	Digits1 = io_lib:fwrite("~10.10.0b", [rand:uniform(10000000000) - 1]),
	Digits2 = io_lib:fwrite("~10.10.0b", [rand:uniform(10000000000) - 1]),
	[Start, End] = lists:sort([Digits1, Digits2]),
	Value = make_ref(),
	ok = cse_gtt:add_range(Table, Start, End, Value),
	ok = cse_gtt:delete_range(Table, Start, End),
	F1 = fun(#gtt{value = undefined}, Acc) ->
				Acc;
			(#gtt{}, Acc) ->
				mnesia:abort(garbage)
	end,
	F2 = fun() -> mnesia:foldl(F1, 0, Table) end,
	{atomic, 0} = mnesia:transaction(F2).

