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

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("inets/include/mod_auth.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("cse/include/diameter_gen_ietf.hrl").
-include_lib("cse/include/diameter_gen_3gpp.hrl").
-include_lib("cse/include/diameter_gen_3gpp_ro_application.hrl").
-include_lib("cse/include/diameter_gen_cc_application_rfc4006.hrl").

-define(MILLISECOND, millisecond).
-define(RO_APPLICATION, cse_diameter_ro_application).
-define(RO_APPLICATION_DICT, diameter_gen_3gpp_ro_application).
-define(RO_APPLICATION_CALLBACK, cse_diameter_ro_application_cb).
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
	{default_config, diameter, [{address, {127,0,0,1}}]},
   {timetrap, {minutes, 10}},
	{require, rest},
	{default_config, rest, [{user, "nrf"},
			{password, "4yjhe6ydsrh4"}]}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	ok = cse_test_lib:unload(mnesia),
	DataDir = ?config(priv_dir, Config),
	ok = cse_test_lib:load(mnesia),
	ok = application:set_env(mnesia, dir, DataDir),
	ok = cse_test_lib:unload(cse),
	ok = cse_test_lib:load(cse),
	ok = cse_test_lib:init_tables(),
	init_per_suite1(Config).
%% @hidden
init_per_suite1(Config) ->
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
   ok = diameter:start_service(?MODULE, client_acct_service_opts(Config1)),
   true = diameter:subscribe(?MODULE),
   {ok, _Ref2} = connect(?MODULE, DiameterAddress, DiameterPort, diameter_tcp),
   receive
      #diameter_event{service = ?MODULE, info = Info}
            when element(1, Info) == up ->
			init_per_suite2(Config1);
      _Other ->
         {skip, diameter_client_service_not_started}
   end.
init_per_suite2(Config) ->
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
			init_per_suite3(Config1);
		{error, InetsReason} ->
			ct:fail(InetsReason)
	end.
%% @hidden
init_per_suite3(Config) ->
	case gen_server:start({local, ocs}, cse_test_ocs_server, [], []) of
		{ok, Pid} ->
			[{ocs_server, Pid} | Config];
		{error, Reason} ->
			ct:fail(Reason)
	end.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = cse_test_lib:stop(),
	OCSServer = ?config(ocs_server, Config),
	ok = gen_server:stop(OCSServer),
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
	[send_initial_scur, receive_initial_scur, send_interim_scur,
			receive_interim_scur].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

send_initial_scur() ->
	[{userdata, [{doc, "On received SCUR CCR-I send startRating"}]}].

send_initial_scur(Config) ->
	Server = ?config(ocs_server, Config),
	Subscriber = generate_identity(7),
	Balance = rand:uniform(100000),
	MSISDN = list_to_binary(Subscriber),
	IMSI = list_to_binary(generate_identity(7)),
	{ok, {Subscriber, Balance}} = gen_server:call(Server, {add_subscriber, Subscriber, Balance}),
	Subscriber1 = {MSISDN, IMSI},
	Ref = erlang:ref_to_list(make_ref()),
	SId = diameter:session_id(Ref),
	RequestNum = 0,
	Answer0 = diameter_scur_start(SId, Subscriber1, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer0.

receive_initial_scur(Config) ->
	Server = ?config(ocs_server, Config),
	Subscriber = generate_identity(7),
	Balance = rand:uniform(100000),
	MSISDN = list_to_binary(Subscriber),
	IMSI = list_to_binary(generate_identity(7)),
	{ok, {Subscriber, Balance}} = gen_server:call(Server, {add_subscriber, Subscriber, Balance}),
	Subscriber1 = {MSISDN, IMSI},
	Ref = erlang:ref_to_list(make_ref()),
	SId = diameter:session_id(Ref),
	RequestNum = 0,
	Answer0 = diameter_scur_start(SId, Subscriber1, RequestNum),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Multiple-Services-Credit-Control' = [MultiServices_CC]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GrantedUnits]} = MultiServices_CC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [TotalOctets]} = GrantedUnits,
	{ok, {Subscriber, NewBalance}} = gen_server:call(Server, {get_subscriber, Subscriber}),
	Balance = NewBalance + TotalOctets.

send_interim_scur() ->
	[{userdata, [{doc, "On received SCUR CCR-U send updateRating"}]}].

send_interim_scur(Config) ->
	Server = ?config(ocs_server, Config),
	Subscriber = generate_identity(7),
	Balance = rand:uniform(100000),
	MSISDN = list_to_binary(Subscriber),
	IMSI = list_to_binary(generate_identity(7)),
	{ok, {Subscriber, Balance}} = gen_server:call(Server, {add_subscriber, Subscriber, Balance}),
	Subscriber1 = {MSISDN, IMSI},
	Ref = erlang:ref_to_list(make_ref()),
	SId = diameter:session_id(Ref),
	RequestNum0 = 0,
	Answer0 = diameter_scur_start(SId, Subscriber1, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer0,
	RequestNum1 = RequestNum0 + 1,
	InputOctets2 = rand:uniform(100),
	OutputOctets2 = rand:uniform(200),
	UsedServiceUnits = {InputOctets2, OutputOctets2},
	Answer1 = diameter_scur_interim(SId, Subscriber1, RequestNum1, UsedServiceUnits),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer1.

receive_interim_scur() ->
	[{userdata, [{doc, "On SCUR updateRating response send CCA-U"}]}].

receive_interim_scur(Config) ->
	Server = ?config(ocs_server, Config),
	Subscriber = generate_identity(7),
	Balance = rand:uniform(100000),
	MSISDN = list_to_binary(Subscriber),
	IMSI = list_to_binary(generate_identity(7)),
	{ok, {Subscriber, Balance}} = gen_server:call(Server, {add_subscriber, Subscriber, Balance}),
	Subscriber1 = {MSISDN, IMSI},
	Ref = erlang:ref_to_list(make_ref()),
	SId = diameter:session_id(Ref),
	RequestNum0 = 0,
	Answer0 = diameter_scur_start(SId, Subscriber1, RequestNum0),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum0,
			'Multiple-Services-Credit-Control' = [MCC]} = Answer0,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GrantedUnits]} = MCC,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [TotalOctets]} = GrantedUnits,
	{ok, {Subscriber, NewBalance}} = gen_server:call(Server, {get_subscriber, Subscriber}),
	Balance = NewBalance + TotalOctets,
	RequestNum1 = RequestNum0 + 1,
	InputOctets = rand:uniform(100),
	OutputOctets = rand:uniform(200),
	UsedServiceUnits = {InputOctets, OutputOctets},
	Answer1 = diameter_scur_interim(SId, Subscriber1, RequestNum1, UsedServiceUnits),
	#'3gpp_ro_CCA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
			'CC-Request-Number' = RequestNum1,
			'Multiple-Services-Credit-Control' = [MCC1]} = Answer1,
	#'3gpp_ro_Multiple-Services-Credit-Control'{
			'Granted-Service-Unit' = [GrantedUnits1]} = MCC1,
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [TotalOctets1]} = GrantedUnits1,
	{ok, {Subscriber, NewBalance1}} = gen_server:call(Server, {get_subscriber, Subscriber}),
	TotalRSU = TotalOctets + TotalOctets1,
	TotalUSU = InputOctets + OutputOctets,
	Balance = TotalRSU + TotalUSU + NewBalance1.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

