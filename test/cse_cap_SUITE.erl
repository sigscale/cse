%%% cse_cap_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2023 SigScale Global Inc.
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
%%% Test suite for the Transaction Capabilities stack with
%%% CAMEL Application Part (CAP) integration of the
%%% {@link //cse. cse} application.
%%%
-module(cse_cap_SUITE).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([start_dialogue/0, start_dialogue/1,
		end_dialogue/0, end_dialogue/1,
		initial_dp_mo/0, initial_dp_mo/1,
		initial_dp_mt/0, initial_dp_mt/1,
		continue/0, continue/1,
		dp_arming/0, dp_arming/1,
		apply_charging/0, apply_charging/1,
		call_info_request/0, call_info_request/1,
		mo_abandon/0, mo_abandon/1,
		mt_abandon/0, mt_abandon/1,
		mo_answer/0, mo_answer/1,
		mt_answer/0, mt_answer/1,
		mo_disconnect/0, mo_disconnect/1,
		mt_disconnect/0, mt_disconnect/1]).

-include_lib("sccp/include/sccp.hrl").
-include_lib("tcap/include/sccp_primitive.hrl").
-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("map/include/MAP-MS-DataTypes.hrl").
-include_lib("cap/include/CAP-operationcodes.hrl").
-include_lib("cap/include/CAP-object-identifiers.hrl").
-include_lib("cap/include/CAP-gsmSSF-gsmSCF-pkgs-contracts-acs.hrl").
-include_lib("cap/include/CAP-datatypes.hrl").
-include_lib("cap/include/CAMEL-datatypes.hrl").
-include("cse_codec.hrl").
-include_lib("common_test/include/ct.hrl").

-define(SSN_CAP, 146).
-define(Pkgs, 'CAP-gsmSSF-gsmSCF-pkgs-contracts-acs').
-define(PDUs, 'GenericSSF-gsmSCF-PDUs').

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	[{timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before the whole suite.
%%
init_per_suite(Config) ->
	ok = cse_test_lib:unload(mnesia),
	DataDir = ?config(priv_dir, Config),
	ok = cse_test_lib:load(mnesia),
	ok = application:set_env(mnesia, dir, DataDir),
	ok = cse_test_lib:unload(cse),
	ok = cse_test_lib:load(cse),
	Callback = callback(cse_tco_server_cb),
	ok = application:set_env(cse, tsl_callback, Callback),
	{ok, TslArgs} = application:get_env(cse, tsl_args),
	ok = application:set_env(cse, tsl_args, [{?MODULE, undefined} | TslArgs]),
	ok = cse_test_lib:init_tables(),
	ok = cse_test_lib:start(),
	EDP = #{abandon => notifyAndContinue,
			answer => notifyAndContinue,
			busy => interrupted,
			disconnect1 => interrupted,
			disconnect2 => interrupted,
			no_answer => interrupted,
			route_fail => interrupted},
	ServiceKey = rand:uniform(2147483647),
	Data = #{edp => EDP},
	Opts = [],
	ok = cse:add_service(ServiceKey, cse_slp_prepaid_cap_fsm, Data, Opts),
	{ok, TCO} = application:get_env(cse, tsl_name),
	Config1 = [{tco, TCO}, {service_key, ServiceKey} | Config],
	init_per_suite1(Config1).
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

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initiation before each test case.
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
	[start_dialogue, end_dialogue, initial_dp_mo, initial_dp_mt,
			continue, dp_arming, apply_charging, call_info_request,
			mo_abandon, mt_abandon, mo_answer, mt_answer,
			mo_disconnect, mt_disconnect].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

start_dialogue() ->
	[{userdata, [{doc, "Start a TCAP Dialogue"}]}].

start_dialogue(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2,
			sequenceControl = true,
			returnOption = true,
			calledAddress = SsfParty,
			callingAddress = ScfParty} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<_ScfTid:32>>,
			dtid = <<SsfTid:32>>,
			dialoguePortion = DialoguePortion,
			components = _Components} = Continue,
	#'EXTERNAL'{'direct-reference' = {0,0,17,773,1,1,1},
			encoding = {'single-ASN1-type', DialoguePDUs}} = DialoguePortion,
	{ok, {dialogueResponse, AARE}} = 'DialoguePDUs':decode('DialoguePDU',
			DialoguePDUs),
	#'AARE-apdu'{'application-context-name' = AC,
			'result-source-diagnostic' = {'dialogue-service-user', null},
			result = Result} = AARE,
	accepted = Result.

