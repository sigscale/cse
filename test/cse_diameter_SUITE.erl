%% cse_diameter_SUITE.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2023 SigScale Global Inc.
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
-module(cse_diameter_SUITE).
-copyright('Copyright (c) 2016 - 2023 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

% export test case functions
-export([initial_scur_ims/0, initial_scur_ims/1,
		initial_scur_ims_nrf/0, initial_scur_ims_nrf/1,
		interim_scur_ims/0, interim_scur_ims/1,
		interim_scur_ims_nrf/0, interim_scur_ims_nrf/1,
		final_scur_ims/0, final_scur_ims/1,
		final_scur_ims_nrf/0, final_scur_ims_nrf/1,
		initial_scur_ps/0, initial_scur_ps/1,
		initial_scur_ps_nrf/0, initial_scur_ps_nrf/1,
		interim_scur_ps/0, interim_scur_ps/1,
		interim_scur_ps_nrf/0, interim_scur_ps_nrf/1,
		final_scur_ps/0, final_scur_ps/1,
		final_scur_ps_nrf/0, final_scur_ps_nrf/1,
		sms_iec/0, sms_iec/1,
		mms_iec/0, mms_iec/1,
		unknown_subscriber/0, unknown_subscriber/1,
		out_of_credit/0, out_of_credit/1,
		initial_in_call/0, initial_in_call/1,
		interim_in_call/0, interim_in_call/1,
		final_in_call/0, final_in_call/1,
		accounting_ims/0, accounting_ims/1,
		client_connect/0, client_connect/1,
		client_reconnect/0, client_reconnect/1,
		location_tai_ecgi/0, location_tai_ecgi/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("inets/include/mod_auth.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("diameter/include/diameter_gen_acct_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_3gpp_rf_application.hrl").
-include("diameter_gen_cc_application_rfc4006.hrl").

-define(MILLISECOND, millisecond).
-define(RO_APPLICATION, cse_diameter_3gpp_ro_application).
-define(RO_APPLICATION_DICT, diameter_gen_3gpp_ro_application).
-define(RO_APPLICATION_CALLBACK, cse_diameter_3gpp_ro_application_cb).
-define(RO_APPLICATION_ID, 4).
-define(RF_APPLICATION, cse_diameter_3gpp_rf_application).
-define(RF_APPLICATION_DICT, diameter_gen_3gpp_rf_application).
-define(RF_APPLICATION_CALLBACK, cse_diameter_3gpp_rf_application_cb).
-define(RF_APPLICATION_ID, 3).
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
			[{address, {127,0,0,1}},
			{port, 3868},
			{realm, "mnc001.mcc001.3gppnetwork.org"}]},
	{require, log},
	{default_config, log,
			[{logs,
					[{'3gpp_ro',
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_diameter_ecs}}]},
					{'3gpp_rf',
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_diameter_ecs}}]},
					{'rating',
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_rating_ecs}}]},
					{'cdr',
							[{format, external}]},
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
	DiameterPort = ct:get_config({diameter, port},
			rand:uniform(64511) + 1024),
	Ro = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	Rf = [{alias, ?RF_APPLICATION},
			{dictionary, ?RF_APPLICATION_DICT},
			{module, ?RF_APPLICATION_CALLBACK},
			{request_errors, callback}],
	Realm = ct:get_config({diameter, realm},
			"mnc001.mcc001.3gppnetwork.org"),
	SutRealm = "sut." ++ Realm,
	CtRealm = "ct." ++ Realm,
	CtHost = atom_to_list(?MODULE) ++ "." ++ CtRealm,
	DiameterOptions = [{'Origin-Realm', SutRealm},
			{application, Ro}, {application, Rf},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{'Acct-Application-Id', [?RF_APPLICATION_ID]}],
	DiameterAppVar = [{DiameterAddress, DiameterPort, DiameterOptions}],
	ok = application:set_env(cse, diameter, DiameterAppVar),
	InterimInterval = 60 * rand:uniform(10),
	ok = cse:add_context("rf.32251@3gpp.org",
			cse_slp_postpaid_diameter_ps_fsm,
			[{interim_interval, InterimInterval}], []),
	ok = cse:add_context("rf.32260@3gpp.org",
			cse_slp_postpaid_diameter_ims_fsm,
			[{interim_interval, InterimInterval}], []),
	ok = cse:add_context("rf.32270@3gpp.org",
			cse_slp_postpaid_diameter_mms_fsm,
			[{interim_interval, InterimInterval}], []),
	ok = cse:add_context("rf.32274@3gpp.org",
			cse_slp_postpaid_diameter_sms_fsm,
			[{interim_interval, InterimInterval}], []),
	ok = cse:add_context("rf.32278@3gpp.org",
			cse_slp_postpaid_diameter_ims_fsm,
			[{interim_interval, InterimInterval}], []),
   Config1 = [{realm, Realm}, {ct_host, CtHost},
			{ct_realm, CtRealm}, {sut_realm, SutRealm},
         {diameter_address, DiameterAddress},
			{interim_interval, InterimInterval} | Config],
	ok = cse_test_lib:start(),
   Service = {?MODULE, client},
   true = diameter:subscribe(Service),
   ok = diameter:start_service(Service,
			client_acct_service_opts(Config1)),
   receive
      #diameter_event{service = Service, info = start} ->
			ok
	end,
	TransportConfig = [{raddr, DiameterAddress},
			{rport, DiameterPort},
			{reuseaddr, true}, {ip, DiameterAddress}],
	TransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, TransportConfig}],
   {ok, _Ref} = diameter:add_transport(Service,
			{connect, TransportOpts}),
   receive
      #diameter_event{service = Service, info = Info}
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
end_per_testcase(TestCase, _Config)
		when TestCase == client_connect; TestCase == client_reconnect ->
   Service = {?MODULE, server},
   ok = diameter:stop_service(Service),
   receive
      #diameter_event{service = Service, info = stop} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end;
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
	[initial_scur_ims, initial_scur_ims_nrf, interim_scur_ims,
			interim_scur_ims_nrf, final_scur_ims, final_scur_ims_nrf,
			initial_scur_ps, initial_scur_ps_nrf, interim_scur_ps,
			interim_scur_ps_nrf, final_scur_ps, final_scur_ps_nrf,
			sms_iec, mms_iec,
			unknown_subscriber, out_of_credit,
			initial_in_call, interim_in_call, final_in_call,
			accounting_ims, client_connect, client_reconnect,
			location_tai_ecgi].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

