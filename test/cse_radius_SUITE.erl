%% cse_radius_SUITE.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2025 SigScale Global Inc.
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
%%%  @doc Test suite for diameter protocoll n the {@link //cse. cse} application.
%%%
-module(cse_radius_SUITE).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

% export test case functions
-export([simple_auth/0, simple_auth/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("radius/include/radius.hrl").

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 23).
		-define(HMAC(Key, Data), crypto:mac(hmac, md5, Key, Data)).
	-else.
		-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
	-endif.
-else.
	-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
-endif.

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
   [{userdata, [{doc, "Test suite for RADIUS in CSE"}]},
	{require, radius},
	{default_config, radius,
			[{address, {127,0,0,1}}]},
	{require, log},
	{default_config, log,
			[{logs,
					[{rating,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_rating_ecs}}]},
					{postpaid,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_postpaid_ecs}}]},
					{prepaid,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_prepaid_ecs}}]}]}]},
	{require, rest},
	{default_config, rest,
			[{user, "nrf"},
			{password, "4yjhe6ydsrh4"}]},
   {timetrap, {seconds, 60}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	DataDir = ?config(priv_dir, Config),
	ok = cse_test_lib:unload(mnesia),
	ok = cse_test_lib:load(mnesia),
	ok = application:set_env(mnesia, dir, DataDir),
	ok = cse_test_lib:unload(cse),
	ok = cse_test_lib:load(cse),
	ok = cse_test_lib:init_tables(),
	LogDir = ct:get_config({log, log_dir}, ?config(priv_dir, Config)),
	ok = application:set_env(cse, log_dir, LogDir),
	Logs = ct:get_config({log, logs}, []),
	ok = application:set_env(cse, logs, Logs),
	RadiusAddress = ct:get_config({radius, address}, {127,0,0,1}),
	AuthPort = ct:get_config({radius, auth_port},
			rand:uniform(64511) + 1024),
	AcctPort = ct:get_config({radius, acct_port},
			rand:uniform(64511) + 1024),
	Secret = ct:get_config({radius, secret}, cse_test_lib:rand_name()),
	AuthOptions = ct:get_config({radius, auth_options}, []),
	AcctOptions = ct:get_config({radius, acct_options}, []),
	SLP = {cse_slp_prepaid_radius_ps_fsm, [], []},
	AuthArgs = [{slp, #{2 => SLP}}],
	AcctArgs = [{slp, #{2 => SLP}}],
	RadiusAppVar = [{RadiusAddress, AuthPort,
					cse_radius_auth_server, AuthArgs, AuthOptions},
			{RadiusAddress, AcctPort,
					cse_radius_acct_server, AcctArgs, AcctOptions}],
	ok = application:set_env(cse, radius, RadiusAppVar),
	InterimInterval = 60 * rand:uniform(10),
   Config1 = [{radius_address, RadiusAddress},
			{acct_port, AcctPort},
			{auth_port, AuthPort},
			{secret, Secret},
			{interim_interval, InterimInterval} | Config],
	ok = cse_test_lib:start(),
	init_per_suite1(Config1).
%% @hidden
init_per_suite1(Config) ->
	case inets:start(httpd,
			[{port, 0},
			{server_name, atom_to_list(?MODULE)},
			{server_root, "./"},
			{document_root, ?config(data_dir, Config)},
			{modules, [mod_ct_nrf]}]) of
		{ok, HttpdPid} ->
			[{port, Port}] = httpd:info(HttpdPid, [port]),
			NrfUri = "http://localhost:" ++ integer_to_list(Port),
			ok = application:set_env(cse, nrf_uri, NrfUri),
			Config1 = [{server_port, Port}, {server_pid, HttpdPid}, {nrf_uri, NrfUri} | Config],
			init_per_suite2(Config1);
		{error, InetsReason} ->
			ct:fail(InetsReason)
	end.
%% @hidden
init_per_suite2(Config) ->
	case gen_server:start({local, ocs}, cse_test_ocs_server, [], []) of
		{ok, Pid} ->
			[{ocs, Pid} | Config];
		{error, Reason} ->
			ct:fail(Reason)
	end.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = cse_test_lib:stop(),
	OCS = ?config(ocs, Config),
	ok = gen_server:stop(OCS),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Initialization before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	Address = proplists:get_value(radius_address, Config),
	Secret = proplists:get_value(secret, Config),
	{ok, Socket} = gen_udp:open(0, [{active, false}, inet, binary]),
	ok = cse:add_client(Address, radius, Secret, #{}),
	[{nas_socket, Socket}, {nas_client, Address} | Config].

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, Config) ->
	Socket = proplists:get_value(nas_socket, Config),
	Address = proplists:get_value(nas_client, Config),
	gen_udp:close(Socket),
	ok = cse:delete_client(Address).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[simple_auth].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

simple_auth() ->
	[{userdata, [{doc, "RADIUS simple authentication"}]}].

simple_auth(Config) ->
	OCS = proplists:get_value(ocs, Config),
	MSISDN = cse_test_lib:rand_dn(11),
	Password = cse_test_lib:rand_name(),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, MSISDN, Balance}),
	RadID = 1,
	NasID = atom_to_list(?FUNCTION_NAME),
	AcctSessionID = cse_test_lib:rand_name(),
	Address = proplists:get_value(radius_address, Config),
	Port = proplists:get_value(auth_port, Config),
	Secret = proplists:get_value(secret, Config),
	ReqAuth = radius:authenticator(),
	HiddenPassword = radius_attributes:hide(Secret, ReqAuth, Password),
	Socket = proplists:get_value(nas_socket, Config),
	authenticate_subscriber(Socket, Address, Port, MSISDN,
			HiddenPassword, Secret, NasID, ReqAuth, RadID, AcctSessionID).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

authenticate_subscriber(Socket, Address, Port,
		Username, Password, Secret, NasID,
		ReqAuth, RadID, AcctSessionID) ->
	RadAttribute = radius_attributes:add(?UserPassword, Password, []),
	access_request(Socket, Address, Port, Username, Secret,
			NasID, ReqAuth, RadID, AcctSessionID, RadAttribute),
	access_accept(Socket, Address, Port, RadID).

access_request(Socket, Address, Port, UserName, Secret,
		NasID, Auth, RadID, AcctSessionID, RadAttributes)
		when is_binary(UserName) ->
	access_request(Socket, Address, Port, binary_to_list(UserName),
			Secret, NasID, Auth, RadID, AcctSessionID, RadAttributes);
access_request(Socket, Address, Port, UserName, Secret,
		NasID, Auth, RadID, AcctSessionID, RadAttributes) ->
	A1 = session_attributes(UserName, NasID, AcctSessionID, RadAttributes),
	A2 = radius_attributes:add(?MessageAuthenticator, <<0:128>>, A1),
	Request1 = #radius{code = ?AccessRequest, id = RadID,
		authenticator = Auth, attributes = A2},
	ReqPacket1 = radius:codec(Request1),
	MsgAuth1 = ?HMAC(Secret, ReqPacket1),
	A3 = radius_attributes:store(?MessageAuthenticator, MsgAuth1, A2),
	Request2 = Request1#radius{attributes = A3},
	ReqPacket2 = radius:codec(Request2),
	gen_udp:send(Socket, Address, Port, ReqPacket2).

access_accept(Socket, Address, Port, RadID) ->
	receive_radius(?AccessAccept, Socket, Address, Port, RadID).

receive_radius(Code, Socket, Address, Port, RadID) ->
	{ok, {Address, Port, RespPacket}} = gen_udp:recv(Socket, 0),
	#radius{code = Code, id = RadID} = radius:codec(RespPacket).

session_attributes(UserName, NasID, AcctSessionID, RadAttributes) ->
	A1 = radius_attributes:add(?UserName, UserName, RadAttributes),
	A2 = radius_attributes:add(?NasPort, 19, A1),
	A3 = radius_attributes:add(?NasIpAddress, {127,0,0,1}, A2),
	A4 = radius_attributes:add(?NasIdentifier, NasID, A3),
	A5 = radius_attributes:add(?CallingStationId,"DE-AD-BE-EF-FE-ED", A4),
	A6 = radius_attributes:add(?CalledStationId,"BA-DF-AD-CA-DD-AD:TestSSID", A5),
	A7 = radius_attributes:add(?AcctSessionId, AcctSessionID, A6),
	radius_attributes:add(?ServiceType, 2, A7).

