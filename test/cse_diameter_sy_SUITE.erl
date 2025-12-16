%%% cse_diameter_sy_SUITE.erl
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
%%%  @doc Test suite for DIAMETER Sy in the {@link //cse. cse} application.
%%%
-module(cse_diameter_sy_SUITE).
-copyright('Copyright (c) 2016 - 2025 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

% export test case functions
-export([slr_initial/0, slr_initial/1,
		client_connect/0, client_connect/1,
		client_reconnect/0, client_reconnect/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("inets/include/mod_auth.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_sy_application.hrl").

-define(MILLISECOND, millisecond).
-define(SY_APPLICATION, cse_diameter_3gpp_sy_application).
-define(SY_APPLICATION_DICT, diameter_gen_3gpp_sy_application).
-define(SY_APPLICATION_CALLBACK, cse_diameter_3gpp_sy_application_cb).
-define(SY_APPLICATION_ID, 16777302).
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
	{require, nchf},
	{default_config, nchf,
			[{address, {127,0,0,1}},
			{path, "/nchf-spendinglimitcontrol/v1/"}]},
	{require, sy},
	{default_config, sy,
			[{address, {127,0,0,1}},
			{realm, "ocs.mnc001.mcc001.3gppnetwork.org"}]},
   {timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
%% @hidden
init_per_suite(Config) ->
	application:start(inets),
	Port = ct:get_config({nchf, port},
			rand:uniform(64511) + 1024),
	case inets:start(httpd,
			[{port, Port},
			{server_name, atom_to_list(?MODULE)},
			{server_root, "./"},
			{document_root, ?config(data_dir, Config)},
			{modules, [mod_ct_nchf]}]) of
		{ok, HttpdPid} ->
			[{port, Port}] = httpd:info(HttpdPid, [port]),
			Path = ct:get_config({nchf, path},
					"/nchf-spendinglimitcontrol/v1/"),
			NchfUri = "http://localhost:" ++ integer_to_list(Port) ++ Path,
			Config1 = [{nchf_uri, NchfUri} | Config],
			init_per_suite1(Config1);
		{error, Reason} ->
			ct:fail(Reason)
	end.
%% @hidden
init_per_suite1(Config) ->
	DataDir = ?config(priv_dir, Config),
	ok = cse_test_lib:unload(mnesia),
	ok = cse_test_lib:load(mnesia),
	ok = application:set_env(mnesia, dir, DataDir),
	ok = cse_test_lib:unload(cse),
	ok = cse_test_lib:load(cse),
	ok = cse_test_lib:init_tables(),
	SyAddress = ct:get_config({sy, address}, {127,0,0,1}),
	SyPort = ct:get_config({sy, port}, rand:uniform(64511) + 1024),
	NchfURI = ?config(nchf_uri, Config),
	SyConfig = #{nchf_uri => NchfURI, notify_uri => NchfURI},
	Sy = [{alias, ?SY_APPLICATION},
			{dictionary, ?SY_APPLICATION_DICT},
			{module, [?SY_APPLICATION_CALLBACK, SyConfig]},
			{request_errors, callback}],
	Realm = ct:get_config({sy, realm},
			"ocs.mnc001.mcc001.3gppnetwork.org"),
	SutRealm = "sut." ++ Realm,
	CtRealm = "ct." ++ Realm,
	CtHost = atom_to_list(?MODULE) ++ "." ++ CtRealm,
	SyOptions = [{'Origin-Realm', SutRealm},
			{application, Sy},
			{'Auth-Application-Id', [?SY_APPLICATION_ID]}],
	SyService = {SyAddress, SyPort, SyOptions},
	ok = application:set_env(cse, diameter, [SyService]),
	InterimInterval = 60 * rand:uniform(10),
   Config1 = [{realm, Realm}, {ct_host, CtHost},
			{ct_realm, CtRealm}, {sut_realm, SutRealm},
         {sy_address, SyAddress},
			{interim_interval, InterimInterval} | Config],
	ok = cse_test_lib:start(),
   CtService = {?MODULE, client},
   true = diameter:subscribe(CtService),
   ok = diameter:start_service(CtService,
			client_auth_service_opts(Config1)),
   receive
      #diameter_event{service = CtService, info = start} ->
			ok
	end,
	TransportConfig = [{raddr, SyAddress},
			{rport, SyPort},
			{reuseaddr, true}, {ip, SyAddress}],
	TransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, TransportConfig}],
   {ok, _Ref} = diameter:add_transport(CtService,
			{connect, TransportOpts}),
   receive
      #diameter_event{service = CtService, info = Info}
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
	[slr_initial, client_connect, client_reconnect].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

slr_initial() ->
	Description = "Initial Spending-Limit-Request (SLR)",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

slr_initial(Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	Session = diameter:session_id(atom_to_list(?MODULE)),
	{ok, Answer} = subscribe(Config, Session, IMSI, MSISDN, initial),
	Success = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	#'3gpp_sy_SLA'{'Result-Code' = Success} = Answer.

client_connect() ->
	Description = "Connect as client to peer server",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

client_connect(Config) ->
	Realm = "ct." ++ ?config(realm, Config),
	Address = ?config(sy_address, Config),
	Port = rand:uniform(64511) + 1024,
   Service = {?MODULE, server},
   true = diameter:subscribe(Service),
   ok = diameter:start_service(Service,
			server_auth_service_opts(Config)),
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
	Application = [{alias, ?SY_APPLICATION},
			{dictionary, ?SY_APPLICATION_DICT},
			{module, ?SY_APPLICATION_CALLBACK},
			{request_errors, callback}],
	ClientTransportConfig = [{raddr, Address},
			{rport, Port},
			{reuseaddr, true}, {ip, Address}],
	ClientTransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, ClientTransportConfig}],
	Options = [{application, Application},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?SY_APPLICATION_ID]},
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
	Address = ?config(sy_address, Config),
	Port = rand:uniform(64511) + 1024,
   Service = {?MODULE, server},
   true = diameter:subscribe(Service),
   ok = diameter:start_service(Service,
			server_auth_service_opts(Config)),
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
	Application = [{alias, ?SY_APPLICATION},
			{dictionary, ?SY_APPLICATION_DICT},
			{module, ?SY_APPLICATION_CALLBACK},
			{request_errors, callback}],
	ClientTransportConfig = [{raddr, Address},
			{rport, Port},
			{reuseaddr, true}, {ip, Address}],
	ClientTransportOpts = [{connect_timer, 4000},
			{transport_module, diameter_tcp},
			{transport_config, ClientTransportConfig}],
	Options = [{application, Application},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?SY_APPLICATION_ID]},
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
			server_auth_service_opts(Config)),
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