initial_scur_ims() ->
	[{userdata, [{doc, "IMS SCUR CCA-I success"}]}].

initial_scur_ims(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, 0),
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

initial_scur_ims_nrf() ->
	[{userdata, [{doc, "IMS SCUR Nrf start"}]}].

initial_scur_ims_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU]} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant]} = GSU,
	{ok, {NewBalance, Grant}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Grant.

interim_scur_ims() ->
	[{userdata, [{doc, "IMS SCUR CCA-U success"}]}].

interim_scur_ims(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used),
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

interim_scur_ims_nrf() ->
	[{userdata, [{doc, "IMS SCUR CCR-U with Nrf update"}]}].

interim_scur_ims_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU1]} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant1]} = GSU1,
	{ok, {NewBalance, Grant1}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Grant1 + Used.

final_scur_ims() ->
	[{userdata, [{doc, "IMS SCUR CCR-T with CCA-T success"}]}].

final_scur_ims(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100000),
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used =  rand:uniform(Grant0),
	{ok, Answer1} = scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used),
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

final_scur_ims_nrf() ->
	[{userdata, [{doc, "IMS SCUR CCR-T with Nrf release"}]}].

final_scur_ims_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum0),
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
	{ok, Answer1} = scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum1, Used1),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU1]} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant1]} = GSU1,
	RequestNum2 = RequestNum1 + 1,
	Used2 = rand:uniform(Grant1),
	{ok, Answer2} = scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum2, Used2),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer2,
	{ok, {NewBalance, 0}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Used1 + Used2.

initial_scur_ps() ->
	[{userdata, [{doc, "PS SCUR CCA-I success"}]}].

initial_scur_ps(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = (rand:uniform(10) + 20) * 1048576,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, 0),
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
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant]} = GSU,
	Grant > 0.

