%%% cse_log_codec_ecs_SUITE.erl
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
%%% Test suite for the Elestic Stack CODEC API
%%% 	of the {@link //cse. cse} application.
%%%
-module(cse_log_codec_ecs_SUITE).
-copyright('Copyright (c) 2022-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([diameter_ccr_initial/0, diameter_ccr_initial/1,
		prepaid_originating/0, prepaid_originating/1,
		postpaid_originating/0, postpaid_originating/1]).

-include("diameter_gen_3gpp_ro_application.hrl").
-include_lib("diameter/include/diameter.hrl").
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
	[diameter_ccr_initial, prepaid_originating, postpaid_originating].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

diameter_ccr_initial() ->
	[{userdata, [{doc, "Encode diameter event"}]}].

diameter_ccr_initial(_Config) ->
	Start = erlang:system_time(millisecond),
	Stop = Start + rand:uniform(100),
	Address = {192, 168, rand:uniform(255), rand:uniform(255)},
	Port = 3868,
	ServiceName = {?MODULE, Address, Port},
	OHost = "ct",
	DHost = "cse",
	Realm = "ims.mnc001.mcc001.3gppnetwork.org",
	Capabilities = #diameter_caps{origin_host = {DHost, OHost},
			origin_realm = {Realm, Realm}},
	Peer = {make_ref(), Capabilities},
	SessionId = session_id(OHost),
	ContextId = "32260@3gpp.org",
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(),
	SIPURI = "sip:+" ++ MSISDN ++ "@" ++ Realm,
	SubscriptionId1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = 0,
			'Subscription-Id-Data' = list_to_binary(MSISDN)},
	SubscriptionId2 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = 1,
			'Subscription-Id-Data' = list_to_binary(IMSI)},
	SubscriptionId3 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = 2,
			'Subscription-Id-Data' = list_to_binary(SIPURI)},
	UserName = IMSI ++ "@" ++ Realm,
	RequestNumber = rand:uniform(1000),
	ApplicationId = 4,
	RequestType = 1,
	Request = #'3gpp_ro_CCR'{
		'Session-Id' = list_to_binary(SessionId),
		'Auth-Application-Id' = ApplicationId,
		'CC-Request-Type' = RequestType,
		'CC-Request-Number' = RequestNumber,
		'Origin-Host' = list_to_binary(OHost),
		'Origin-Realm' = list_to_binary(Realm),
		'Destination-Realm' = list_to_binary(Realm),
		'Service-Context-Id' = list_to_binary(ContextId),
		'User-Name' = [list_to_binary(UserName)],
		'Subscription-Id' = [SubscriptionId1,
				SubscriptionId2, SubscriptionId3]},
	Reply = #'3gpp_ro_CCA'{
		'Session-Id' = list_to_binary(SessionId),
		'Result-Code' = 2001,
		'Origin-Host' = list_to_binary(OHost),
		'Origin-Realm' = list_to_binary(Realm),
		'Auth-Application-Id' = ApplicationId,
		'CC-Request-Type' = RequestType,
		'CC-Request-Number' = RequestNumber},
	Event = {Start, Stop, ServiceName, Peer, Request, {reply, Reply}},
	JSON = cse_log_codec_ecs:codec_diameter_ecs(Event),
	{ok, ECS} = zj:decode(JSON).

prepaid_originating() ->
	[{userdata, [{doc, "Encode prepaid originating call event"}]}].

prepaid_originating(_Config) ->
	Start = erlang:system_time(millisecond),
	Stop = Start + rand:uniform(100),
	ServiceName = atom_to_list(?MODULE),
	State = o_active,
	Realm = "ims.mnc001.mcc001.3gppnetwork.org",
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(),
	SIPURI = "sip:+" ++ MSISDN ++ "@" ++ Realm,
	Subscriber = #{imsi => IMSI, msisdn => MSISDN, sip_uri => SIPURI},
	Direction = originating,
	Calling = MSISDN,
	Called = cse_test_lib:rand_dn(),
	Call = #{direction => Direction, calling => Calling, called => Called},
	ContextId = "32260@3gpp.org",
	SessionId = list_to_binary(session_id("ct")),
	Network = #{context => ContextId, session_id => SessionId,
			hplmn => Realm, vplmn => Realm},
	NrfUri = "http://localhost:8080/nrf-rating/v1/ratingdata/42",
	OCS = #{nrf_location => NrfUri, nrf_result => "SUCCESS"},
	Event = {Start, Stop, ServiceName, State, Subscriber, Call, Network, OCS},
	JSON = cse_log_codec_ecs:codec_prepaid_ecs(Event),
	{ok, ECS} = zj:decode(JSON).

postpaid_originating() ->
	[{userdata, [{doc, "Encode postpaid originating call event"}]}].

postpaid_originating(_Config) ->
	Start = erlang:system_time(millisecond),
	Stop = Start + rand:uniform(100),
	ServiceName = atom_to_list(?MODULE),
	State = active,
	Realm = "ims.mnc001.mcc001.3gppnetwork.org",
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(),
	SIPURI = "sip:+" ++ MSISDN ++ "@" ++ Realm,
	Subscriber = #{imsi => IMSI, msisdn => MSISDN, sip_uri => SIPURI},
	Direction = originating,
	Calling = MSISDN,
	Called = cse_test_lib:rand_dn(),
	Call = #{direction => Direction, calling => Calling, called => Called},
	ContextId = "32260@3gpp.org",
	SessionId = list_to_binary(session_id("ct")),
	Network = #{context => ContextId, session_id => SessionId,
			hplmn => Realm, vplmn => Realm},
	Event = {Start, Stop, ServiceName, State, Subscriber, Call, Network},
	JSON = cse_log_codec_ecs:codec_postpaid_ecs(Event),
	{ok, ECS} = zj:decode(JSON).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

session_id(OriginHost) ->
	High = integer_to_list(erlang:system_time(millisecond)),
	Low = integer_to_list(erlang:unique_integer([positive])),
	[OriginHost, $;, High, $;, Low].

