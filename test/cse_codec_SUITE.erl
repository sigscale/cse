%%% cse_codec_SUITE.erl
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
%%% Test suite for the CODEC library of the {@link //cse. cse} application.
%%%
-module(cse_codec_SUITE).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
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
		redirect_info/0, redirect_info/1,
		generic_number/0, generic_number/1,
		generic_digits/0, generic_digits/1,
		date_time/0, date_time/1,
		cause/0, cause/1,
		ims_sip/0, ims_sip/1, ims_tel/0, ims_tel/1,
		rat_type/0, rat_type/1]).

-include("cse_codec.hrl").
-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	Description = "Test suite for CODEC library of CSE",
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
	[called_party, called_party_bcd, calling_party, isdn_address,
			redirect_info, generic_number, generic_digits, tbcd,
			date_time, cause, ims_sip, ims_tel].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

called_party() ->
	Description = "Encode/decode ISUP Called Party IE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Description = "Encode/decode ISUP Calling Party IE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Description = "Encode/decode CAMEL CalledPartyBCD",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Description = "Encode/decode TBCD-String",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

tbcd(_Config) ->
	Digits1 = "0123456789*#abc",
	Digits1 = cse_codec:tbcd(cse_codec:tbcd(Digits1)),
	Digits2 = "123456#",
	Digits2 = cse_codec:tbcd(cse_codec:tbcd(Digits2)),
	Digits3 = <<2:4, 1:4, 4:4, 3:4, 15:4, 5:4>>,
	Digits3 = cse_codec:tbcd(cse_codec:tbcd(Digits3)).

isdn_address() ->
	Description = "Encode/decode MAP ISDN-Address",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

isdn_address(_Config) ->
	NAI = nai(),
	NPI = 1,
	Address = lists:flatten([integer_to_list(D) || D <- address()]),
	IA = #isdn_address{nai = NAI, npi = NPI, address = Address},
	B = cse_codec:isdn_address(IA),
	<<1:1, NAI:3, NPI:4, Rest/binary>> = B,
	Address = cse_codec:tbcd(Rest),
	IA = cse_codec:isdn_address(B).

redirect_info() ->
	Description = "Encode/decode ISUP Redirection information",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

redirect_info(_Config) ->
	RedirectingIndicator = rand:uniform(7) -1,
	OriginalRedirectionReason = rand:uniform(4) -1,
	RedirectionCounter = rand:uniform(5),
	RedirectingReason = rand:uniform(7) - 1,
	RedirectionInformation = #redirect_info{
			indicator = RedirectingIndicator,
			orig_reason = OriginalRedirectionReason,
			reason = RedirectingReason,
			counter = RedirectionCounter},
	B = cse_codec:redirect_info(RedirectionInformation),
	<<OriginalRedirectionReason:4, _:1,
			RedirectingIndicator:3,
			RedirectingReason:4, _:1,
			RedirectionCounter:3>> = B,
	RedirectionInformation = cse_codec:redirect_info(B).

generic_number() ->
	Description = "Encode/decode ISUP Generic Number IE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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

generic_digits() ->
	Description = "Encode/decode ISUP Generic Digits IE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

generic_digits(_Config) ->
	Address = address(),
	ENC = length(Address) rem 2,
	TOD = 0,
	Digits = sccp_codec:bcd(Address),
	GD = #generic_digits{enc = ENC, tod = TOD, digits = Digits},
	B = cse_codec:generic_digits(GD),
	<<ENC:3, TOD:5, Rest/binary>> = B,
	Address = sccp_codec:bcd(Rest, ENC),
	GD = cse_codec:generic_digits(B).

date_time() ->
	Description = "Encode/decode CAMEL CalledPartyBCD",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Description = "Encode/decode ISUP Cause",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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

ims_sip() ->
	Description = "Decode IMS SIP URI",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

ims_sip(_Config) ->
	URIString1 = "sip:+14165551234;npdi;rn=+14162220000@ims.mnc001.mcc001.3gppnetwork.org:5060;user=phone",
	#ims_uri{scheme = sip, user = "+14165551234", uri_params = UriParams1,
		host = "ims.mnc001.mcc001.3gppnetwork.org", port = 5060,
		user_params = UserParams} = cse_codec:ims_uri(URIString1),
	true = map_get("npdi", UserParams),
	"+14162220000"= map_get("rn", UserParams),
	"phone" = map_get("user", UriParams1),
	URIString2 = "sips:+14165559876@ims.mnc001.mcc001.3gppnetwork.org;user=phone",
	#ims_uri{scheme = sips, user = "+14165559876", uri_params = UriParams2,
		host = "ims.mnc001.mcc001.3gppnetwork.org"} = cse_codec:ims_uri(URIString2),
	"phone" = map_get("user", UriParams2).

ims_tel() ->
	Description = "Decode IMS Tel URI",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

ims_tel(_Config) ->
	URIString1 = "tel:+14165551234;npdi;rn=+14162220000",
	#ims_uri{scheme = tel, user = "+14165551234",
			user_params = UserParams} = cse_codec:ims_uri(URIString1),
	true = map_get("npdi", UserParams),
	"+14162220000"= map_get("rn", UserParams),
	URIString2 = "tel:+14165559876",
	#ims_uri{user = "+14165559876"} = cse_codec:ims_uri(URIString2).

rat_type() ->
	Description = "Decode 3GPP-RAT-Type",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

rat_type(_Config) ->
	RatType = rand:bytes(1),
	String = cse_codec:rat_type(RatType),
	true = is_list(String).

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