initial_scur_ps_nrf() ->
	[{userdata, [{doc, "PS SCUR Nrf start"}]}].

initial_scur_ps_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = (rand:uniform(10) + 20) * 1048576,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU]} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant]} = GSU,
	{ok, {NewBalance, Grant}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Grant.

interim_scur_ps() ->
	[{userdata, [{doc, "PS SCUR CCA-U success"}]}].

interim_scur_ps(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = (rand:uniform(10) + 50) * 1048576,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_ps_interim(Config, Session, SI, RG, IMSI, MSISDN, RequestNum1, Used),
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
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant]} = GSU1,
	Grant > 0.

interim_scur_ps_nrf() ->
	[{userdata, [{doc, "PS SCUR CCR-U with Nrf update"}]}].

interim_scur_ps_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = (rand:uniform(10) + 50) * 1048576,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_ps_interim(Config, Session, SI, RG, IMSI, MSISDN, RequestNum1, Used),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU1]} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant1]} = GSU1,
	{ok, {NewBalance, Grant1}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Grant1 + Used.

final_scur_ps() ->
	[{userdata, [{doc, "IMS SCUR CCR-T with CCA-T success"}]}].

final_scur_ps(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = (rand:uniform(10) + 50) * 1048576,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used =  rand:uniform(Grant0),
	{ok, Answer1} = scur_ps_stop(Config, Session, SI, RG, IMSI, MSISDN, RequestNum1, Used),
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

final_scur_ps_nrf() ->
	[{userdata, [{doc, "IMS SCUR CCR-T with Nrf release"}]}].

final_scur_ps_nrf(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = (rand:uniform(10) + 50) * 1048576,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum0,
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used1 = rand:uniform(Grant0),
	{ok, Answer1} = scur_ps_interim(Config, Session, SI, RG, IMSI, MSISDN, RequestNum1, Used1),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU1]} = MSCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [Grant1]} = GSU1,
	RequestNum2 = RequestNum1 + 1,
	Used2 = rand:uniform(Grant1),
	{ok, Answer2} = scur_ps_stop(Config, Session, SI, RG, IMSI, MSISDN, RequestNum2, Used2),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer2,
	{ok, {NewBalance, 0}} = gen_server:call(OCS, {get_subscriber, IMSI}),
	Balance = NewBalance + Used1 + Used2.

sms_iec() ->
	[{userdata, [{doc, "SMS IEC CCR-E with CCA-E success"}]}].

sms_iec(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100000),
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = iec_event_sms(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [GSU],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Service-Specific-Units' = [1]} = GSU.

mms_iec() ->
	[{userdata, [{doc, "MMS IEC CCR-E with CCA-E success"}]}].

mms_iec(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100000),
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = iec_event_mms(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC]} = Answer,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [],
			'Used-Service-Unit' = [],
			'Granted-Service-Unit' = [GSU],
			'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = MSCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Service-Specific-Units' = [1]} = GSU.

unknown_subscriber() ->
	[{userdata, [{doc, "SCUR Nrf start with unknown user"}]}].

unknown_subscriber(Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN'} = Answer0.

out_of_credit() ->
	[{userdata, [{doc, "SCUR Nrf start when credit limit reached"}]}].

out_of_credit(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	{ok, {0, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, 0}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'IETF_RESULT-CODE_CREDIT_LIMIT_REACHED'} = Answer0.

initial_in_call() ->
	[{userdata, [{doc, "IMS voice terminating call SCUR CCA-I success"}]}].

initial_in_call(Config) ->
	OCS = ?config(ocs, Config),
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum = 0,
	{ok, Answer} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, terminate, 0),
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
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used = rand:uniform(Grant0),
	{ok, Answer1} = scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum1, Used),
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
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	SI = rand:uniform(20),
	RG = rand:uniform(99) + 100,
	Balance = rand:uniform(100000),
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	RequestNum0 = 0,
	{ok, Answer0} = scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Multiple-Services-Credit-Control' = [MSCC0]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GSU0]} = MSCC0,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [Grant0]} = GSU0,
	RequestNum1 = RequestNum0 + 1,
	Used =  rand:uniform(Grant0),
	{ok, Answer1} = scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum1, Used),
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

