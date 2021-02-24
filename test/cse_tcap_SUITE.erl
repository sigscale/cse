%%% cse_tcap_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
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
%%% Test suite for the Transaction Capabilities stack integration
%%% of the {@link //cse. cse} application.
%%%
-module(cse_tcap_SUITE).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([start_dialogue/0, start_dialogue/1]).

-include_lib("sccp/include/sccp.hrl").
-include_lib("tcap/include/sccp_primitive.hrl").
-include_lib("common_test/include/ct.hrl").

-define(SSN_CAMEL, 146).

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
	application:load(mnesia),
	ok = application:set_env(mnesia, dir, PrivDir),
	{ok, [m3ua_asp, m3ua_as]} = m3ua_app:install(),
	{ok,[gtt_ep,gtt_as,gtt_pc]} = gtt_app:install(),
	ok = application:start(inets),
	ok = application:start(snmp),
	ok = application:start(sigscale_mibs),
	ok = application:start(m3ua),
	ok = application:start(tcap),
	ok = application:start(gtt),
	ok = application:start(cse),
	{ok, TCO} = application:get_env(cse, tsl_name),
	[{tco, TCO} | Config].

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = application:stop(cse),
	ok = application:stop(gtt),
	ok = application:stop(tcap),
	ok = application:stop(m3ua),
	ok = application:stop(sigscale_mibs),
	ok = application:stop(snmp),
	ok = application:stop(inets).

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
	[start_dialogue].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

start_dialogue() ->
	[{userdata, [{doc, "Start a TCAP Dialougue"}]}].

start_dialogue(Config) ->
	TCO = ?config(tco, Config),
	CallingParty = #party_address{ssn = ?SSN_CAMEL,
			nai = international,
			translation_type = undefined,
			numbering_plan = isdn_tele,
			encoding_scheme = bcd_odd,
			gt = [1,4,1,6,5,5,5,1,2,3,4]},
	CalledParty = #party_address{ssn = ?SSN_CAMEL,
			nai = international,
			translation_type = undefined,
			numbering_plan = isdn_tele,
			encoding_scheme = bcd_odd,
			gt = [1,4,1,6,5,5,5,5,6,7,8]},
	UnitData = #'N-UNITDATA'{userData = pdu_initial_dp(),
			sequenceControl = true,
			returnOption = true,
			calledAddress = CalledParty, callingAddress = CallingParty},
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, UnitData}).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

pdu_initial_dp() ->
	<<98,129,167,72,4,129,35,175,209,107,30,40,28,6,7,0,17,134,5,1,1,1,
			160,17,96,15,128,2,7,128,161,9,6,7,4,0,0,1,23,3,4,108,127,161,
			125,2,1,1,2,1,0,48,117,128,1,91,131,8,129,16,65,97,85,21,50,4,
			133,1,10,138,8,129,19,65,97,85,21,50,4,187,5,128,3,128,144,163,
			156,1,2,159,50,8,0,1,16,16,50,84,118,152,191,52,23,2,1,0,129,7,
			193,65,97,85,5,0,240,163,9,128,7,0,1,16,0,1,0,1,191,53,3,131,1,
			17,159,54,4,9,4,193,244,159,55,7,193,65,97,85,5,0,240,159,56,7,
			161,65,97,85,85,118,248,159,57,8,2,18,32,65,81,116,49,10>>.