diameter_scur_start(SId, {MSISDN, IMSI}, RequestNum) ->
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	RequestedUnits = #'3gpp_ro_Requested-Service-Unit' {
			'CC-Total-Octets' = []},
	MultiServices_CC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Requested-Service-Unit' = [RequestedUnits], 'Service-Identifier' = [1],
			'Rating-Group' = [2]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'PS-Information' =
			[#'3gpp_ro_PS-Information'{
					'3GPP-PDP-Type' = [3],
					'Serving-Node-Type' = [2],
					'SGSN-Address' = [{10,1,2,3}],
					'GGSN-Address' = [{10,4,5,6}],
					'3GPP-IMSI-MCC-MNC' = [<<"001001">>],
					'3GPP-GGSN-MCC-MNC' = [<<"001001">>],
					'3GPP-SGSN-MCC-MNC' = [<<"001001">>]}]},
	CC_CCR = #'3gpp_ro_CCR'{'Session-Id' = SId,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Service-Context-Id' = "32251@3gpp.org",
			'User-Name' = [MSISDN],
			'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
			'CC-Request-Number' = RequestNum,
			'Event-Timestamp' = [calendar:universal_time()],
			'Subscription-Id' = [MSISDN1, IMSI1],
			'Multiple-Services-Credit-Control' = [MultiServices_CC],
			'Service-Information' = [ServiceInformation]},
	{ok, Answer} = diameter:call(?MODULE, cc_app_test, CC_CCR, []),
	Answer.

