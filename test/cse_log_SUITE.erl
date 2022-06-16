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
		log/0, log/1, blog/0, blog/1,
		alog/0, alog/1, balog/0, balog/1,
		log_wrap/0, log_wrap/1, blog_wrap/0, blog_wrap/1,
		log_codec/0, log_codec/1, blog_codec/0, blog_codec/1,
		log_job/0, log_job/1, blog_job/0, blog_job/1]).
%% export the private api
-export([codec_int/1, codec_ext/1]).

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
	[new, close, log, blog, alog, balog, log_wrap, blog_wrap,
			log_codec, blog_codec, log_job, blog_job].

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
	[{userdata, [{doc, "Write to an internal format log"}]}].

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
	BytesIn = cse_test_lib:rand_name(40),
	ok = cse_log:blog(LogName, BytesIn),
	ok = disk_log:sync(LogName),
	Filename = filename:join(PrivDir, Name),
	BytesOut = iolist_to_binary([BytesIn, $\r, $\n]),
	Size = byte_size(BytesOut),
	{ok, <<BytesOut:Size/binary, _/binary>>} = file:read_file(Filename).

alog() ->
	[{userdata, [{doc, "Write to an internal log asynchronously"}]}].

alog(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, []),
	Term = {?MODULE, cse_test_lib:rand_name(), erlang:universaltime()},
	ok = cse_log:alog(LogName, Term),
	ct:sleep(500),
	ok = disk_log:sync(LogName),
	{_, [Term]} = disk_log:chunk(LogName, start).

balog() ->
	[{userdata, [{doc, "Write to an external log asynchronously"}]}].

balog(Config) ->
	PrivDir = ?config(priv_dir, Config),
	Name = cse_test_lib:rand_name(),
	LogName = list_to_atom(Name),
	cse_log:open(LogName, [{format, external}]),
	BytesIn = cse_test_lib:rand_name(40),
	ok = cse_log:balog(LogName, BytesIn),
	ct:sleep(500),
	ok = disk_log:sync(LogName),
	Filename = filename:join(PrivDir, Name),
	BytesOut = iolist_to_binary([BytesIn, $\r, $\n]),
	Size = byte_size(BytesOut),
	{ok, <<BytesOut:Size/binary, _/binary>>} = file:read_file(Filename).

log_wrap() ->
	[{userdata, [{doc, "Write to an internal format wrap log"}]}].

log_wrap(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, [{format, internal},
			{type, wrap}, {size, {1024, 5}}]),
	F = fun F(0) ->
				disk_log:sync(LogName);
			F(N) ->
				Term = {?MODULE, cse_test_lib:rand_name(20), erlang:universaltime()},
				ok = cse_log:log(LogName, Term),
				F(N - 1)
	end,
	ok = F(50),
	{ok, Cont} = disk_log:chunk_step(LogName, start, 1),
	{_, [{?MODULE, _, _} | _]} = disk_log:chunk(LogName, Cont).

blog_wrap() ->
	[{userdata, [{doc, "Write to an external format wrap log"}]}].

blog_wrap(Config) ->
	PrivDir = ?config(priv_dir, Config),
	Name = cse_test_lib:rand_name(),
	LogName = list_to_atom(Name),
	Module = atom_to_list(?MODULE),
	Rand = cse_test_lib:rand_name(20),
	Time = cse_log:iso8601(cse_log:date(erlang:universaltime())),
	BytesIn = [Module, $;, Rand, $;, Time],
	cse_log:open(LogName, [{format, external},
			{type, wrap}, {size, {1024, 5}}]),
	F = fun F(0) ->
				disk_log:sync(LogName);
			F(N) ->
				ok = cse_log:blog(LogName, BytesIn),
				F(N - 1)
	end,
	ok = F(50),
	Filename = filename:join(PrivDir, Name ++ ".2"),
	BytesOut = iolist_to_binary([BytesIn, $\r, $\n]),
	Size = byte_size(BytesOut),
	{ok, <<BytesOut:Size/binary, _/binary>>} = file:read_file(Filename).

