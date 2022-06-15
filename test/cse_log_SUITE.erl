%%% cse_log_SUITE.erl
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
-module(cse_log_SUITE).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([new/0, new/1, close/0, close/1,
		log/0, log/1, blog/0, blog/1, alog/0, alog/1]).

-include_lib("common_test/include/ct.hrl").

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
	PrivDir = ?config(priv_dir, Config),
	ok = cse_test_lib:unload(cse),
	ok = cse_test_lib:load(cse),
	ok = application:set_env(cse, log_dir, PrivDir),
	ok = cse_test_lib:unload(mnesia),
	ok = cse_test_lib:load(mnesia),
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
	[new, close, log, blog, alog].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

new() ->
	[{userdata, [{doc, "Create a new log"}]}].

new(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	ok = cse_log:open(LogName, []).

close() ->
	[{userdata, [{doc, "Close an open log"}]}].

close(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, []),
	ok = cse_log:close(LogName).

log() ->
	[{userdata, [{doc, "Write to a internal format log"}]}].

log(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, []),
	Term = {?MODULE, cse_test_lib:rand_name(), erlang:universaltime()},
	ok = cse_log:log(LogName, Term),
	ok = disk_log:sync(LogName),
	{_, [Term]} = disk_log:chunk(LogName, start).

blog() ->
	[{userdata, [{doc, "Write to an external format log"}]}].

blog(Config) ->
	PrivDir = ?config(priv_dir, Config),
	Name = cse_test_lib:rand_name(),
	LogName = list_to_atom(Name),
	cse_log:open(LogName, [{format, external}]),
	Term = cse_test_lib:rand_name(40),
	ok = cse_log:blog(LogName, Term),
	ok = disk_log:sync(LogName),
	Filename = filename:join(PrivDir, Name),
	{ok, Binary} = file:read_file(Filename),
	[Term, $\r, $\n] = binary_to_list(Binary).

alog() ->
	[{userdata, [{doc, "Write to a log asynchronously"}]}].

alog(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, []),
	Term = {?MODULE, cse_test_lib:rand_name(), erlang:universaltime()},
	ok = cse_log:alog(LogName, Term),
	ok = disk_log:sync(LogName),
	{_, [Term]} = disk_log:chunk(LogName, start).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