accounting_ims() ->
	[{userdata, [{doc, "Accounting record for IMS voice call"}]}].

accounting_ims(Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	Interval = ?config(interim_interval, Config),
	RecordNum0 = 0,
	{ok, Answer0} = acct_ims(Config, Session, IMSI, MSISDN, start, RecordNum0),
	#'3gpp_rf_ACA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Acct-Interim-Interval' = [Interval],
			'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING_ACCOUNTING-RECORD-TYPE_START_RECORD',
			'Accounting-Record-Number' = RecordNum0} = Answer0,
	RecordNum1 = RecordNum0 + 1,
	{ok, Answer1} = acct_ims(Config, Session, IMSI, MSISDN, interim, RecordNum1),
	#'3gpp_rf_ACA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Acct-Interim-Interval' = [Interval],
			'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD',
			'Accounting-Record-Number' = RecordNum1} = Answer1,
	RecordNum2 = RecordNum1 + 1,
	{ok, Answer2} = acct_ims(Config, Session, IMSI, MSISDN, stop, RecordNum2),
	#'3gpp_rf_ACA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Acct-Interim-Interval' = [Interval],
			'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING_ACCOUNTING-RECORD-TYPE_STOP_RECORD',
			'Accounting-Record-Number' = RecordNum2} = Answer2.

client_connect() ->
	[{userdata, [{doc, "Connect as client to peer server"}]}].

client_connect(Config) ->
	Realm = "ct." ++ ?config(realm, Config),
	Address = ?config(diameter_address, Config),
	Port = rand:uniform(64511) + 1024,
   Service = {?MODULE, server},
   true = diameter:subscribe(Service),
   ok = diameter:start_service(Service,
			server_acct_service_opts(Config)),
   receive
      #diameter_event{service = Service, info = start} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end,
	ServerTransportConfig = [{reuseaddr, true},
			{ip, Address}, {port, Port}],
	ServerTransportOpts = [{transport_module, diameter_tcp},
			{transport_config, ServerTransportConfig}],
   {ok, _Ref} = diameter:add_transport(Service,
			{listen, ServerTransportOpts}),
	Application = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	ClientTransportConfig = [{raddr, Address},
			{rport, Port},
			{reuseaddr, true}, {ip, Address}],
	ClientTransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, ClientTransportConfig}],
	Options = [{application, Application},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{connect, ClientTransportOpts}],
	{ok, Pid} = cse:start_diameter(Address, 0, Options),
   receive
      #diameter_event{service = Service, info = Info}
            when element(1, Info) == up ->
			ok = cse:stop_diameter(Pid)
   end.

client_reconnect() ->
	[{userdata, [{doc, "Reconnect disconnected client to peer server"}]}].

client_reconnect(Config) ->
	Realm = "ct." ++ ?config(realm, Config),
	Address = ?config(diameter_address, Config),
	Port = rand:uniform(64511) + 1024,
   Service = {?MODULE, server},
   true = diameter:subscribe(Service),
   ok = diameter:start_service(Service,
			server_acct_service_opts(Config)),
   receive
      #diameter_event{service = Service, info = start} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end,
	ServerTransportConfig = [{reuseaddr, true},
			{ip, Address}, {port, Port}],
	ServerTransportOpts = [{transport_module, diameter_tcp},
			{transport_config, ServerTransportConfig}],
   {ok, _Ref} = diameter:add_transport(Service,
			{listen, ServerTransportOpts}),
	Application = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	ClientTransportConfig = [{raddr, Address},
			{rport, Port},
			{reuseaddr, true}, {ip, Address}],
	ClientTransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, ClientTransportConfig}],
	Options = [{application, Application},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{connect, ClientTransportOpts}],
	{ok, Pid} = cse:start_diameter(Address, 0, Options),
   receive
      #diameter_event{service = Service, info = Info1}
            when element(1, Info1) == up ->
			ok
	after
		4000 ->
			ct:fail(timeout)
   end,
   ok = diameter:stop_service(Service),
   receive
      #diameter_event{service = Service, info = stop} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
   end,
	ct:sleep(1000),
   ok = diameter:start_service(Service,
			server_acct_service_opts(Config)),
   receive
      #diameter_event{service = Service, info = start} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
   end,
   receive
      #diameter_event{service = Service, info = Info2}
            when element(1, Info2) == up ->
			ok = cse:stop_diameter(Pid)
	end.

