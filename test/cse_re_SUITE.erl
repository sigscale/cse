%%% cse_re_SUITE.erl
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
%%%  @doc Test suite for Re interface in the {@link //cse. cse} application.
%%%
-module(cse_re_SUITE).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

% export test case functions
-export([default/0, default/1,
		http_connect_timeout/0, http_connect_timeout/1,
		http_refused/0, http_refused/1]).

% export test case resolver functions
-export([resolve1/2, resolve2/2]).

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
	Description = "Test suite for Re interface in CSE",
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
					[{'3gpp_ro',
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_diameter_ecs}}]},
					{rating,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_rating_ecs}}]},
					{cdr,
							[{format, external}]},
					{prepaid,
							[{format, external},
							{codec, {cse_log_codec_ecs, codec_prepaid_ecs}}]}]}]},
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
	Ro = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	Realm = ct:get_config({diameter, realm},
			"mnc001.mcc001.3gppnetwork.org"),
	SutRealm = "sut." ++ Realm,
	CtRealm = "ct." ++ Realm,
	CtHost = atom_to_list(?MODULE) ++ "." ++ CtRealm,
	DiameterOptions = [{'Origin-Realm', SutRealm},
			{application, Ro},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]}],
	DiameterAppVar = [{DiameterAddress, DiameterPort, DiameterOptions}],
	ok = application:set_env(cse, diameter, DiameterAppVar),
	InterimInterval = 60 * rand:uniform(10),
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
			Config1 = [{server_port, Port},
					{server_pid, HttpdPid},
					{nrf_uri, NrfUri} | Config],
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
	[default, http_connect_timeout, http_refused].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

default() ->
	Description = "Re interface with default configuration (reference case)",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

default(Config) ->
	Session = diameter:session_id(atom_to_list(?MODULE)),
	{ok, Answer} = scur_ims(Config, Session),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN'} = Answer.

http_connect_timeout() ->
	Description = "First host address URI connection timeout",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

http_connect_timeout(Config) ->
	ok = application:set_env(cse, nrf_retries, 1),
	ok = application:set_env(cse, nrf_resolver, {?MODULE, resolve1}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	{ok, Answer} = scur_ims(Config, Session),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN'} = Answer.

http_refused() ->
	Description = "First host address URI connection is refused",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

http_refused(Config) ->
	ok = application:set_env(cse, nrf_retries, 1),
	ok = application:set_env(cse, nrf_resolver, {?MODULE, resolve2}),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	{ok, Answer} = scur_ims(Config, Session),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN'} = Answer.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

scur_ims(Config, Session) ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	Realm = ?config(realm, Config),
	MSISDN = cse_test_lib:rand_dn(11),
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	RSU = #'3gpp_ro_Requested-Service-Unit'{'CC-Time' = []},
	MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Requested-Service-Unit' = [RSU]},
	Destination = "tel:+" ++ cse_test_lib:rand_dn(rand:uniform(10) + 5),
	IMS = #'3gpp_ro_IMS-Information'{
			'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
			'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
			'Called-Party-Address' = [Destination]},
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
			'CC-Request-Number' = 0,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Multiple-Services-Indicator' = [1],
			'Multiple-Services-Credit-Control' = [MSCC],
			'Service-Information' = [ServiceInformation]},
	diameter:call({?MODULE, client}, cc_app_test, CCR, []).

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

resolve1(ServiceURI, Options) ->
	URIMap = uri_string:parse(ServiceURI),
	Options1 = maps:merge(#{max_uri => 2}, proplists:to_map(Options)),
	BogusAddress = inet:ntoa(cse_test_lib:rand_ipv4()),
	BogusURI = URIMap#{host => BogusAddress},
	LocalURI = URIMap#{host => "127.0.0.1"},
	resolve3(Options1, [BogusURI, LocalURI], []).

resolve2(ServiceURI, Options) ->
	URIMap = uri_string:parse(ServiceURI),
	Options1 = maps:merge(#{max_uri => 2}, proplists:to_map(Options)),
	BogusPort = 49151, % IANA reserved
	BogusURI = URIMap#{host => "127.0.0.1", port => BogusPort},
	LocalURI = URIMap#{host => "127.0.0.1"},
	resolve3(Options1, [BogusURI, LocalURI], []).

resolve3(Options, [H | T], Acc) ->
	resolve3(Options, T, [uri_string:recompose(H) | Acc]);
resolve3(#{max_uri := N} = _Options, [], Acc) ->
	lists:sublist(lists:reverse(Acc), N).

