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
		slr_intermediate/0, slr_intermediate/1,
		snr_normal/0, snr_normal/1,
		final_str/0, final_str/1,
		client_connect/0, client_connect/1,
		client_reconnect/0, client_reconnect/1]).
% export private API
-export([handle_request/3]).

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
			{path, "/nchf-spendinglimitcontrol/v1"}]},
	{require, iwf},
	{default_config, iwf,
			[{address, {127,0,0,1}},
			{path, "/nchf-spendinglimitcontrol/v1"},
			{profile, iwf},
			{options, [{keep_alive_timeout, 4000}]}]},
	{require, sy},
	{default_config, sy,
			[{address, {127,0,0,1}},
			{realm, "ocs.mnc001.mcc001.3gppnetwork.org"}]},
	{timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	application:start(inets),
	Port = ct:get_config({nchf, port},
			rand:uniform(64511) + 1024),
	Modules = [mod_ct_nchf],
	case inets:start(httpd,
			[{port, Port},
			{server_name, atom_to_list(?MODULE) ++ "-nchf"},
			{server_root, "./"},
			{document_root, ?config(data_dir, Config)},
			{modules, Modules}]) of
		{ok, HttpdPid} ->
			[{port, Port}] = httpd:info(HttpdPid, [port]),
			Path = ct:get_config({nchf, path},
					"/nchf-spendinglimitcontrol/v1"),
			URI = "http://localhost:" ++ integer_to_list(Port) ++ Path,
			Config1 = [{nchf_uri, URI} | Config],
			init_per_suite1(Config1);
		{error, Reason} ->
			ct:fail(Reason)
	end.
init_per_suite1(Config) ->
	Profile = ct:get_config({iwf, profile}, iwf),
	{ok, _Pid} = inets:start(httpc, [{profile, Profile}]),
	Options = ct:get_config({iwf, options}, []),
	ok = httpc:set_options(Options, Profile),
	Port = ct:get_config({iwf, port},
			rand:uniform(64511) + 1024),
	Modules = [mod_cse_rest_accepted_content,
			mod_cse_rest_get,
			mod_cse_rest_head,
			mod_get,
			mod_cse_rest_post,
			mod_cse_rest_delete],
	case inets:start(httpd,
			[{port, Port},
			{server_name, atom_to_list(?MODULE) ++ "-iwf"},
			{server_root, "./"},
			{document_root, ?config(data_dir, Config)},
			{modules, Modules}]) of
		{ok, HttpdPid} ->
			[{port, Port}] = httpd:info(HttpdPid, [port]),
			Path = ct:get_config({iwf, path},
					"/nchf-spendinglimitcontrol/v1"),
			URI = "http://localhost:" ++ integer_to_list(Port) ++ Path,
			Config1 = [{iwf_uri, URI}, {iwf_profile, Profile} | Config],
			init_per_suite2(Config1);
		{error, Reason} ->
			ct:fail(Reason)
	end.
init_per_suite2(Config) ->
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
	ok = application:set_env(cse, nchf_profile, nchf),
	ok = application:set_env(cse, nchf_options,
			[{keep_alive_timeout, 4000}]),
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
	[slr_initial, slr_intermediate, snr_normal, final_str,
			client_connect, client_reconnect].

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
	Session = session_id(Config),
	Answer = subscribe(Config, Session, IMSI, MSISDN),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	#'3gpp_sy_SLA'{'Result-Code' = [ResultCode]} = Answer.

slr_intermediate() ->
	Description = "Intermediate Spending-Limit-Request (SLR)",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

slr_intermediate(Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	Session = session_id(Config),
	Answer1 = subscribe(Config, Session, IMSI, MSISDN),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	#'3gpp_sy_SLA'{'Result-Code' = [ResultCode],
			'Origin-Host' = Host} = Answer1,
	Answer2 = update(Config, Session, Host, IMSI, MSISDN),
	#'3gpp_sy_SLA'{'Result-Code' = [ResultCode]} = Answer2.

snr_normal() ->
	Description = "Normal Spending-Status-Notification-Request (SNR)",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

snr_normal(Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	Session = session_id(Config),
	Answer1 = subscribe(Config, Session, IMSI, MSISDN),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	#'3gpp_sy_SLA'{'Session-Id' = Session,
			'Result-Code' = [ResultCode],
			'Policy-Counter-Status-Report' = PCSR} = Answer1,
	F = fun(#'3gpp_sy_Policy-Counter-Status-Report'{
					'Policy-Counter-Identifier' = Id,
					'Policy-Counter-Status' = Status}, Acc) ->
				PCI = #{policyCounterId => Id, currentStatus => Status},
				Acc#{Id => PCI}
	end,
	StatusInfos = lists:foldl(F, #{}, PCSR),
	SpendingLimitStatus = #{supi => "imsi-" ++ IMSI,
			statusInfos => StatusInfos},
	yes = global:register_name(Session, self()),
	ok = send_notification(Config, zj:encode(SpendingLimitStatus)),
	receive
		{Session, StatusInfos} ->
			StatusInfos
	after
		1000 ->
			ct:fail(timeout)
	end.

