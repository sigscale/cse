%% cse_diameter_SUITE.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2022 SigScale Global Inc.
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
%%%  @doc Test suite for public API of the {@link //cse. cse} application.
%%%
-module(cse_diameter_SUITE).
-copyright('Copyright (c) 2016 - 2022 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

% export test case functions
-export([initial_scur/0, initial_scur/1,
		initial_scur_nrf/0, initial_scur_nrf/1,
		interim_scur/0, interim_scur/1,
		interim_scur_nrf/0, interim_scur_nrf/1,
		final_scur/0, final_scur/1,
		final_scur_nrf/0, final_scur_nrf/1,
		unknown_subscriber/0, unknown_subscriber/1,
		out_of_credit/0, out_of_credit/1,
		initial_in_call/0, initial_in_call/1,
		interim_in_call/0, interim_in_call/1,
		final_in_call/0, final_in_call/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("inets/include/mod_auth.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_cc_application_rfc4006.hrl").

-define(MILLISECOND, millisecond).
-define(RO_APPLICATION, cse_diameter_3gpp_ro_application).
-define(RO_APPLICATION_DICT, diameter_gen_3gpp_ro_application).
-define(RO_APPLICATION_CALLBACK, cse_diameter_3gpp_ro_application_cb).
-define(RO_APPLICATION_ID, 4).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
   [{userdata, [{doc, "Test suite for Diameter in CSE"}]},
	{require, diameter},
	{default_config, diameter,
			[{address, {127,0,0,1}}]},
	{require, log},
	{default_config, log,
			[{logs,
					[{'3gpp_ro',
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_diameter_ecs}}]},
					{prepaid,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_prepaid_ecs}}]}]}]},
	{require, rest},
	{default_config, rest,
			[{user, "nrf"},
			{password, "4yjhe6ydsrh4"}]},
   {timetrap, {minutes, 60}}].

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
	DiameterAddress = ct:get_config({diameter, address}, {127,0,0,1}),
	DiameterPort = ct:get_config({diameter, auth_port}, rand:uniform(64511) + 1024),
	DiameterApplication = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	Realm = ct:get_config({diameter, realm}, "mnc001.mcc001.3gppnetwork.org"),
	Host = ct:get_config({diameter, host}, atom_to_list(?MODULE) ++ "." ++ Realm),
	DiameterOptions = [{application, DiameterApplication}, {'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]}],
	DiameterAppVar = [{DiameterAddress, DiameterPort, DiameterOptions}],
	ok = application:set_env(cse, diameter, DiameterAppVar),
   Config1 = [{diameter_host, Host}, {realm, Realm},
         {diameter_address, DiameterAddress} | Config],
	ok = cse_test_lib:start(),
   true = diameter:subscribe(?MODULE),
   ok = diameter:start_service(?MODULE, client_acct_service_opts(Config1)),
   receive
      #diameter_event{service = ?MODULE, info = start} ->
			ok
	end,
   {ok, _Ref} = connect(?MODULE, DiameterAddress, DiameterPort, diameter_tcp),
   receive
      #diameter_event{service = ?MODULE, info = Info}
            when element(1, Info) == up ->
			init_per_suite1(Config1)
   end.
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
%% Cleanup after the whole suite.
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
	[initial_scur, initial_scur_nrf, interim_scur,
			interim_scur_nrf, final_scur, final_scur_nrf,
			unknown_subscriber, out_of_credit,
			initial_in_call, interim_in_call, final_in_call].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

initial_scur() ->
	[{userdata, [{doc, "SCUR CCA-I success"}]}].

initial_scur(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum = 0,
	{ok, Answer} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, 0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [GSU],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant]} = GSU,
	Grant > 0.

initial_scur_nrf() ->
	[{userdata, [{doc, "SCUR Nrf start"}]}].

initial_scur_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum = 0,
	{ok, Answer} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU]} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant]} = GSU,
	{ok, {NewBalance, Grant}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Grant.

interim_scur() ->
	[{userdata, [{doc, "SCUR CCA-U success"}]}].

interim_scur(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum0 = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_interim(Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
			'CC-Request-Number' = RequestNum1,
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [GSU1],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant]} = GSU1,
	Grant > 0.

interim_scur_nrf() ->
	[{userdata, [{doc, "SCUR CCR-U with Nrf update"}]}].

interim_scur_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum0 = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_interim(Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU1]} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant1]} = GSU1,
	{ok, {NewBalance, Grant1}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Grant1 + Used.

final_scur() ->
	[{userdata, [{doc, "SCUR CCR-T with CCA-T success"}]}].

final_scur(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100000),
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum0 = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used =  rand:uniform(Grant0),
	{ok, Answer1} = scur_stop(Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
			'CC-Request-Number' = RequestNum1,
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC1.

final_scur_nrf() ->
	[{userdata, [{doc, "SCUR CCR-T with Nrf release"}]}].

final_scur_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum0 = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum0,
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used1 = rand:uniform(Grant0),
	{ok, Answer1} = scur_interim(Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used1),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU1]} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant1]} = GSU1,
	RequestNum2 = RequestNum1 + 1,
	Used2 = rand:uniform(Grant1),
	{ok, Answer2} = scur_stop(Session, SI, RG, IMSI, MSISDN, originate, RequestNum2, Used2),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer2,
	{ok, {NewBalance, 0}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Used1 + Used2.

unknown_subscriber() ->
	[{userdata, [{doc, "SCUR Nrf start with unknown user"}]}].

unknown_subscriber(_Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN'} = Answer0.

out_of_credit() ->
	[{userdata, [{doc, "SCUR Nrf start when credit limit reached"}]}].

out_of_credit(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	{ok, {0, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, 0}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED'} = Answer0.

initial_in_call() ->
	[{userdata, [{doc, "IMS voice terminating call SCUR CCA-I success"}]}].

initial_in_call(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum = 0,
	{ok, Answer} = scur_start(Session, SI, RG, IMSI, MSISDN, terminate, 0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [GSU],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant]} = GSU,
	Grant > 0.

interim_in_call() ->
	[{userdata, [{doc, "IMS voice terminating call SCUR CCA-U success"}]}].

interim_in_call(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum0 = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_interim(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
			'CC-Request-Number' = RequestNum1,
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [GSU1],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant]} = GSU1,
	Grant > 0.

final_in_call() ->
	[{userdata, [{doc, "IMS voice terminating call SCUR CCR-T with CCA-T success"}]}].

final_in_call(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100000),
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(erlang:ref_to_list(make_ref())),
	RequestNum0 = 0,
	{ok, Answer0} = scur_start(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used =  rand:uniform(Grant0),
	{ok, Answer1} = scur_stop(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
			'CC-Request-Number' = RequestNum1,
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC1.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

scur_start(Session, SI, RG, IMSI, MSISDN, originate, RequestNum) ->
	Destination = [$+ | cse_test_lib:rand_dn(rand:uniform(10) + 5)],
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
	scur_start(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum);
scur_start(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum) ->
	Origination = [$+ | cse_test_lib:rand_dn(rand:uniform(10) + 5)],
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Calling-Party-Address' = [Origination]},
	scur_start(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum);
scur_start(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum)
		when is_record(IMS, '3gpp_ro_IMS-Information') ->
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	RSU = #'3gpp_ro_Requested-Service-Unit'{'CC-Time' = []},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [RSU]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'IMS-Information' = [IMS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32260@3gpp.org",
			'User-Name' = [MSISDN],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Service-Information' = [ServiceInformation]},
	diameter:call(?MODULE, cc_app_test, CCR, []).

scur_interim(Session, SI, RG, IMSI, MSISDN, originate, RequestNum, Used) ->
	Destination = [$+ | cse_test_lib:rand_dn(rand:uniform(10) + 5)],
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
	scur_interim(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_interim(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum, Used) ->
	Origination = [$+ | cse_test_lib:rand_dn(rand:uniform(10) + 5)],
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Calling-Party-Address' = [Origination]},
	scur_interim(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_interim(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used)
		when is_record(IMS, '3gpp_ro_IMS-Information') ->
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	USU = #'3gpp_ro_Used-Service-Unit'{'CC-Time' = [Used]},
	RSU = #'3gpp_ro_Requested-Service-Unit' {'CC-Time' = []},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Used-Service-Unit' = [USU],
			'Requested-Service-Unit' = [RSU]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'IMS-Information' = [IMS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32260@3gpp.org",
			'User-Name' = [MSISDN],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Service-Information' = [ServiceInformation]},
	diameter:call(?MODULE, cc_app_test, CCR, []).

scur_stop(Session, SI, RG, IMSI, MSISDN, originate, RequestNum, Used) ->
	Destination = [$+ | cse_test_lib:rand_dn(rand:uniform(10) + 5)],
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
	scur_stop(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_stop(Session, SI, RG, IMSI, MSISDN, terminate, RequestNum, Used) ->
	Origination = [$+ | cse_test_lib:rand_dn(rand:uniform(10) + 5)],
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Calling-Party-Address' = [Origination]},
	scur_stop(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_stop(Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used)
		when is_record(IMS, '3gpp_ro_IMS-Information') ->
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	USU = #'3gpp_ro_Used-Service-Unit'{'CC-Time' = [Used]},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Used-Service-Unit' = [USU]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'IMS-Information' = [IMS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32260@3gpp.org" ,
			'User-Name' = [MSISDN],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Service-Information' = [ServiceInformation]},
	diameter:call(?MODULE, cc_app_test, CCR, []).

%% @doc Add a transport capability to diameter service.
%% @hidden
connect(SvcName, Address, Port, Transport) when is_atom(Transport) ->
	connect(SvcName, [{connect_timer, 30000} | transport_opts(Address, Port, Transport)]).

%% @hidden
connect(SvcName, Opts)->
	diameter:add_transport(SvcName, {connect, Opts}).

%% @hidden
client_acct_service_opts(Config) ->
	[{'Origin-Host', ?config(diameter_host, Config)},
			{'Origin-Realm', ?config(realm, Config)},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Client (Nrf)"},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, diameter_test_client_cb}]},
			{application, [{alias, cc_app_test},
					{dictionary, diameter_gen_3gpp_ro_application},
					{module, diameter_test_client_cb}]}].

%% @hidden
transport_opts(Address, Port, Trans) when is_atom(Trans) ->
	transport_opts1({Trans, Address, Address, Port}).

%% @hidden
transport_opts1({Trans, LocalAddr, RemAddr, RemPort}) ->
	[{transport_module, Trans}, {transport_config,
		[{raddr, RemAddr}, {rport, RemPort},
		{reuseaddr, true}, {ip, LocalAddr}]}].

