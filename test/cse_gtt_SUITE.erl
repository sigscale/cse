%%% cse_gtt_SUITTE.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022-2025 SigScale Global Inc.
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
%%%  @doc Test suite for GTT table API of the {@link //cse. cse} application.
%%%
-module(cse_gtt_SUITE).
-copyright('Copyright 2022-2025 SigScale Global Inc.').
-author('dushan@sigscale.org').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% test cases
-export([add_table/0, add_table/1,
		delete_table/0, delete_table/1,
		list_tables/0, list_tables/1,
		insert/0, insert/1,
		lookup/0, lookup/1,
		list/0, list/1,
		range/0, range/1,
		add_range/0, add_range/1,
		delete_range/0, delete_range/1,
		big_table/0, big_table/1,
		big_list_tables/0, big_list_tables/1,
		big_insert/0, big_insert/1,
		big_lookup/0, big_lookup/1,
		big_list/0, big_list/1,
		big_range/0, big_range/1]).

-include("cse.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	Description = "Test suite for GTT tables in CSE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]},
	{timetrap, {minutes, 1}}].

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
init_per_testcase(TestCase, Config)
		when TestCase == add_table;
		TestCase == big_table ->
	Table = list_to_atom(cse_test_lib:rand_name()),
	lists:keystore(table, 1, Config, {table, Table});
init_per_testcase(range = _TestCase, Config) ->
	Config;
init_per_testcase(TestCase, Config)
		when TestCase == big_list_tables;
		TestCase == big_insert;
		TestCase == big_lookup;
		TestCase == big_range ->
	Table = list_to_atom(cse_test_lib:rand_name()),
	ok = cse_gtt:new(Table, [{disc_only_copies, [node()]}]),
	lists:keystore(table, 1, Config, {table, Table});
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
	[add_table, delete_table, list_tables, insert, lookup,
			range, add_range, delete_range,
			big_table, big_list_tables, big_insert, big_lookup, big_range].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

add_table() ->
	Description = "Add a prefix table.",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

add_table(Config) ->
	Table = ?config(table, Config),
	ok = cse_gtt:new(Table, []),
	gtt = mnesia:table_info(Table, record_name),
	disc_copies = mnesia:table_info(Table, storage_type).

delete_table() ->
	Description = "Delete a prefix table.",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

delete_table(Config) ->
	Table = ?config(table, Config),
	ok = cse_gtt:delete(Table).

list_tables() ->
	Description = "List prefix tables.",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

list_tables(Config) ->
	Table = ?config(table, Config),
	true = lists:member(Table, cse_gtt:list()).

insert() ->
	Description = "Add a key and value to prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

insert(Config) ->
	Table = ?config(table, Config),
	do_insert(Table).

lookup() ->
	Description = "Find a key and value in prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

lookup(Config) ->
	Table = ?config(table, Config),
	do_lookup(Table).

list() ->
	Description = "List all rows in prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

list(Config) ->
	Table = ?config(table, Config),
	do_list(Table).

range() ->
	Description = "Prefixes for range",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Description = "Add prefixes by range",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

add_range(Config) ->
	Table = ?config(table, Config),
	Digits1 = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	Digits2 = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	[Start, End] = lists:sort([Digits1, Digits2]),
	Value = make_ref(),
	ok = cse_gtt:add_range(Table, Start, End, Value).

delete_range() ->
	Description = "Delete prefixes by range",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
			(#gtt{}, _Acc) ->
				mnesia:abort(garbage)
	end,
	F2 = fun() -> mnesia:foldl(F1, 0, Table) end,
	{atomic, 0} = mnesia:transaction(F2).

big_table() ->
	Description = "Add a disk only prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

big_table(Config) ->
	Table = ?config(table, Config),
	ok = cse_gtt:new(Table, [{disc_only_copies, [node()]}]),
	gtt = mnesia:table_info(Table, record_name),
	disc_only_copies = mnesia:table_info(Table, storage_type).

big_list_tables() ->
	Description = "List prefix tables, including disk only.",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

big_list_tables(Config) ->
	Table = ?config(table, Config),
	true = lists:member(Table, cse_gtt:list()).

big_insert() ->
	Description = "Add a key and value to disk only prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

big_insert(Config) ->
	Table = ?config(table, Config),
	do_insert(Table).

big_lookup() ->
	Description = "Find a key and value in disk only prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

big_list() ->
	Description = "List all rows in disk only prefix table",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

big_list(Config) ->
	Table = ?config(table, Config),
	do_list(Table).

big_lookup(Config) ->
	Table = ?config(table, Config),
	do_lookup(Table).

big_range() ->
	Description = "Add prefixes to a disk only table by range",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

big_range(Config) ->
	Table = ?config(table, Config),
	Digits1 = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	Digits2 = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	[Start, End] = lists:sort([Digits1, Digits2]),
	Value = make_ref(),
	ok = cse_gtt:add_range(Table, Start, End, Value),
	disc_only_copies = mnesia:table_info(Table, storage_type).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

do_insert(Table) ->
	Digits = io_lib:fwrite("~3.10.0b", [rand:uniform(1000) - 1]),
	Value = make_ref(),
	{ok, #gtt{}} = cse_gtt:insert(Table, Digits, Value).

do_lookup(Table) ->
	Items = do_fill(1000),
	ok = cse_gtt:insert(Table, Items),
	Index = rand:uniform(length(Items)),
	{Prefix, Value} = lists:nth(Index, Items),
	Address = Prefix ++ io_lib:fwrite("~3.10.0b",
			[rand:uniform(1000) - 1]),
	Value = cse_gtt:lookup_last(Table, Address).

do_list(Table) ->
	N = 1000,
	Items = do_fill(N),
	ok = cse_gtt:insert(Table, Items),
	do_list(Table, N, cse_gtt:list(start, Table)).
do_list(_Table, N, {eof, L}) ->
	0 = N - length(L);
do_list(Table, N, {Cont, L}) ->
	N1 = N - length(L),
	do_list(Table, N1, cse_gtt:list(Cont, Table)).

do_fill(N) ->
	F = fun F(Acc) when length(Acc) < N ->
				Digits = io_lib:fwrite("~7.10.0b",
						[rand:uniform(10000000) - 1]),
				case lists:keymember(Digits, 1, Acc)  of
					false ->
						Value = make_ref(),
						F([{Digits, Value} | Acc]);
					true ->
						F(Acc)
				end;
			F(Acc) ->
				Acc
	end,
	F([]).