final_str() ->
	Description = "Final Session-Termination-Request (STR)",
	ct:comment(Description),
	[{userdata, [{doc, Description}]}].

final_str(Config) ->
	IMSI = "001001" ++ cse_test_lib:rand_dn(9),
	MSISDN = cse_test_lib:rand_dn(11),
	Session = session_id(Config),
	Answer1 = subscribe(Config, Session, IMSI, MSISDN),
	ResultCode = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
	#'3gpp_sy_SLA'{'Session-Id' = Session,
			'Result-Code' = [ResultCode],
			'Origin-Host' = Host} = Answer1,
	Answer2 = terminate(Config, Session, Host),
	#'3gpp_sy_STA'{'Result-Code' = [ResultCode]} = Answer2.

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
			{module, [?SY_APPLICATION_CALLBACK, #{}]},
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
			{module, [?SY_APPLICATION_CALLBACK, #{}]},
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

subscribe(Config, Session, IMSI, MSISDN) ->
	SLR = #'3gpp_sy_SLR'{
			'SL-Request-Type' = ?'3GPP_SY_SL-REQUEST-TYPE_INITIAL_REQUEST'},
	slr(Config, Session, IMSI, MSISDN, SLR).

update(Config, Session, Host, IMSI, MSISDN) ->
	SLR = #'3gpp_sy_SLR'{
			'Destination-Host' = [Host],
			'SL-Request-Type' = ?'3GPP_SY_SL-REQUEST-TYPE_INTERMEDIATE_REQUEST'},
	slr(Config, Session, IMSI, MSISDN, SLR).

slr(Config, Session, IMSI, MSISDN, SLR)
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
	diameter:call({?MODULE, client}, sy_app_test, SLR1, []).

terminate(Config, Session, Host) ->
	OriginHost = ?config(ct_host, Config),
	OriginRealm = ?config(ct_realm, Config),
	DestinationRealm = ?config(sut_realm, Config),
	STR = #'3gpp_sy_STR'{'Session-Id' = Session,
			'Auth-Application-Id' = 16777302,
			'Origin-Host' = OriginHost,
			'Origin-Realm' = OriginRealm,
			'Destination-Host' = [Host],
			'Destination-Realm' = DestinationRealm,
			'Termination-Cause' = ?'DIAMETER_BASE_TERMINATION-CAUSE_LOGOUT'},
	diameter:call({?MODULE, client}, sy_app_test, STR, []).

send_notification(Config, SpendingLimitStatus) ->
	Profile = ?config(iwf_profile, Config),
	URI = ?config(iwf_uri, Config),
	Accept = "application/json, application/problem+json",
	Headers = [{"accept", Accept}],
	ContentType = "application/json",
	RequestURL = list_to_binary([URI, <<"/notify">>]),
	Request = {RequestURL, Headers, ContentType, SpendingLimitStatus},
	{ok, {{_, 204, _}, _, []}} = httpc:request(post,
			Request, [], [], Profile),
	ok.

handle_request(#diameter_packet{errors = [], msg = Request} = _Packet,
		_ServiceName, {_, Capabilities} = _Peer)
		when is_record(Request, '3gpp_sy_SNR') ->
	handle_request1(Request, Capabilities).
handle_request1(#'3gpp_sy_SNR'{'Session-Id' = Session,
				'Auth-Application-Id' = 16777302,
				'SN-Request-Type' = [0],
				'Policy-Counter-Status-Report' = PCSR},
		#diameter_caps{origin_host = {OHost, _DHost},
				origin_realm = {ORealm, _DRealm}}) ->
	F = fun(#'3gpp_sy_Policy-Counter-Status-Report'{
					'Policy-Counter-Identifier' = Id,
					'Policy-Counter-Status' = Status}, Acc) ->
				PCI = #{policyCounterId => Id, currentStatus => Status},
				Acc#{Id => PCI}
	end,
	StatusInfos = lists:foldl(F, #{}, PCSR),
	global:send(Session, {Session, StatusInfos}),
	SNA = #'3gpp_sy_SNA'{'Session-Id' = Session,
			'Origin-Host' = OHost,
			'Origin-Realm' = ORealm,
			'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'},
	{reply, SNA}.

session_id(Config) ->
	Host = ?config(ct_host, Config),
	iolist_to_binary(diameter:session_id(Host)).

client_auth_service_opts(Config) ->
	Realm = ?config(ct_realm, Config),
	Host = ?config(ct_host, Config),
	Handler = {?MODULE, handle_request, []},
	Callbacks = #diameter_callback{handle_request = Handler},
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
					{module, #diameter_callback{}}]},
			{application, [{alias, sy_app_test},
					{dictionary, ?SY_APPLICATION_DICT},
					{module, Callbacks}]}].

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
					{module, #diameter_callback{}}]},
			{application, [{alias, auth_app_test},
					{dictionary, ?SY_APPLICATION_DICT},
					{module, #diameter_callback{}}]}].