log_codec() ->
	[{userdata, [{doc, "Write through CODEC to an internal format log"}]}].

log_codec(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, [{codec, {?MODULE, codec_int}}]),
	Binary = rand:bytes(100),
	ok = cse_log:log(LogName, Binary),
	ok = disk_log:sync(LogName),
	{_, [Term | _]} = disk_log:chunk(LogName, start),
	Binary = codec_int(Term).

blog_codec() ->
	[{userdata, [{doc, "Write through CODEC to an external format log"}]}].

blog_codec(Config) ->
	PrivDir = ?config(priv_dir, Config),
	Name = cse_test_lib:rand_name(),
	LogName = list_to_atom(Name),
	cse_log:open(LogName, [{format, external}, {codec, {?MODULE, codec_ext}}]),
	Binary = rand:bytes(100),
	ok = cse_log:blog(LogName, Binary),
	ok = disk_log:sync(LogName),
	Filename = filename:join(PrivDir, Name),
	{ok, File} = file:open(Filename, [read]),
	{ok, JSON} = file:read_line(File),
	Binary = codec_ext(JSON).

log_job() ->
	[{userdata, [{doc, "Write with CODEC job to an internal format log"}]}].

log_job(_Config) ->
	LogName = list_to_atom(cse_test_lib:rand_name()),
	cse_log:open(LogName, [{process, true}, {codec, {?MODULE, codec_int}}]),
	Binary = rand:bytes(100),
	ok = cse_log:log(LogName, Binary),
	ct:sleep(500),
	ok = disk_log:sync(LogName),
	{_, [Term | _]} = disk_log:chunk(LogName, start),
	Binary = codec_int(Term).

blog_job() ->
	[{userdata, [{doc, "Write with CODEC job to an external format log"}]}].

blog_job(Config) ->
	PrivDir = ?config(priv_dir, Config),
	Name = cse_test_lib:rand_name(),
	LogName = list_to_atom(Name),
	cse_log:open(LogName, [{process, true}, {format, external}, {codec, {?MODULE, codec_ext}}]),
	Binary = rand:bytes(100),
	ok = cse_log:blog(LogName, Binary),
	ct:sleep(500),
	ok = disk_log:sync(LogName),
	Filename = filename:join(PrivDir, Name),
	{ok, File} = file:open(Filename, [read]),
	{ok, JSON} = file:read_line(File),
	Binary = codec_ext(JSON).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

codec_int(Binary) when is_binary(Binary) ->
	codec_int(Binary, $a, #{});
codec_int(Map) when is_map(Map) ->
	AVPs = lists:keysort(1, maps:to_list(Map)),
	codec_int(lists:reverse(AVPs), <<>>).

codec_int(<<Value:40, Rest/binary>>, N, Acc) ->
	Attribute = lists:duplicate(5, N),
	codec_int(Rest, N + 1, Acc#{Attribute => Value});
codec_int(<<>>, _, Acc) ->
	Acc.
codec_int([{_Attribute, Value} | T], Acc) ->
	codec_int(T, <<Value:40, Acc/binary>>);
codec_int([], Acc) ->
	Acc.

codec_ext(Binary) when is_binary(Binary) ->
	codec_ext(Binary, $a, #{});
codec_ext(JSON) when is_list(JSON) ->
	{ok, Map} = zj:decode(JSON),
	AVPs = lists:keysort(1, maps:to_list(Map)),
	codec_ext(lists:reverse(AVPs), <<>>).

codec_ext(<<Value:40, Rest/binary>>, N, Acc) ->
	Attribute = lists:duplicate(5, N),
	codec_ext(Rest, N + 1, Acc#{Attribute => Value});
codec_ext(<<>>, _, Acc) ->
	zj:encode(Acc).
codec_ext([{_Attribute, Value} | T], Acc) ->
	codec_ext(T, <<Value:40, Acc/binary>>);
codec_ext([], Acc) ->
	Acc.