location_tai_ecgi() ->
	[{userdata, [{doc, "User location CODEC for TAI and ECGI"}]}].

location_tai_ecgi(_Config) ->
	Type = 130,
	MCC = 302,
	MNC = 720,
	<<MCC2:4, MCC1:4, 15:4, MCC3:4>> = cse_codec:tbcd(integer_to_list(MCC)),
	<<MNC2:4, MNC1:4, 15:4, MNC3:4>> = cse_codec:tbcd(integer_to_list(MNC)),
	Length = 15,
	TAC = 30210,
	ECI = 8941333,
	Bin = <<22, Length, Type, MCC2:4, MCC1:4, MNC3:4, MCC3:4, MNC2:4,
			MNC1:4, TAC:16, MCC2:4, MCC1:4, MNC3:4, MCC3:4, MNC2:4, MNC1:4,
			0:4, ECI:28>>,
	{ok, UserLocation} = cse_diameter:user_location(Bin),
	Mcc = io_lib:fwrite("~3.10.0b", [MCC]),
	Mnc = io_lib:fwrite("~3.10.0b", [MNC]),
	Plmn = #{mcc => Mcc, mnc => Mnc},
	Tac = io_lib:fwrite("~4.16.0b", [TAC]),
	Eci = io_lib:fwrite("~7.16.0b", [ECI]),
	#{eutraLocation := EutranLocation} = UserLocation,
	#{tai := TAI, ecgi := ECGI} = EutranLocation,
	#{plmnId := Plmn, tac := Tac} = TAI,
	#{plmnId := Plmn, eutraCellId := Eci} = ECGI.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum) ->
	Destination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
	scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum);
scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum) ->
	Origination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Calling-Party-Address' = [Origination]},
	scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum);
scur_ims_start(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum)
		when is_record(IMS, '3gpp_ro_IMS-Information') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
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
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	ServiceInformation = #'3gpp_ro_Service-Information'{
			'IMS-Information' = [IMS],
			'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32260@3gpp.org",
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum, Used) ->
	Destination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
	scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum, Used) ->
	Origination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Calling-Party-Address' = [Origination]},
	scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_ims_interim(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used)
		when is_record(IMS, '3gpp_ro_IMS-Information') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
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
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	ServiceInformation = #'3gpp_ro_Service-Information'{
			'IMS-Information' = [IMS],
			'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32260@3gpp.org",
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum, Used) ->
	Destination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
	scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum, Used) ->
	Origination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Calling-Party-Address' = [Origination]},
	scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used);
scur_ims_stop(Config, Session, SI, RG, IMSI, MSISDN, IMS, RequestNum, Used)
		when is_record(IMS, '3gpp_ro_IMS-Information') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
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
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	ServiceInformation = #'3gpp_ro_Service-Information'{
			'IMS-Information' = [IMS],
			'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32260@3gpp.org" ,
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

scur_ps_start(Config, Session, SI, RG, IMSI, MSISDN, RequestNum) ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	RSU = #'3gpp_ro_Requested-Service-Unit'{'CC-Total-Octets' = []},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Requested-Service-Unit' = [RSU]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32251@3gpp.org",
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

scur_ps_interim(Config, Session, SI, RG, IMSI, MSISDN, RequestNum, Used) ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	USU = #'3gpp_ro_Used-Service-Unit'{'CC-Total-Octets' = [Used]},
	RSU = #'3gpp_ro_Requested-Service-Unit'{'CC-Total-Octets' = []},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Used-Service-Unit' = [USU],
			'Requested-Service-Unit' = [RSU]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32251@3gpp.org",
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

scur_ps_stop(Config, Session, SI, RG, IMSI, MSISDN, RequestNum, Used) ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	USU = #'3gpp_ro_Used-Service-Unit'{'CC-Total-Octets' = [Used]},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Used-Service-Unit' = [USU]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32251@3gpp.org" ,
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

