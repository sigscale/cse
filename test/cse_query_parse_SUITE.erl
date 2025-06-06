%%% cse_query_parse_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% Test suite for the REST query filter scanner/parser
%%% 	of the {@link //cse. cse} application.
%%%
-module(cse_query_parse_SUITE).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([root_path/0, root_path/1,
		relative_path/0, relative_path/1,
		select_child/0, select_child/1,
		select_children/0, select_children/1,
		select_embedded/0, select_embedded/1,
		select_descendants/0, select_descendants/1,
		slice/0, slice/1,
		slice_start/0, slice_start/1,
		slice_end/0, slice_end/1,
		filter_exact/0, filter_exact/1,
		filter_notexact/0, filter_notexact/1,
		filter_lt/0, filter_lt/1,
		filter_lte/0, filter_lte/1,
		filter_gt/0, filter_gt/1,
		filter_gte/0, filter_gte/1,
		filter_regex/0, filter_regex/1,
		filter_negate/0, filter_negate/1,
		filter_band/0, filter_band/1,
		filter_bor/0, filter_bor/1,
		filter_embedded/0, filter_embedded/1]).

-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	Description = "Test suite for REST query filter scanner/parser in CSE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]},
	{timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before the whole suite.
%%
init_per_suite(Config) ->
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok.

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
	[root_path, relative_path, select_child, select_children,
			select_embedded, select_descendants, slice, slice_start,
			slice_end, filter_exact, filter_notexact, filter_lt,
			filter_lte, filter_gt, filter_gte, filter_regex,
			filter_negate, filter_band, filter_bor, filter_embedded].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

root_path() ->
	Description = "Explicit root path selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

root_path(_Config) ->
	Query = "$.name",
	Root = '$',
	Step1 = {'.', ["name"]},
	Steps = [Step1],
	{Root, Steps} = parse(Query).

relative_path() ->
	Description = "Implicit root path selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

relative_path(_Config) ->
	Query = "name",
	Root = '$',
	Step1 = {'.', ["name"]},
	Steps = [Step1],
	{Root, Steps} = parse(Query).

select_child() ->
	Description = "Child path selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

select_child(_Config) ->
	Query = "$.resourceSpecification",
	Root = '$',
	Step1 = {'.', ["resourceSpecification"]},
	Steps = [Step1],
	{Root, Steps} = parse(Query).

select_children() ->
	Description = "Children path selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

select_children(_Config) ->
	Query = "$.resourceSpecification[id,href]",
	Root = '$',
	Step1 = {'.', ["resourceSpecification"]},
	Step2 = {'.', ["id", "href"]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

select_descendants() ->
	Description = "Descendants path selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

select_descendants(_Config) ->
	Query = "$..name",
	Root = '$',
	Step1 = {'..', ["name"]},
	Steps = [Step1],
	{Root, Steps} = parse(Query).

select_embedded() ->
	Description = "Embedded child selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

select_embedded(_Config) ->
	Query = "$.resourceSpecification.id",
	Root = '$',
	Step1 = {'.', ["resourceSpecification"]},
	Step2 = {'.', ["id"]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

slice() ->
	Description = "Slice array selection",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

slice(_Config) ->
	Query = "$.resourceCharacteristic[0:2]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Step2 = {'.', {slice, 0, 2}},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

slice_start() ->
	Description = "Slice array selection from start",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

slice_start(_Config) ->
	Query = "$.resourceCharacteristic[:2]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Step2 = {'.', {slice, undefined, 2}},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

slice_end() ->
	Description = "Slice array selection from end",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

slice_end(_Config) ->
	Query = "$.resourceCharacteristic[-4:]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Step2 = {'.', {slice, -4, undefined}},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_exact() ->
	Description = "Filter selection with exact match",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_exact(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value=='purple')]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {exact, {'@', ["value"]}, "purple"},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_notexact() ->
	Description = "Filter selection with exactly not",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_notexact(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value!='purple')]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {notexact, {'@', ["value"]}, "purple"},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_lt() ->
	Description = "Filter selection with less than",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_lt(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value<42)]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {lt, {'@', ["value"]}, 42},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_lte() ->
	Description = "Filter selection with less than or equal to",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_lte(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value=<42)]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {lte, {'@', ["value"]}, 42},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_gt() ->
	Description = "Filter selection with greater than",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_gt(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value>42)]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {gt, {'@', ["value"]}, 42},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_gte() ->
	Description = "Filter selection with less than or equal to",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_gte(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value>=42)]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {gte, {'@', ["value"]}, 42},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_regex() ->
	Description = "Filter selection with regular expression",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_regex(_Config) ->
	Query = "$.resourceCharacteristic[?(@.value=~'/[0-9]*$/')]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {regex, {'@', ["value"]}, "/[0-9]*$/"},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_negate() ->
	Description = "Filter selection with boolean not",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_negate(_Config) ->
	Query = "$.resourceCharacteristic[?(!@.default)]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {negate, {'@', ["default"]}},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_band() ->
	Description = "Filter with logical AND",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_band(_Config) ->
	Query = "$.resourceCharacteristic[?(@.name=='prefix' && @.value=='+1416')]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {exact, {'@', ["name"]}, "prefix"},
	Filter2 = {exact, {'@', ["value"]}, "+1416"},
	BAND = {'band', Filter1, Filter2},
	Step2 = {'.', [{filter, BAND}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_bor() ->
	Description = "Filter with logical AND",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_bor(_Config) ->
	Query = "$.resourceCharacteristic[?(@.id=='42' || @.name=='forty-two')]",
	Root = '$',
	Step1 = {'.', ["resourceCharacteristic"]},
	Filter1 = {exact, {'@', ["id"]}, "42"},
	Filter2 = {exact, {'@', ["name"]}, "forty-two"},
	BOR = {'bor', Filter1, Filter2},
	Step2 = {'.', [{filter, BOR}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

filter_embedded() ->
	Description = "Filter selection with embedded element",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

filter_embedded(_Config) ->
	Query = "resourceRelationship[?(@.resource.name=='foo')]",
	Root = '$',
	Step1 = {'.', ["resourceRelationship"]},
	Filter1 = {exact, {'@', ["resource", "name"]}, "foo"},
	Step2 = {'.', [{filter, Filter1}]},
	Steps = [Step1, Step2],
	{Root, Steps} = parse(Query).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

parse(String) ->
	{ok, Tokens, _} = cse_rest_query_scanner:string(String),
	{ok, JSONPath} = cse_rest_query_parser:parse(Tokens),
	JSONPath.