subscribe(Config, Session, IMSI, MSISDN, initial) ->
	SLR = #'3gpp_sy_SLR'{
			'SL-Request-Type' = ?'3GPP_SY_SL-REQUEST-TYPE_INITIAL_REQUEST'},
	subscribe(Config, Session, IMSI, MSISDN, SLR);
subscribe(Config, Session, IMSI, MSISDN, intermediate) ->
	SLR = #'3gpp_sy_SLR'{
			'SL-Request-Type' = ?'3GPP_SY_SL-REQUEST-TYPE_INTERMEDIATE_REQUEST'},
	subscribe(Config, Session, IMSI, MSISDN, SLR);
subscribe(Config, Session, IMSI, MSISDN, SLR)
		when is_record(SLR, '3gpp_sy_SLR') ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	IMSI1 = #'3gpp_sy_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	MSISDN1 = #'3gpp_sy_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	SLR1 = SLR#'3gpp_sy_SLR'{'Session-Id' = Session,
			'Auth-Application-Id' = 16777302,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Realm' = DestinationRealm,
			'Subscription-Id' = [IMSI1, MSISDN1]},
	diameter:call({?MODULE, client}, auth_app_test, SLR1, []).

%% @hidden
client_auth_service_opts(Config) ->
	Realm = ?config(ct_realm, Config),
	Host = ?config(ct_host, Config),
	[{'Origin-Host', Host},
			{'Origin-Realm', Realm},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Client"},
			{'Auth-Application-Id', [?SY_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, auth_app_test},
					{dictionary, ?SY_APPLICATION_DICT},
					{module, cse_test_diameter_cb}]}].

%% @hidden
server_auth_service_opts(_Config) ->
	[{'Origin-Host', cse_test_lib:rand_name()},
			{'Origin-Realm', cse_test_lib:rand_name() ++ ".net"},
			{'Vendor-Id', ?IANA_PEN_SigScale},
			{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
			{'Product-Name', "SigScale Test Server"},
			{'Auth-Application-Id', [?SY_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, slc_app_test},
					{dictionary, ?SY_APPLICATION_DICT},
					{module, cse_test_diameter_cb}]}].

