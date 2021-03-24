%%% cse_codec_SUITE.erl
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
%%% Test suite for the public API of the {@link //cse. cse} application.
%%%
-module(cse_codec_SUITE).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([called_party/0, called_party/1,
		calling_party/0, calling_party/1,
		called_party_bcd/0, called_party_bcd/1,
		tbcd/0, tbcd/1, isdn_address/0, isdn_address/1,
		generic_number/0, generic_number/1,
		date_time/0, date_time/1,
		cause/0, cause/1]).

-include("cse_codec.hrl").
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
	[called_party, called_party_bcd, calling_party, isdn_address,
			generic_number, tbcd, date_time, cause].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

called_party() ->
	[{userdata, [{doc, "Encode/decode ISUP Called Party IE"}]}].

called_party(_Config) ->
	NAI = nai(),
	INN = 0,
	NPI = 1,
	Address = address(),
	OE = length(Address) rem 2,
	CP = #called_party{nai = NAI, inn = INN, npi = NPI, address = Address},
	B = cse_codec:called_party(CP),
	<<OE:1, NAI:7, INN:1, NPI:3, _:4, Rest/binary>> = B,
	Address = sccp_codec:bcd(Rest, OE),
	CP = cse_codec:called_party(B).

calling_party() ->
	[{userdata, [{doc, "Encode/decode ISUP Calling Party IE"}]}].

calling_party(_Config) ->
	NAI = nai(),
	NI = 0,
	NPI = 1,
	APRI = 0,
	SI = 3,
	Address = address(),
	OE = length(Address) rem 2,
	CP = #calling_party{nai = NAI, ni = NI, npi = NPI,
			apri = APRI, si = SI, address = Address},
	B = cse_codec:calling_party(CP),
	<<OE:1, NAI:7, NI:1, NPI:3, APRI:2, SI:2, Rest/binary>> = B,
	Address = sccp_codec:bcd(Rest, OE),
	CP = cse_codec:calling_party(B).

called_party_bcd() ->
	[{userdata, [{doc, "Encode/decode CAMEL CalledPartyBCD"}]}].

called_party_bcd(_Config) ->
	TON = 2,
	NPI = 1,
	Address = address(),
	CP = #called_party_bcd{ton = TON, npi = NPI, address = Address},
	B = cse_codec:called_party_bcd(CP),
	<<0:1, TON:3, NPI:4, Rest/binary>> = B,
	Address = case lists:reverse(sccp_codec:bcd(Rest, 0)) of
		[15 | Digits] ->
			lists:reverse(Digits);
		Digits ->
			lists:reverse(Digits)
	end,
	CP = cse_codec:called_party_bcd(B).

tbcd() ->
	[{userdata, [{doc, "Encode/decode TBCD-String"}]}].

tbcd(_Config) ->
	Digits1 = "0123456789*#abc",
	Digits1 = cse_codec:tbcd(cse_codec:tbcd(Digits1)),
	Digits2 = "123456#",
	Digits2 = cse_codec:tbcd(cse_codec:tbcd(Digits2)),
	Digits3 = <<2:4, 1:4, 4:4, 3:4, 15:4, 5:4>>,
	Digits3 = cse_codec:tbcd(cse_codec:tbcd(Digits3)).

isdn_address() ->
	[{userdata, [{doc, "Encode/decode MAP ISDN-Address"}]}].

isdn_address(_Config) ->
	NAI = nai(),
	NPI = 1,
	Address = lists:flatten([integer_to_list(D) || D <- address()]),
	IA = #isdn_address{nai = NAI, npi = NPI, address = Address},
	B = cse_codec:isdn_address(IA),
	<<1:1, NAI:3, NPI:4, Rest/binary>> = B,
	Address = cse_codec:tbcd(Rest),
	IA = cse_codec:isdn_address(B).

generic_number() ->
	[{userdata, [{doc, "Encode/decode ISUP Generic Number IE"}]}].

generic_number(_Config) ->
	NQI = 0,
	NAI = nai(),
	NPI = 1,
	NI = 0,
	APRI = 0,
	SI = 3,
	Address = address(),
	OE = length(Address) rem 2,
	GN = #generic_number{nqi = 0, nai = NAI, npi = NPI,
			ni = NI, apri = APRI, si = SI, address = Address},
	B = cse_codec:generic_number(GN),
	<<NQI, OE:1, NAI:7, NI:1, NPI:3, APRI:2, SI:2, Rest/binary>> = B,
	Address = sccp_codec:bcd(Rest, OE),
	GN = cse_codec:generic_number(B).

date_time() ->
	[{userdata, [{doc, "Encode/decode CAMEL CalledPartyBCD"}]}].

date_time(_Config) ->
	Year = (rand:uniform(1000) - 1) + 1500,
	Month = rand:uniform(12),
	Day = rand:uniform(28),
	Date = {Year, Month, Day},
	Hour = rand:uniform(12),
	Minute = rand:uniform(60) - 1,
	Second = rand:uniform(60) - 1,
	Time = {Hour, Minute, Second},
	DateTime = {Date, Time},
	B = cse_codec:date_time(DateTime),
	<<Y2:4, Y1:4, Y4:4, Y3:4, M2:4, M1:4, D2:4, D1:4,
			H2:4, H1:4, Min2:4, Min1:4, S2:4, S1:4>> = B,
	Year = (Y1 * 1000) + (Y2 * 100) + (Y3 * 10) + Y4,
	Month = (M1 * 10) + M2,
	Day = (D1 * 10) + D2,
	Hour = (H1 * 10) + H2,
	Minute = (Min1 * 10) + Min2,
	Second = (S1 * 10) + S2,
	DateTime = cse_codec:date_time(B).

cause() ->
	[{userdata, [{doc, "Encode/decode ISUP Cause"}]}].

cause(_Config) ->
	Codings = [itu, iso, national, other],
	Coding = lists:nth(rand:uniform(4), Codings),
	Locations = [user, local_private, local_public, transit,
			remote_public, remote_private, international, beyond],
	Location = lists:nth(rand:uniform(8), Locations),
	Value = rand:uniform(127),
	Diagnostic = case rand:uniform(2) of
		1 ->
			undefined;
		2 ->
			crypto:strong_rand_bytes(rand:uniform(4))
	end,
	Cause = #cause{coding = Coding, location = Location,
		value = Value, diagnostic = Diagnostic},
	Cause = cse_codec:cause(cse_codec:cause(Cause)).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

nai() ->
	rand:uniform(4).

address() ->
	address(rand:uniform(9) + 6, []).
address(N, Acc) when N > 0 ->
	address(N - 1, [rand:uniform(10 - 1) | Acc]);
address(0, Acc) ->
	Acc.

