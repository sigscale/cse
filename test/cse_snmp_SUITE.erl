%%% cse_snmp_SUITE.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016-2025 SigScale Global Inc.
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
-copyright('Copyright (c) 2016-2025 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([get_id/0, get_id/1,
		get_realm/0, get_realm/1,
		get_host/0, get_host/1,
		get_uptime/0, get_uptime/1,
		get_count_in/0, get_count_in/1,
		get_count_out/0, get_count_out/1,
		peer_up/0, peer_up/1,
		get_next_peers/0, get_next_peers/1,
		get_next_stats/0, get_next_stats/1,
		peer_down/0, peer_down/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("diameter/include/diameter.hrl").

-define(BASE_APPLICATION_ID, 0).
-define(RO_APPLICATION_ID, 4).
-define(RO_APPLICATION, cse_diameter_3gpp_ro_application).
-define(RO_APPLICATION_DICT, diameter_gen_3gpp_ro_application).
-define(RO_APPLICATION_CALLBACK, cse_diameter_3gpp_ro_application_cb).
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
	{timetrap, {minutes, 1}},
	{require, diameter},
	{default_config, diameter,
			[{address, {127,0,0,1}}]},
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
	ok = ct_snmp:start(Config, snmp_mgr_agent, snmp_app),
	DiameterAddress = ct:get_config({diameter, diameter_address}, {127,0,0,1}),
	DiameterPort = ct:get_config({diameter, diameter_port}, rand:uniform(64511) + 1024),
	DiameterApplication = [{alias, ?RO_APPLICATION},
			{dictionary, ?RO_APPLICATION_DICT},
			{module, ?RO_APPLICATION_CALLBACK},
			{request_errors, callback}],
	Realm = ct:get_config({diameter, realm}, "mnc001.mcc001.3gppnetwork.org"),
	Host = ct:get_config({diameter, host}, "ct." ++ Realm),
	DiameterOptions = [{application, DiameterApplication},
			{'Origin-Realm', Realm},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]}],
	DiameterAppVar = [{DiameterAddress, DiameterPort, DiameterOptions}],
	ok = application:set_env(cse, diameter, DiameterAppVar),
   Config1 = [{diameter_host, Host}, {realm, Realm},
         {diameter_address, DiameterAddress},
			{diameter_port, DiameterPort} | Config],
	Alarms = [{dbpPeerConnectionUpNotif, []}, {dbpPeerConnectionDownNotif, []}],
	ok = application:set_env(cse, snmp_alarms, Alarms),
	ok = cse_test_lib:start(),
	true = diameter:subscribe(?MODULE),
   ok = diameter:start_service(?MODULE, client_service_opts(Config1)),
	receive
		#diameter_event{service = ?MODULE, info = start} ->
			Config1
	end.

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
	AgentConf = [{ct_agent, ["ct_user", {127,0,0,1}, 4000,
			[{engine_id, "agentEngine"}, {community, "public"}, {version, v2},
			{sec_model, v2c}, {sec_name, "ct"}, {sec_level, noAuthNoPriv}]]}],
	UsersConf = [{"ct_user", [cse_snmpm_cb, self()]}],
	ok = ct_snmp:register_users(snmp_mgr_agent, UsersConf),
	ok = ct_snmp:register_agents(snmp_mgr_agent, AgentConf),
	Config.

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, _Config) ->
	ok = ct_snmp:unregister_users(snmp_mgr_agent),
	ok = ct_snmp:unregister_agents(snmp_mgr_agent),
	ok = diameter:remove_transport(?MODULE, true).

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() ->
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() ->
	[get_id, get_realm, get_host, get_uptime, get_count_in, get_count_out,
			get_next_peers, get_next_stats, peer_up, peer_down].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

get_id() ->
	[{userdata, [{doc, "SNMP GET agent identity"}]}].

get_id(_Config) ->
	{value, DbpLocalId} = snmpa:name_to_oid(dbpLocalId),
	OID = DbpLocalId ++ [0],
	{noError, 0, [{_, _, 'OCTET STRING', "SigScale CSE", _}]}
			= ct_snmp:get_values(ct_agent, [OID], snmp_mgr_agent).

get_realm() ->
	[{userdata, [{doc, "SNMP GET DIAMETER Realm"}]}].

get_realm(_Config) ->
	{value, DbpLocalRealm} = snmpa:name_to_oid(dbpLocalRealm),
	OID = DbpLocalRealm ++ [0],
	{noError, 0, [{_, _, 'OCTET STRING', _DiameterRealm, _}]}
			= ct_snmp:get_values(ct_agent, [OID], snmp_mgr_agent).