iec_event_sms(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum) ->
   Originator = #'3gpp_ro_Originator-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [MSISDN]},
	Destination = [cse_test_lib:rand_dn(rand:uniform(10) + 5)],
   Recipient = #'3gpp_ro_Recipient-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [Destination]},
	Info = #'3gpp_ro_Recipient-Info'{'Recipient-Address' = [Recipient]},
	SMS = #'3gpp_ro_SMS-Information'{
			'Originator-Received-Address' = [Originator],
			'Recipient-Info' = [Info]},
	iec_event_sms(Config, Session, SI, RG, IMSI, MSISDN, SMS, RequestNum);
iec_event_sms(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum) ->
	Origination = [cse_test_lib:rand_dn(rand:uniform(10) + 5)],
   Originator = #'3gpp_ro_Originator-Received-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [Origination]},
   Recipient = #'3gpp_ro_Recipient-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [MSISDN]},
	Info = #'3gpp_ro_Recipient-Info'{'Recipient-Address' = [Recipient]},
	SMS = #'3gpp_ro_SMS-Information'{
			'Originator-Received-Address' = [Originator],
			'Recipient-Info' = [Info]},
	iec_event_sms(Config, Session, SI, RG, IMSI, MSISDN, SMS, RequestNum);
iec_event_sms(Config, Session, SI, RG, IMSI, MSISDN, SMS, RequestNum)
		when is_record(SMS, '3gpp_ro_SMS-Information') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	USU = #'3gpp_ro_Used-Service-Unit'{'CC-Service-Specific-Units' = [1]},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Used-Service-Unit' = [USU]},
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	ServiceInformation = #'3gpp_ro_Service-Information'{
			'SMS-Information' = [SMS],
			'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32274@3gpp.org",
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_EVENT_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Requested-Action' = [?'3GPP_RO_REQUESTED-ACTION_DIRECT_DEBITING'],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

iec_event_mms(Config, Session, SI, RG, IMSI, MSISDN, originate, RequestNum) ->
   Originator = #'3gpp_ro_Originator-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [MSISDN]},
	Destination = [cse_test_lib:rand_dn(rand:uniform(10) + 5)],
   Recipient = #'3gpp_ro_Recipient-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [Destination]},
	MMS = #'3gpp_ro_MMS-Information'{
			'Originator-Address' = [Originator],
			'Recipient-Address' = [Recipient]},
	iec_event_mms(Config, Session, SI, RG, IMSI, MSISDN, MMS, RequestNum);
iec_event_mms(Config, Session, SI, RG, IMSI, MSISDN, terminate, RequestNum) ->
	Origination = [cse_test_lib:rand_dn(rand:uniform(10) + 5)],
   Originator = #'3gpp_ro_Originator-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [Origination]},
   Recipient = #'3gpp_ro_Recipient-Address'{
			'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
			'Address-Data' = [MSISDN]},
	MMS = #'3gpp_ro_MMS-Information'{
			'Originator-Address' = [Originator],
			'Recipient-Address' = [Recipient]},
	iec_event_mms(Config, Session, SI, RG, IMSI, MSISDN, MMS, RequestNum);
iec_event_mms(Config, Session, SI, RG, IMSI, MSISDN, MMS, RequestNum)
		when is_record(MMS, '3gpp_ro_MMS-Information') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	USU = #'3gpp_ro_Used-Service-Unit'{'CC-Service-Specific-Units' = [1]},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Service-Identifier' = [SI],
			'Rating-Group' = [RG],
			'Used-Service-Unit' = [USU]},
	PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	ServiceInformation = #'3gpp_ro_Service-Information'{
			'MMS-Information' = [MMS],
			'PS-Information' = [PS]},
	CCR = #'3gpp_ro_CCR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32270@3gpp.org",
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_EVENT_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Requested-Action' = [?'3GPP_RO_REQUESTED-ACTION_DIRECT_DEBITING'],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

acct_ims(Config, Session, IMSI, MSISDN, start, RecordNum) ->
	ACR = #'3gpp_rf_ACR'{
			'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING_ACCOUNTING-RECORD-TYPE_START_RECORD',
			'Accounting-Record-Number' = RecordNum},
	acct_ims(Config, Session, IMSI, MSISDN, ACR);