end_dialogue() ->
	[{userdata, [{doc, "End a TCAP Dialogue"}]}].

end_dialogue(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	MonitorRef = receive
		{csl, DHA, _TCU} ->
			monitor(process, DHA)
	end,
	End = #'GenericSSF-gsmSCF-PDUs_end'{dtid = <<ScfTid:32>>},
	{ok, UserData3} = ?Pkgs:encode(?PDUs, {'end',  End}),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	receive
		{'DOWN', MonitorRef, _, _, normal} -> ok
	end.

initial_dp_mo() ->
	[{userdata, [{doc, "MO InitialDP received by SLPI"}]}].

initial_dp_mo(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	TcUser = receive
		{csl, _DHA, TCU} -> TCU
	end,
	receive
		{'N', 'UNITDATA', request, #'N-UNITDATA'{}} -> ok
	end,
	analyse_information = get_state(TcUser).

initial_dp_mt() ->
	[{userdata, [{doc, "MT InitialDP received by SLPI"}]}].

initial_dp_mt(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mt(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	TcUser = receive
		{csl, _DHA, TCU} -> TCU
	end,
	receive
		{'N', 'UNITDATA', request, #'N-UNITDATA'{}} -> ok
	end,
	terminating_call_handling = get_state(TcUser).

continue() ->
	[{userdata, [{doc, "Continue received by SSF"}]}].

continue(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{components = Components} = Continue,
	{basicROS, {invoke, Invoke}} = lists:last(Components),
	N = #'GenericSCF-gsmSSF-PDUs_continue_components_SEQOF_basicROS_invoke'.opcode,
	?'opcode-continue' = element(N, Invoke).

dp_arming() ->
	[{userdata, [{doc, "RequestReportBCSMEvent received by SSF"}]}].

dp_arming(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{components = Components} = Continue,
	N = #'GenericSCF-gsmSSF-PDUs_continue_components_SEQOF_basicROS_invoke'.opcode,
	F1 = fun({basicROS, {invoke, Invoke}})
					when element(N, Invoke) == ?'opcode-requestReportBCSMEvent' ->
				true;
			(_) -> false
	end,
	[{basicROS, {invoke, I}}] = lists:filter(F1, Components),
	A = I#'GenericSSF-gsmSCF-PDUs_continue_components_SEQOF_basicROS_invoke'.argument,
	BCSMEvents = A#'GenericSSF-gsmSCF-PDUs_RequestReportBCSMEventArg'.bcsmEvents,
	F2 = fun(#'BCSMEvent'{}) ->
				true;
			(_) ->
				false
	end,
	true = lists:all(F2, BCSMEvents).

apply_charging() ->
	[{userdata, [{doc, "ApplyCharging received by SSF"}]}].

apply_charging(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{components = Components} = Continue,
	N = #'GenericSCF-gsmSSF-PDUs_continue_components_SEQOF_basicROS_invoke'.opcode,
	F1 = fun({basicROS, {invoke, Invoke}})
					when element(N, Invoke) == ?'opcode-applyCharging' ->
				true;
			(_) -> false
	end,
	[{basicROS, {invoke, I}}] = lists:filter(F1, Components),
	A = I#'GenericSSF-gsmSCF-PDUs_continue_components_SEQOF_basicROS_invoke'.argument,
	{sendingSideID, ?leg1} = A#'GenericSSF-gsmSCF-PDUs_ApplyChargingArg'.partyToCharge,
	PDUs = A#'GenericSSF-gsmSCF-PDUs_ApplyChargingArg'.aChBillingChargingCharacteristics,
	{ok, {_, TD}} = 'CAMEL-datatypes':decode('PduAChBillingChargingCharacteristics', PDUs),
	P = TD#'PduAChBillingChargingCharacteristics_timeDurationCharging'.maxCallPeriodDuration,
	true = is_integer(P).

call_info_request() ->
	[{userdata, [{doc, "CallInformationRequest received by SSF"}]}].

call_info_request(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{components = Components} = Continue,
	N = #'GenericSCF-gsmSSF-PDUs_continue_components_SEQOF_basicROS_invoke'.opcode,
	F1 = fun({basicROS, {invoke, Invoke}})
					when element(N, Invoke) == ?'opcode-callInformationRequest' ->
				true;
			(_) -> false
	end,
	[{basicROS, {invoke, I}}] = lists:filter(F1, Components),
	A = I#'GenericSSF-gsmSCF-PDUs_continue_components_SEQOF_basicROS_invoke'.argument,
	L = A#'GenericSSF-gsmSCF-PDUs_CallInformationRequestArg'.requestedInformationTypeList,
	F = fun(Type) when Type == callAttemptElapsedTime; Type == callStopTime;
					Type == callConnectedElapsedTime; Type == releaseCause ->
				true;
			(_) ->
				false
	end,
	true = lists:all(F, L).

mo_abandon() ->
	[{userdata, [{doc, "EventReportBCSM:oAbandon received by SCF"}]}].

mo_abandon(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	MonitorRef = receive
		{csl, DHA, _TCU} ->
			monitor(process, DHA)
	end,
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD1} -> UD1
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_o_abandon(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	SccpParams4 = receive
		{'N', 'UNITDATA', request, UD2} -> UD2
	end,
	#'N-UNITDATA'{userData = UserData4} = SccpParams4,
	{ok, {'end', _End}} = ?Pkgs:decode(?PDUs, UserData4),
	receive
		{'DOWN', MonitorRef, _, _, normal} -> ok
	end.

mt_abandon() ->
	[{userdata, [{doc, "EventReportBCSM:tAbandon received by SCF"}]}].

mt_abandon(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mt(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	MonitorRef = receive
		{csl, DHA, _TCU} ->
			monitor(process, DHA)
	end,
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD1} -> UD1
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_t_abandon(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	SccpParams4 = receive
		{'N', 'UNITDATA', request, UD2} -> UD2
	end,
	#'N-UNITDATA'{userData = UserData4} = SccpParams4,
	{ok, {'end', _End}} = ?Pkgs:decode(?PDUs, UserData4),
	receive
		{'DOWN', MonitorRef, _, _, normal} -> ok
	end.

mo_answer() ->
	[{userdata, [{doc, "EventReportBCSM:oAnswer received by SCF"}]}].

mo_answer(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	TcUser = receive
		{csl, _DHA, TCU} -> TCU
	end,
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_o_answer(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	ct:sleep(500),
	o_active = get_state(TcUser).

mt_answer() ->
	[{userdata, [{doc, "EventReportBCSM:tAnswer received by SCF"}]}].

mt_answer(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mt(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	TcUser = receive
		{csl, _DHA, TCU} -> TCU
	end,
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_t_answer(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	ct:sleep(500),
	t_active = get_state(TcUser).

mo_disconnect() ->
	[{userdata, [{doc, "EventReportBCSM:oDisconnect received by SCF"}]}].

mo_disconnect(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mo(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	MonitorRef = receive
		{csl, DHA, _TCU} ->
			monitor(process, DHA)
	end,
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD1} -> UD1
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_o_answer(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	UserData4 = pdu_o_disconnect(SsfTid, ScfTid, 3),
	SccpParams4 = unitdata(UserData4, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams4}),
	SccpParams5 = receive
		{'N', 'UNITDATA', request, UD2} -> UD2
	end,
	#'N-UNITDATA'{userData = UserData5} = SccpParams5,
	{ok, {'end', _End}} = ?Pkgs:decode(?PDUs, UserData5),
	receive
		{'DOWN', MonitorRef, _, _, normal} -> ok
	end.

mt_disconnect() ->
	[{userdata, [{doc, "EventReportBCSM:tDisconnect received by SCF"}]}].

mt_disconnect(Config) ->
	OCS = ?config(ocs, Config),
	ServiceKey = ?config(service_key, Config),
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	IMSI = "001001" ++ cse_test_lib:rand_dn(10),
	Balance = rand:uniform(100) + 3600,
	{ok, {Balance, 0}} = gen_server:call(OCS, {add_subscriber, IMSI, Balance}),
	UserData1 = pdu_initial_mt(SsfTid, AC, ServiceKey, IMSI),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	MonitorRef = receive
		{csl, DHA, _TCU} ->
			monitor(process, DHA)
	end,
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD1} -> UD1
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_t_answer(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	UserData4 = pdu_t_disconnect(SsfTid, ScfTid, 3),
	SccpParams4 = unitdata(UserData4, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams4}),
	SccpParams5 = receive
		{'N', 'UNITDATA', request, UD2} -> UD2
	end,
	#'N-UNITDATA'{userData = UserData5} = SccpParams5,
	{ok, {'end', _End}} = ?Pkgs:decode(?PDUs, UserData5),
	receive
		{'DOWN', MonitorRef, _, _, normal} -> ok
	end.

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

-spec callback(Cb :: atom()) -> #tcap_tco_cb{}.
%% @doc Construct the callback fun() used as a wrapper around the
%% 	cse application's callback.
%% @hidden
callback(Cb) ->
	Finit = fun(Args) ->
			case Cb:init(Args) of
				{ok, State} ->
					{ok, {{?MODULE, undefined}, State}};
				{ok, State, Timeout} ->
					{ok, {{?MODULE, undefined}, State}, Timeout};
				{stop, Reason} ->
					{stop, Reason};
				ignore ->
					ignore
			end
	end,
	Fcall = fun(Request, From, {{?MODULE, Pid}, State}) ->
			case Cb:handle_call(Request, From, State) of
				{reply, Reply, NewState} ->
					{reply, Reply, {{?MODULE, Pid}, NewState}};
				{reply, Reply, NewState, Timeout} ->
					{reply, Reply, {{?MODULE, Pid}, NewState}, Timeout};
				{noreply, NewState} ->
					{noreply, {{?MODULE, Pid}, NewState}};
				{noreply, NewState, Timeout} ->
					{noreply, {{?MODULE, Pid}, NewState}, Timeout};
				{stop, Reason, NewState} ->
					{stop, Reason, {{?MODULE, Pid}, NewState}}
			end
	end,
	Fcast = fun(Request, {{?MODULE, Pid}, State}) ->
			case Cb:handle_cast(Request, State) of
				{noreply, NewState} ->
					{noreply, {{?MODULE, Pid}, NewState}};
				{noreply, NewState, Timeout} ->
					{noreply, {{?MODULE, Pid}, NewState}, Timeout};
				{stop, Reason, NewState} ->
					{stop, Reason, {{?MODULE, Pid}, NewState}};
				{primitive, Primitive, NewState} ->
					{primitive, Primitive, {{?MODULE, Pid}, NewState}}
			end
	end,
	Finfo = fun({?MODULE, Pid}, {{?MODULE, _}, State}) ->
				{noreply, {{?MODULE, Pid}, State}};
			(Info, {{?MODULE, Pid}, State}) ->
				case Cb:handle_info(Info, State) of
					{noreply, NewState} ->
						{noreply, {{?MODULE, Pid}, NewState}};
					{noreply, NewState, Timeout} ->
						{noreply, {{?MODULE, Pid}, NewState}, Timeout};
					{stop, Reason, NewState} ->
						{stop, Reason, {{?MODULE, Pid}, NewState}};
					{primitive, Primitive, NewState} ->
						{primitive, Primitive, {{?MODULE, Pid}, NewState}}
				end
	end,
	Fterm = fun(Reason, {{?MODULE, _}, State}) ->
			Cb:terminate(Reason, State)
	end,
	Fcont = fun(Info, {{?MODULE, Pid}, State}) ->
			case Cb:handle_continue(Info, State) of
				{noreply, NewState} ->
					{noreply, {{?MODULE, Pid}, NewState}};
				{noreply, NewState, Timeout} ->
					{noreply, {{?MODULE, Pid}, NewState}, Timeout};
				{stop, Reason, NewState} ->
					{stop, Reason, {{?MODULE, Pid}, NewState}}
			end
	end,
	Fsend = fun(Primitive, {{?MODULE, Pid}, State}) when is_pid(Pid) ->
			Pid ! Primitive,
			{noreply, {{?MODULE, Pid}, State}}
	end,
	Fstart = fun(DialoguePortion, {{?MODULE, Pid}, State}) ->
			case Cb:start_aei(DialoguePortion, State) of
				{ok, DHA, CCO, TCU, State} ->
					Pid ! {csl, DHA, TCU},
					{ok, DHA, CCO, TCU, {{?MODULE, Pid}, State}};
				{error, Reason} ->
					{error, Reason}
			end
	end,
	Fcode = fun(OldVersion, {{?MODULE, Pid}, State}, Extra) ->
			case Cb:code_change(OldVersion, State, Extra) of
				{ok, NewState} ->
					{ok, {{?MODULE, Pid}, NewState}};
				{error, Reason} ->
					{error, Reason}
			end
	end,
	Fstat = fun(Opt, [PDict | {{?MODULE, _Pid}, State}]) ->
			Cb:format_status(Opt, [PDict | State])
	end,
	#tcap_tco_cb{init = Finit,
		handle_call = Fcall,
		handle_cast =  Fcast,
		handle_info = Finfo,
		terminate = Fterm,
		handle_continue = Fcont,
		send_primitive = Fsend,
		start_aei = Fstart,
		code_change = Fcode,
		format_status = Fstat}.

get_state(Fsm) ->
	{_,_,_,[_,_,_,_,[_,_,{data,[{_,{State,_}}]}]]} = sys:get_status(Fsm),
	State.

tid() ->
	rand:uniform(4294967295).

party() ->
	party(4, [1,4,1,6,5,5,5]).
party(N, Acc) when length(Acc) < 11 ->
	party(N - 1, [rand:uniform(10) - 1 | Acc]);
party(0, Acc) ->
	#party_address{ssn = ?SSN_CAP,
			nai = international,
			translation_type = undefined,
			numbering_plan = isdn_tele,
			encoding_scheme = bcd_odd,
			gt = Acc}.

isup_called_party() ->
	isup_called_party(rand:uniform(7) + 6, []).
isup_called_party(N, Acc) when N > 0 ->
	isup_called_party(N - 1, [rand:uniform(10 - 1) | Acc]);
isup_called_party(0, Acc) ->
	CalledParty = #called_party{nai = 3, inn = 0, npi = 1, address = Acc},
	cse_codec:called_party(CalledParty).

isup_calling_party() ->
	isup_calling_party(rand:uniform(7) + 6, []).
isup_calling_party(N, Acc) when N > 0 ->
	isup_calling_party(N - 1, [rand:uniform(10 - 1) | Acc]);
isup_calling_party(0, Acc) ->
	CallingParty = #calling_party{nai = 4, ni = 0,
			npi = 1, apri = 0, si = 3, address = Acc},
	cse_codec:calling_party(CallingParty).

called_party_bcd() ->
	called_party_bcd(rand:uniform(7) + 6, []).
called_party_bcd(N, Acc) when N > 0 ->
	called_party_bcd(N - 1, [rand:uniform(10 - 1) | Acc]);
called_party_bcd(0, Acc) ->
	CalledParty = #called_party_bcd{ton = 2, npi = 1, address = Acc},
	cse_codec:called_party_bcd(CalledParty).

unitdata(UserData, CalledParty, CallingParty) ->
	#'N-UNITDATA'{userData = UserData,
			sequenceControl = true,
			returnOption = true,
			calledAddress = CalledParty,
			callingAddress = CallingParty}.

pdu_initial_mo(OTID, AC, ServiceKey, IMSI) ->
	AARQ = #'AARQ-apdu'{'application-context-name' = AC},
	{ok, DialoguePDUs} = 'DialoguePDUs':encode('DialoguePDU',
			{dialogueRequest, AARQ}),
	DialoguePortion = #'EXTERNAL'{'direct-reference' = {0,0,17,773,1,1,1},
			'indirect-reference' = asn1_NOVALUE,
			'data-value-descriptor' = asn1_NOVALUE,
			encoding = {'single-ASN1-type', DialoguePDUs}},
	LocationInformation = #'LocationInformation'{
			ageOfLocationInformation = 0,
			'vlr-number' = cse_codec:isdn_address(#isdn_address{nai = 1,
					npi = 1, address = "14165550000"}),
			cellGlobalIdOrServiceAreaIdOrLAI =
			{cellGlobalIdOrServiceAreaIdFixedLength, <<0,1,16,0,1,0,1>>}},
	InitialDPArg = #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{
			serviceKey = ServiceKey,
			callingPartyNumber = isup_calling_party(),
			callingPartysCategory = <<10>>,
			locationNumber = isup_calling_party(),
			bearerCapability = {bearerCap,<<128,144,163>>},
			eventTypeBCSM = collectedInfo,
			iMSI = cse_codec:tbcd(IMSI),
			locationInformation = LocationInformation,
			'ext-basicServiceCode' = {'ext-Teleservice', <<17>>},
			callReferenceNumber = crypto:strong_rand_bytes(4),
			mscAddress = cse_codec:isdn_address(#isdn_address{nai = 1,
               npi = 1, address = "14165550001"}),
			calledPartyBCDNumber = called_party_bcd(),
			timeAndTimezone = <<2,18,32,65,81,116,49,10>>},
	Invoke = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, 1},
			opcode = ?'opcode-initialDP',
			argument = InitialDPArg},
	Begin = #'GenericSSF-gsmSCF-PDUs_begin'{otid = <<OTID:32>>,
			dialoguePortion = DialoguePortion,
			components = [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'begin', Begin}),
	UD.

pdu_initial_mt(OTID, AC, ServiceKey, IMSI) ->
	AARQ = #'AARQ-apdu'{'application-context-name' = AC},
	{ok, DialoguePDUs} = 'DialoguePDUs':encode('DialoguePDU',
			{dialogueRequest, AARQ}),
	DialoguePortion = #'EXTERNAL'{'direct-reference' = {0,0,17,773,1,1,1},
			'indirect-reference' = asn1_NOVALUE,
			'data-value-descriptor' = asn1_NOVALUE,
			encoding = {'single-ASN1-type', DialoguePDUs}},
	LocationInformation = #'LocationInformation'{
			ageOfLocationInformation = 0,
			'vlr-number' = cse_codec:isdn_address(#isdn_address{nai = 1,
					npi = 1, address = "14165550000"}),
			cellGlobalIdOrServiceAreaIdOrLAI =
			{cellGlobalIdOrServiceAreaIdFixedLength, <<0,1,16,0,1,0,1>>}},
	InitialDPArg = #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{
			serviceKey = ServiceKey,
			calledPartyNumber = isup_called_party(),
			callingPartyNumber = isup_calling_party(),
			callingPartysCategory = <<10>>,
			locationNumber = isup_calling_party(),
			bearerCapability = {bearerCap,<<128,144,163>>},
			eventTypeBCSM = termAttemptAuthorized,
			iMSI = cse_codec:tbcd(IMSI),
			locationInformation = LocationInformation,
			callReferenceNumber = crypto:strong_rand_bytes(4),
			mscAddress = cse_codec:isdn_address(#isdn_address{nai = 1,
               npi = 1, address = "14165550001"}),
			timeAndTimezone = <<2,18,32,65,81,116,49,10>>},
	Invoke = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, 1},
			opcode = ?'opcode-initialDP',
			argument = InitialDPArg},
	Begin = #'GenericSSF-gsmSCF-PDUs_begin'{otid = <<OTID:32>>,
			dialoguePortion = DialoguePortion,
			components = [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'begin', Begin}),
	UD.

