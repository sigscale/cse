%%% cse_snmp_SUITE.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2021 SigScale Global Inc.
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
%%%  @doc Test suite for public API of the {@link //ocs. ocs} application.
%%%
-module(cse_snmp_SUITE).
-copyright('Copyright (c) 2016 - 2021 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("diameter/include/diameter.hrl").

-define(BASE_APPLICATION_ID, 0).
-define(RO_APPLICATION_ID, 4).
-define(RO_APPLICATION, cse_diameter_ro_application).
-define(RO_APPLICATION_DICT, diameter_gen_3gpp_ro_application).
-define(RO_APPLICATION_CALLBACK, cse_diameter_ro_application_cb).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{userdata, [{doc, "Test suite for SNMP agent in SigScale CSE"}]},
	{require, snmp_mgr_agent, snmp},
	{default_config, snmp,
		[{start_agent, true},
		{agent_manager_ip, [127,0,0,1]},
		{agent_community, [{"public", "public", "ct", "", ""}]},
		{agent_vacm,
				[{vacmSecurityToGroup, usm, "ct", "ct"},
				{vacmSecurityToGroup, v2c, "ct", "ct"},
				{vacmAccess, "ct", "", any, noAuthNoPriv, exact, "restricted", "", "restricted"},
				{vacmAccess, "ct", "", usm, authNoPriv, exact, "internet", "internet", "internet"},
				{vacmAccess, "ct", "", usm, authPriv, exact, "internet", "internet", "internet"},
				{vacmViewTreeFamily, "internet", [1,3,6,1], included, null},
				{vacmViewTreeFamily, "restricted", [1,3,6,1], included, null}]},
		{agent_notify_def, [{"cttrap", "ct_tag", trap}]},
		{agent_target_address_def, [{"ct_user", transportDomainUdpIpv4, {[127,0,0,1], 5000},
				1500, 3, "ct_tag", "ct_params", "mgrEngine", [], 2048}]},
		{agent_target_param_def, [{"ct_params", v2c, v2c, "ct", noAuthNoPriv}]},
		{start_manager, true}]},
	{require, snmp_app},
	{default_config, snmp_app,
			[{manager,
					[{config, [{verbosity, silence}]},
					{server, [{verbosity, silence}]},
					{notestore, [{verbosity, silence}]},
					{net_if, [{verbosity, silence}]}]},
			{agent,
					[{config, [{verbosity, silence}]},
					{agent_verbosity, silence},
					{net_if, [{verbosity, silence}]}]}]}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
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
	ok = ct_snmp:start(Config, snmp_mgr_agent, snmp_app),
	DiameterAddress = ct:get_config({diameter, diameter_address}, {127,0,0,1}),
	DiameterPort = ct:get_config({diameter, diameter_port}, rand:uniform(64511) + 1024),
	ServiceName = ct:get_config({diameter, diameter_service},  atom_to_list(?MODULE)),
	DiameterApplication = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	Realm = ct:get_config({diameter, realm}, "mnc001.mcc001.3gppnetwork.org"),
	Host = ct:get_config({diameter, host}, ServiceName ++ "." ++ Realm),
	DiameterOptions = [{application, DiameterApplication}, {'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]}],
	DiameterAppVar = [{DiameterAddress, DiameterPort, DiameterOptions}],
	ok = application:set_env(cse, diameter, DiameterAppVar),
   Config1 = [{diameter_host, Host}, {realm, Realm},
         {diameter_address, DiameterAddress}, {diameter_port, DiameterPort},
			{diameter_service, ServiceName} | Config],
	Alarms = [{dbpPeerConnectionUpNotif, []}, {dbpPeerConnectionDownNotif, []}],
	ok = application:set_env(cse, snmp_alarms, Alarms),
	ok = cse_test_lib:start(),
   ok = diameter:start_service(ServiceName, client_service_opts(Config1)),
	true = diameter:subscribe(ServiceName),
	Config1.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = ct_snmp:stop(Config),
	ok = cse_test_lib:stop().

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	AgentConf = [{ct_agent, ["ct_user", {127,0,0,1}, 4000, [
			{engine_id, "agentEngine"}, {taddress, {[127,0,0,1], 5000}},
			{community, "public"}, {version, v2}, {sec_model, v2c}, {sec_name, "ct"},
			{sec_level, noAuthNoPriv}]]}],
	UsersConf = [{"ct_user", [cse_snmpm_cb, self()]}],
	case ct_snmp:register_users(snmp_mgr_agent, UsersConf) of
		ok ->
			ok;
		_  ->
			ok = ct_snmp:unregister_users(snmp_mgr_agent),
			ok = ct_snmp:register_users(snmp_mgr_agent, UsersConf)
	end,
	case ct_snmp:register_agents(snmp_mgr_agent, AgentConf) of
		ok ->
			ok;
		_ ->
			ok = ct_snmp:unregister_agents(snmp_mgr_agent),
			ok = ct_snmp:register_agents(snmp_mgr_agent, AgentConf)
	end,
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
	[peer_up, peer_down].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

peer_up() ->
	[{userdata, [{doc, "Test suite for SNMP manager in SigScale CSE"}]}].

peer_up(Config) ->
	ServiceName = ?config(diameter_service, Config),
	DiameterAddress = ?config(diameter_address, Config),
	DiameterPort = ?config(diameter_port, Config),
   {ok, _Ref2} = connect(ServiceName, DiameterAddress, DiameterPort, diameter_tcp),
	receive
		ok ->
			ok = diameter:remove_transport(ServiceName, true);
		{error, Reason} ->
			ct:fail(Reason)
	after
		4000 ->
			ct:fail(timeout)
	end.

peer_down() ->
	[{userdata, [{doc, "Test suite for SNMP manager in SigScale CSE"}]}].

peer_down(Config) ->
	ServiceName = ?config(diameter_service, Config),
	DiameterAddress = ?config(diameter_address, Config),
	DiameterPort = ?config(diameter_port, Config),
   {ok, _Ref2} = connect(ServiceName, DiameterAddress, DiameterPort, diameter_tcp),
	receive
		ok ->
			peer_down1(ServiceName);
		{error, Reason} ->
			ct:fail(Reason)
	after
		4000 ->
			ct:fail(timeout)
	end.
%% @hidden
peer_down1(ServiceName) ->
	ok = diameter:remove_transport(ServiceName, true),
	receive
		ok ->
			ok;
		{error, Reason} ->
			ct:fail(Reason)
	after
		4000 ->
			ct:fail(timeout)
	end.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

%% @hidden
client_service_opts(Config) ->
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

%% @doc Add a transport capability to diameter service.
%% @hidden
connect(SvcName, Address, Port, Transport) when is_atom(Transport) ->
	connect(SvcName, [{connect_timer, 30000} | transport_opts(Address, Port, Transport)]).

%% @hidden
connect(SvcName, Opts)->
	diameter:add_transport(SvcName, {connect, Opts}).