acct_ims(Config, Session, IMSI, MSISDN, interim, RecordNum) ->
	ACR = #'3gpp_rf_ACR'{
			'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD',
			'Accounting-Record-Number' = RecordNum},
	acct_ims(Config, Session, IMSI, MSISDN, ACR);
acct_ims(Config, Session, IMSI, MSISDN, stop, RecordNum) ->
	ACR = #'3gpp_rf_ACR'{
			'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING_ACCOUNTING-RECORD-TYPE_STOP_RECORD',
			'Accounting-Record-Number' = RecordNum},
	acct_ims(Config, Session, IMSI, MSISDN, ACR).
acct_ims(Config, Session, IMSI, MSISDN, ACR) when is_record(ACR, '3gpp_rf_ACR') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	Origination = "tel:+" ++ MSISDN,
	Destination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	SIP = "sip:+" ++ MSISDN ++ "@ims." ++ Realm,
	SIP1 = #'3gpp_rf_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_SIP_URI',
			'Subscription-Id-Data' = SIP},
	MSISDN1 = #'3gpp_rf_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_rf_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	PS = #'3gpp_rf_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
	SipMethod = #'3gpp_rf_Event-Type'{'SIP-Method' = ["INVITE"]},
	TimeStamps = #'3gpp_rf_Time-Stamps'{
			'SIP-Request-Timestamp' = [calendar:universal_time()],
			'SIP-Request-Timestamp-Fraction' = [rand:uniform(4294967296) - 1]},
	ICCID = "ims." ++ Realm ++ cse_test_lib:rand_dn(12),
	IOI = #'3gpp_rf_Inter-Operator-Identifier'{
			'Originating-IOI' = ["ims." ++ Realm],
			'Terminating-IOI' = [cse_test_lib:rand_dn(4) ++ "." ++ Realm]},
	Visited = cse_test_lib:rand_dn(4) ++ ".mnc999.mcc999.3gppnetworks.org",
	IMS = #'3gpp_rf_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_TERMINATING_ROLE'],
			'Event-Type' = [SipMethod],
			'User-Session-Id' = [cse_test_lib:rand_dn(25)],
			'Calling-Party-Address' = [SIP, Origination],
			'Called-Party-Address' = [Destination],
			'Time-Stamps' = [TimeStamps],
			'IMS-Charging-Identifier' = [ICCID],
			'Outgoing-Session-Id' = [cse_test_lib:rand_dn(20)],
			'Inter-Operator-Identifier' = [IOI],
			'IMS-Visited-Network-Identifier' = [Visited]},
	ServiceInformation = #'3gpp_rf_Service-Information'{
			'Subscription-Id' = [SIP1, MSISDN1, IMSI1],
			'IMS-Information' = [IMS],
			'PS-Information' = [PS]},
	ACR1 = ACR#'3gpp_rf_ACR'{'Session-Id' = Session,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Service-Context-Id' = ["rf.32260@3gpp.org"],
			'User-Name' = [MSISDN ++ "@" ++ Realm],
			'Event-Timestamp' = [calendar:universal_time()],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, acct_app_test, ACR1, []).

%% @hidden
client_acct_service_opts(Config) ->
	Realm = ?config(ct_realm, Config),
	Host = ?config(ct_host, Config),
	[{'Origin-Host', Host},
			{'Origin-Realm', Realm},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Client"},
			{'Acct-Application-Id', [?RF_APPLICATION_ID]},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, acct_app_test},
					{dictionary, diameter_gen_3gpp_rf_application},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, cc_app_test},
					{dictionary, diameter_gen_3gpp_ro_application},
					{module, cse_test_diameter_cb}]}].

%% @hidden
server_acct_service_opts(_Config) ->
	[{'Origin-Host', cse_test_lib:rand_name()},
			{'Origin-Realm', cse_test_lib:rand_name() ++ ".net"},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Server"},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, cc_app_test},
					{dictionary, diameter_gen_3gpp_ro_application},
					{module, cse_test_diameter_cb}]}].