get_host() ->
	[{userdata, [{doc, "SNMP GET DIAMETER Host"}]}].

get_host(_Config) ->
	{value, DbpLocalOriginHost} = snmpa:name_to_oid(dbpLocalOriginHost),
	OID = DbpLocalOriginHost ++ [0],
	{noError, 0, [{_, _, 'OCTET STRING', _DiameterHost, _}]}
			= ct_snmp:get_values(ct_agent, [OID], snmp_mgr_agent).

get_uptime() ->
	[{userdata, [{doc, "SNMP GET DIAMETER uptime"}]}].

get_uptime(_Config) ->
	{value, DbpLocalStatsTotalUpTime} = snmpa:name_to_oid(dbpLocalStatsTotalUpTime),
	OID = DbpLocalStatsTotalUpTime ++ [0],
	{noError, 0, [{_, _, 'TimeTicks', _Uptime, _}]}
			= ct_snmp:get_values(ct_agent, [OID], snmp_mgr_agent).

get_count_in() ->
	[{userdata, [{doc, "SNMP GET DIAMETER total incoming packet count"}]}].

get_count_in(_Config) ->
	{value, DbpLocalStatsTotalPacketsIn} = snmpa:name_to_oid(dbpLocalStatsTotalPacketsIn),
	OID = DbpLocalStatsTotalPacketsIn ++ [0],
	{noError, 0, [{_, _, 'Counter32', _CountIn, _}]}
			= ct_snmp:get_values(ct_agent, [OID], snmp_mgr_agent).

get_count_out() ->
	[{userdata, [{doc, "SNMP GET DIAMETER total incoming packet count"}]}].

get_count_out(_Config) ->
	{value, DbpLocalStatsTotalPacketsOut} = snmpa:name_to_oid(dbpLocalStatsTotalPacketsOut),
	OID = DbpLocalStatsTotalPacketsOut ++ [0],
	{noError, 0, [{_, _, 'Counter32', _CountOut, _}]}
			= ct_snmp:get_values(ct_agent, [OID], snmp_mgr_agent).

get_next_peers() ->
	[{userdata, [{doc, "SNMP GET DIAMETER peers table"}]}].

get_next_peers(Config) ->
	DiameterAddress = ?config(diameter_address, Config),
	DiameterPort = ?config(diameter_port, Config),
	{value, SnmpTrapOID} = snmpa:name_to_oid(snmpTrapOID),
	{value, DbpPeerConnectionUpNotif} = snmpa:name_to_oid(dbpPeerConnectionUpNotif),
	{value, DccaPeerTable} = snmpa:name_to_oid(dccaPeerTable),
	{value, DccaPeerEntry} = snmpa:name_to_oid(dccaPeerEntry),
	OID1 = SnmpTrapOID ++ [0],
	Reversed = lists:reverse(DccaPeerEntry),
   {ok, _Ref} = connect(?MODULE, DiameterAddress, DiameterPort, diameter_tcp),
	receive
		{noError, _, [_, {_, OID1, _, DbpPeerConnectionUpNotif, _} | _]} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end,
	F = fun F({noError, _, [{varbind, OID2, _Type, _Value, _}]}) ->
				case lists:reverse(OID2) of
					[_Column, _Index | Reversed] ->
						F(ct_snmp:get_next_values(ct_agent, [OID2], snmp_mgr_agent));
					_ ->
						ok
				end;
			F({noError, _, _}) ->
				ok
		end,
		F(ct_snmp:get_next_values(ct_agent, [DccaPeerTable], snmp_mgr_agent)).

get_next_stats() ->
	[{userdata, [{doc, "SNMP GET DIAMETER peer stats table"}]}].

get_next_stats(Config) ->
	DiameterAddress = ?config(diameter_address, Config),
	DiameterPort = ?config(diameter_port, Config),
	{value, SnmpTrapOID} = snmpa:name_to_oid(snmpTrapOID),
	{value, DbpPeerConnectionUpNotif} = snmpa:name_to_oid(dbpPeerConnectionUpNotif),
	{value, DccaPerPeerStatsTable} = snmpa:name_to_oid(dccaPerPeerStatsTable),
	{value, DccaPerPeerStatsEntry} = snmpa:name_to_oid(dccaPerPeerStatsEntry),
	OID1 = SnmpTrapOID ++ [0],
	Reversed = lists:reverse(DccaPerPeerStatsEntry),
   {ok, _Ref} = connect(?MODULE, DiameterAddress, DiameterPort, diameter_tcp),
	receive
		{noError, _, [_, {_, OID1, _, DbpPeerConnectionUpNotif, _} | _]} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end,
	F = fun F({noError, _, [{varbind, OID2, 'Counter32', _Value, _}]}) ->
				case lists:reverse(OID2) of
					[_Column, _Index | Reversed] ->
						F(ct_snmp:get_next_values(ct_agent, [OID2], snmp_mgr_agent));
					_ ->
						ok
				end;
			F({noError, _, _}) ->
				ok
		end,
		F(ct_snmp:get_next_values(ct_agent, [DccaPerPeerStatsTable], snmp_mgr_agent)).