pdu_o_abandon(OTID, DTID, InvokeID) ->
	SI = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg_eventSpecificInformationBCSM_oAbandonSpecificInfo'{
			routeNotPermitted = asn1_NOVALUE},
	EventReportArg = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{
			eventTypeBCSM = oAbandon,
			eventSpecificInformationBCSM = {oAbandonSpecificInfo, SI},
			legID = {receivingSideID, ?leg1},
			miscCallInfo = #{messageType => notification}},
	Invoke1 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID},
			opcode = ?'opcode-eventReportBCSM',
			argument = EventReportArg},
	ChargingResult = #'PduCallResult_timeDurationChargingResult'{
			partyToCharge = {receivingSideID, ?leg1},
			timeInformation = {timeIfNoTariffSwitch, 0}},
	{ok, ChargingResultArg} = 'CAMEL-datatypes':encode('PduCallResult',
			{timeDurationChargingResult, ChargingResult}),
	Invoke2 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 1},
			opcode = ?'opcode-applyChargingReport',
			argument = ChargingResultArg},
	RI1 = #'RequestedInformation'{
			requestedInformationType = callAttemptElapsedTime,
			requestedInformationValue = {callAttemptElapsedTimeValue, 0}},
	TV2 = cse_codec:date_time(calendar:universal_time()),
	RI2 = #'RequestedInformation'{
			requestedInformationType = callStopTime,
			requestedInformationValue = {callStopTimeValue, TV2}},
	RI3 = #'RequestedInformation'{
			requestedInformationType = callConnectedElapsedTime,
			requestedInformationValue = {callConnectedElapsedTimeValue, 0}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI4 = #'RequestedInformation'{
			requestedInformationType = releaseCause,
			requestedInformationValue = {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2, RI3, RI4],
	InfoReportArg = #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{
			legID = {receivingSideID, ?leg2},
			requestedInformationList = RequestedInformationList},
	Invoke3 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 2},
			opcode = ?'opcode-callInformationReport',
			argument = InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #'GenericSSF-gsmSCF-PDUs_continue'{
			otid = <<OTID:32>>,
			dtid = <<DTID:32>>,
			components = Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_t_abandon(OTID, DTID, InvokeID) ->
	EventReportArg = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{
			eventTypeBCSM = tAbandon,
			legID = {receivingSideID, ?leg2},
			miscCallInfo = #{messageType => notification}},
	Invoke1 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID},
			opcode = ?'opcode-eventReportBCSM',
			argument = EventReportArg},
	ChargingResult = #'PduCallResult_timeDurationChargingResult'{
			partyToCharge = {receivingSideID, ?leg2},
			timeInformation = {timeIfNoTariffSwitch, 0}},
	{ok, ChargingResultArg} = 'CAMEL-datatypes':encode('PduCallResult',
			{timeDurationChargingResult, ChargingResult}),
	Invoke2 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 1},
			opcode = ?'opcode-applyChargingReport',
			argument = ChargingResultArg},
	TV1 = cse_codec:date_time(calendar:universal_time()),
	RI1 = #'RequestedInformation'{
			requestedInformationType = callStopTime,
			requestedInformationValue = {callStopTimeValue, TV1}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI2 = #'RequestedInformation'{
			requestedInformationType = releaseCause,
			requestedInformationValue = {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2],
	InfoReportArg = #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{
			legID = {receivingSideID, ?leg2},
			requestedInformationList = RequestedInformationList},
	Invoke3 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 2},
			opcode = ?'opcode-callInformationReport',
			argument = InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #'GenericSSF-gsmSCF-PDUs_continue'{
			otid = <<OTID:32>>,
			dtid = <<DTID:32>>,
			components = Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_o_answer(OTID, DTID, InvokeID) ->
	SI = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg_eventSpecificInformationBCSM_oAnswerSpecificInfo'{
			destinationAddress = isup_called_party()},
	EventReportBCSMArg = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{
			eventTypeBCSM = oAnswer,
			eventSpecificInformationBCSM = {oAnswerSpecificInfo, SI},
			legID = {receivingSideID, ?leg2},
			miscCallInfo = #{messageType => notification}},
	Invoke = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID},
			opcode = ?'opcode-eventReportBCSM',
			argument = EventReportBCSMArg},
	Continue = #'GenericSSF-gsmSCF-PDUs_continue'{
			otid = <<OTID:32>>,
			dtid = <<DTID:32>>,
			components = [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_t_answer(OTID, DTID, InvokeID) ->
	SI = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg_eventSpecificInformationBCSM_tAnswerSpecificInfo'{
			destinationAddress = isup_called_party()},
	EventReportBCSMArg = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{
			eventTypeBCSM = tAnswer,
			eventSpecificInformationBCSM = {tAnswerSpecificInfo, SI},
			legID = {receivingSideID, ?leg2},
			miscCallInfo = #{messageType => notification}},
	Invoke = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID},
			opcode = ?'opcode-eventReportBCSM',
			argument = EventReportBCSMArg},
	Continue = #'GenericSSF-gsmSCF-PDUs_continue'{
			otid = <<OTID:32>>,
			dtid = <<DTID:32>>,
			components = [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_o_disconnect(OTID, DTID, InvokeID) ->
	Cause = #cause{coding = itu, location = local_public, value = 16},
	SI = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg_eventSpecificInformationBCSM_oDisconnectSpecificInfo'{
			releaseCause = cse_codec:cause(Cause)},
	EventReportArg = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{
			eventTypeBCSM = oDisconnect,
			eventSpecificInformationBCSM = {oDisconnectSpecificInfo, SI},
			legID = {receivingSideID, ?leg2},
			miscCallInfo = #{messageType => notification}},
	Invoke1 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID},
			opcode = ?'opcode-eventReportBCSM',
			argument = EventReportArg},
	ChargingResult = #'PduCallResult_timeDurationChargingResult'{
			partyToCharge = {receivingSideID, ?leg1},
			timeInformation = {timeIfNoTariffSwitch, rand:uniform(300)}},
	{ok, ChargingResultArg} = 'CAMEL-datatypes':encode('PduCallResult',
			{timeDurationChargingResult, ChargingResult}),
	Invoke2 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 1},
			opcode = ?'opcode-applyChargingReport',
			argument = ChargingResultArg},
	TV1 = rand:uniform(256) - 1,
	RI1 = #'RequestedInformation'{
			requestedInformationType = callAttemptElapsedTime,
			requestedInformationValue = {callAttemptElapsedTimeValue, TV1}},
	TV2 = cse_codec:date_time(calendar:universal_time()),
	RI2 = #'RequestedInformation'{
			requestedInformationType = callStopTime,
			requestedInformationValue = {callStopTimeValue, TV2}},
	TV3 = rand:uniform(3600),
	RI3 = #'RequestedInformation'{
			requestedInformationType = callConnectedElapsedTime,
			requestedInformationValue = {callConnectedElapsedTimeValue, TV3}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI4 = #'RequestedInformation'{
			requestedInformationType = releaseCause,
			requestedInformationValue = {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2, RI3, RI4],
	InfoReportArg = #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{
			legID = {receivingSideID, ?leg2},
			requestedInformationList = RequestedInformationList},
	Invoke3 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 2},
			opcode = ?'opcode-callInformationReport',
			argument = InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #'GenericSSF-gsmSCF-PDUs_continue'{
			otid = <<OTID:32>>,
			dtid = <<DTID:32>>,
			components = Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_t_disconnect(OTID, DTID, InvokeID) ->
	Cause = #cause{coding = itu, location = local_public, value = 16},
	SI = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg_eventSpecificInformationBCSM_tDisconnectSpecificInfo'{
			releaseCause = cse_codec:cause(Cause)},
	EventReportArg = #'GenericSSF-gsmSCF-PDUs_EventReportBCSMArg'{
			eventTypeBCSM = tDisconnect,
			eventSpecificInformationBCSM = {tDisconnectSpecificInfo, SI},
			legID = {receivingSideID, ?leg2},
			miscCallInfo = #{messageType => notification}},
	Invoke1 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID},
			opcode = ?'opcode-eventReportBCSM',
			argument = EventReportArg},
	ChargingResult = #'PduCallResult_timeDurationChargingResult'{
			partyToCharge = {receivingSideID, ?leg2},
			timeInformation = {timeIfNoTariffSwitch, rand:uniform(300)}},
	{ok, ChargingResultArg} = 'CAMEL-datatypes':encode('PduCallResult',
			{timeDurationChargingResult, ChargingResult}),
	Invoke2 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 1},
			opcode = ?'opcode-applyChargingReport',
			argument = ChargingResultArg},
	TV1 = cse_codec:date_time(calendar:universal_time()),
	RI1 = #'RequestedInformation'{
			requestedInformationType = callStopTime,
			requestedInformationValue = {callStopTimeValue, TV1}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI2 = #'RequestedInformation'{
			requestedInformationType = releaseCause,
			requestedInformationValue = {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2],
	InfoReportArg = #'GenericSSF-gsmSCF-PDUs_CallInformationReportArg'{
			legID = {receivingSideID, ?leg2},
			requestedInformationList = RequestedInformationList},
	Invoke3 = #'GenericSSF-gsmSCF-PDUs_begin_components_SEQOF_basicROS_invoke'{
			invokeId = {present, InvokeID + 2},
			opcode = ?'opcode-callInformationReport',
			argument = InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #'GenericSSF-gsmSCF-PDUs_continue'{
			otid = <<OTID:32>>,
			dtid = <<DTID:32>>,
			components = Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