diameter_scur_interim(SId, {MSISDN, IMSI}, RequestNum,
		{UsedInputOctets, UsedOutputOctets}) ->
	MSISDN1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
	IMSI1 = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = IMSI},
	UsedUnits = #'3gpp_ro_Used-Service-Unit'{
			'CC-Input-Octets' = [UsedInputOctets], 'CC-Output-Octets' = [UsedOutputOctets],
			'CC-Total-Octets' = [UsedInputOctets + UsedOutputOctets]},
	RequestedUnits = #'3gpp_ro_Requested-Service-Unit' {
			'CC-Total-Octets' = []},
	MCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
			'Used-Service-Unit' = [UsedUnits],
			'Requested-Service-Unit' = [RequestedUnits], 'Service-Identifier' = [1],
			'Rating-Group' = [2]},
	ServiceInformation = #'3gpp_ro_Service-Information'{'PS-Information' =
			[#'3gpp_ro_PS-Information'{
					'3GPP-PDP-Type' = [3],
					'Serving-Node-Type' = [2],
					'SGSN-Address' = [{10,1,2,3}],
					'GGSN-Address' = [{10,4,5,6}],
					'3GPP-IMSI-MCC-MNC' = [<<"001001">>],
					'3GPP-GGSN-MCC-MNC' = [<<"001001">>],
					'3GPP-SGSN-MCC-MNC' = [<<"001001">>]}]},
	CC_CCR = #'3gpp_ro_CCR'{'Session-Id' = SId,
		'Auth-Application-Id' = ?RO_APPLICATION_ID,
		'Service-Context-Id' = "32251@3gpp.org",
		'User-Name' = [MSISDN],
		'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
		'CC-Request-Number' = RequestNum,
		'Event-Timestamp' = [calendar:universal_time()],
		'Multiple-Services-Credit-Control' = [MCC],
		'Subscription-Id' = [MSISDN1, IMSI1],
		'Service-Information' = [ServiceInformation]},
	{ok, Answer} = diameter:call(?MODULE, cc_app_test, CC_CCR, []),
	Answer.

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

-spec generate_identity(Length) -> string()
	when
		Length :: pos_integer().
%% @doc Generate a random uniform numeric identity.
%% @private
generate_identity(Length) when Length > 0 ->
	Charset = lists:seq($0, $9),
	NumChars = length(Charset),
	Random = crypto:strong_rand_bytes(Length),
	generate_identity(Random, Charset, NumChars,[]).
%% @hidden
generate_identity(<<N, Rest/binary>>, Charset, NumChars, Acc) ->
	CharNum = (N rem NumChars) + 1,
	NewAcc = [lists:nth(CharNum, Charset) | Acc],
	generate_identity(Rest, Charset, NumChars, NewAcc);
generate_identity(<<>>, _Charset, _NumChars, Acc) ->
	Acc.