peer_up() ->
	[{userdata, [{doc, "Recieve SNMP Notification for Diameter Peer UP"}]}].

peer_up(Config) ->
	DiameterHost = ?config(diameter_host, Config),
	DiameterAddress = ?config(diameter_address, Config),
	DiameterPort = ?config(diameter_port, Config),
	{value, SysUpTime} = snmpa:name_to_oid(sysUpTime),
	{value, SnmpTrapOID} = snmpa:name_to_oid(snmpTrapOID),
	{value, DbpPeerConnectionUpNotif} = snmpa:name_to_oid(dbpPeerConnectionUpNotif),
	{value, DbpLocalId} = snmpa:name_to_oid(dbpLocalId),
	{value, DbpPeerId} = snmpa:name_to_oid(dbpPeerId),
	OID1 = SysUpTime ++ [0],
	OID2 = SnmpTrapOID ++ [0],
	OID3 = DbpLocalId ++ [0],
	OID4 = DbpPeerId ++ [0],
   {ok, _Ref} = connect(?MODULE, DiameterAddress, DiameterPort, diameter_tcp),
	receive
		{noError, 0, Varbinds} ->
			[{_, OID1, 'TimeTicks', _, _},
					{_, OID2, 'OBJECT IDENTIFIER', DbpPeerConnectionUpNotif, _},
					{_, OID3, 'OCTET STRING', "SigScale CSE", _},
					{_, OID4, 'OCTET STRING', DiameterHost, _}] = Varbinds;
		{error, Reason} ->
			ct:fail(Reason)
	after
		4000 ->
			ct:fail(timeout)
	end.

peer_down() ->
	[{userdata, [{doc, "Recieve SNMP Notification for Diameter Peer Down"}]}].

peer_down(Config) ->
	DiameterHost = ?config(diameter_host, Config),
	DiameterAddress = ?config(diameter_address, Config),
	DiameterPort = ?config(diameter_port, Config),
	{value, SysUpTime} = snmpa:name_to_oid(sysUpTime),
	{value, SnmpTrapOID} = snmpa:name_to_oid(snmpTrapOID),
	{value, DbpPeerConnectionUpNotif} = snmpa:name_to_oid(dbpPeerConnectionUpNotif),
	{value, DbpPeerConnectionDownNotif} = snmpa:name_to_oid(dbpPeerConnectionDownNotif),
	{value, DbpLocalId} = snmpa:name_to_oid(dbpLocalId),
	{value, DbpPeerId} = snmpa:name_to_oid(dbpPeerId),
	OID1 = SysUpTime ++ [0],
	OID2 = SnmpTrapOID ++ [0],
	OID3 = DbpLocalId ++ [0],
	OID4 = DbpPeerId ++ [0],
	true = diameter:subscribe(?MODULE),
   {ok, Ref} = connect(?MODULE, DiameterAddress, DiameterPort, diameter_tcp),
	receive
      #diameter_event{service = ?MODULE, info = Info}
            when element(1, Info) == up ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end,
	receive
		{noError, 0, [_, {_, OID2, _, DbpPeerConnectionUpNotif, _} | _]} ->
			ok
	after
		4000 ->
			ct:fail(timeout)
	end,
	ok = diameter:remove_transport(?MODULE, Ref),
	receive
		{noError, 0, Varbinds} ->
			[{_, OID1, 'TimeTicks', _, _},
					{_, OID2, 'OBJECT IDENTIFIER', DbpPeerConnectionDownNotif, _},
					{_, OID3, 'OCTET STRING', "SigScale CSE", _},
					{_, OID4, 'OCTET STRING', DiameterHost, _}] = Varbinds;
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
			{'Product-Name', "SigScale CSE Test Client"},
			{'Auth-Application-Id', [?RO_APPLICATION_ID]},
			{string_decode, false},
			{restrict_connections, false},
			{application, [{alias, base_app_test},
					{dictionary, diameter_gen_base_rfc6733},
					{module, cse_test_diameter_cb}]},
			{application, [{alias, cc_app_test},
					{dictionary, diameter_gen_3gpp_ro_application},
					{module, cse_test_diameter_cb}]}].

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

