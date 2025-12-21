%%% cse_diameter_rf_SUITE.erl
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
%%%  @doc Test suite for DIAMETER Rf in the {@link //cse. cse} application.
%%%
-module(cse_diameter_rf_SUITE).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

% export test case functions
-export([accounting_ims/0, accounting_ims/1,
		client_connect/0, client_connect/1,
		client_reconnect/0, client_reconnect/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("diameter/include/diameter_gen_acct_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_rf_application.hrl").

-define(MILLISECOND, millisecond).
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
	Description = "Test suite for DIAMETER in CSE",
	ct:comment(Description),
	[{userdata, [{doc, Description}]},
	{require, diameter},
	{default_config, diameter,
			[{address, {127,0,0,1}},
			{port, 3868},
			{realm, "mnc001.mcc001.3gppnetwork.org"}]},
	{require, log},
	{default_config, log,
			[{logs,
					[{'3gpp_rf',
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_diameter_ecs}}]},
					{cdr,
							[{format, external}]},
					{postpaid,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_postpaid_ecs}}]}]}]},
	{timetrap, {minutes, 1}}].

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
			{application, Rf},
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
			Config1
	end.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = cse_test_lib:stop(),
	Config.

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Initialization before each test case.
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
	[accounting_ims, client_connect, client_reconnect].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

accounting_ims() ->
	Description = "Accounting record for IMS voice call",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Description = "Connect as client to peer server",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Application = [{alias, ?RF_APPLICATION},
			{dictionary, ?RF_APPLICATION_DICT},
			{module, ?RF_APPLICATION_CALLBACK},
			{request_errors, callback}],
	ClientTransportConfig = [{raddr, Address},
			{rport, Port},
			{reuseaddr, true}, {ip, Address}],
	ClientTransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, ClientTransportConfig}],
	Options = [{application, Application},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RF_APPLICATION_ID]},
			{connect, ClientTransportOpts}],
	{ok, Pid} = cse:start_diameter(Address, 0, Options),
	receive
		#diameter_event{service = Service, info = Info}
				when element(1, Info) == up ->
			ok = cse:stop_diameter(Pid)
	end.

client_reconnect() ->
	Description = "Reconnect disconnected client to peer server",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

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
	Application = [{alias, ?RF_APPLICATION},
			{dictionary, ?RF_APPLICATION_DICT},
			{module, ?RF_APPLICATION_CALLBACK},
			{request_errors, callback}],
	ClientTransportConfig = [{raddr, Address},
			{rport, Port},
			{reuseaddr, true}, {ip, Address}],
	ClientTransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, ClientTransportConfig}],
	Options = [{application, Application},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RF_APPLICATION_ID]},
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

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

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
			'Node-Functionality' = ?'3GPP_RF_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RF_ROLE-OF-NODE_TERMINATING_ROLE'],
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
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, acct_app_test},
					{dictionary, ?RF_APPLICATION_DICT},
					{module, cse_test_diameter_cb}]}].

%% @hidden
server_acct_service_opts(_Config) ->
	[{'Origin-Host', cse_test_lib:rand_name()},
			{'Origin-Realm', cse_test_lib:rand_name() ++ ".net"},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Server"},
			{'Auth-Application-Id', [?RF_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, cc_app_test},
					{dictionary, ?RF_APPLICATION_DICT},
					{module, cse_test_diameter_cb}]}].

