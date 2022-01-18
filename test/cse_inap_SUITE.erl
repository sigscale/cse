%%% cse_inap_SUITE.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
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
%%% Intelligent Network Application Part (INAP) integration
%%% of the {@link //cse. cse} application.
%%%
-module(cse_inap_SUITE).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
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
-include_lib("inap/include/CS2-operationcodes.hrl").
-include_lib("inap/include/CS2-object-identifiers.hrl").
-include("cse_codec.hrl").
-include_lib("common_test/include/ct.hrl").

-define('leg1', <<1>>).
-define('leg2', <<2>>).

-define(SSN_INAP, 241).
-define(Pkgs, 'CS2-SSF-SCF-pkgs-contracts-acs').
-define(PDUs, 'GenericSSF-SCF-PDUs').

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
	PrivDir = ?config(priv_dir, Config),
	application:load(mnesia),
	ok = application:set_env(mnesia, dir, PrivDir),
	{ok, [m3ua_asp, m3ua_as]} = m3ua_app:install(),
	{ok, [gtt_ep,gtt_as,gtt_pc]} = gtt_app:install(),
	ok = application:start(inets),
	HttpdPort = case inets:start(httpd,
			[{port, 0},
			{server_name, atom_to_list(?MODULE)},
			{server_root, "./"},
			{document_root, ?config(data_dir, Config)},
			{modules, [mod_ct_nrf]}]) of
		{ok, HttpdPid} ->
			[{port, Port}] = httpd:info(HttpdPid, [port]),
			Port;
		{error, InetsReason} ->
			ct:fail(InetsReason)
	end,
	ok = application:start(snmp),
	ok = application:start(sigscale_mibs),
	ok = application:start(m3ua),
	ok = application:start(tcap),
	ok = application:start(gtt),
	catch application:unload(cse),
	ok = application:load(cse),
	{ok, Cb} = application:get_env(cse, tsl_callback),
	Callback = callback(Cb),
	ok = application:set_env(cse, tsl_callback, Callback),
	{ok, TslArgs} = application:get_env(cse, tsl_args),
	ok = application:set_env(cse, tsl_args, [{?MODULE, undefined} | TslArgs]),
	ok = application:set_env(cse, nrf_uri,
			"http://localhost:" ++ integer_to_list(HttpdPort)),
	ok = application:start(cse),
	{ok, TCO} = application:get_env(cse, tsl_name),
	[{tco, TCO}, {orig_cb, Cb} | Config].

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(_Config) ->
	ok = application:stop(cse),
	ok = application:stop(gtt),
	ok = application:stop(tcap),
	ok = application:stop(m3ua),
	ok = application:stop(sigscale_mibs),
	ok = application:stop(snmp),
	ok = application:stop(inets).

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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
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
	#{otid := <<_ScfTid:32>>,
			dtid := <<SsfTid:32>>,
			dialoguePortion := DialoguePortion,
			components := _Components} = Continue,
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
	#{otid := <<ScfTid:32>>} = Continue1,
	MonitorRef = receive
		{csl, DHA, _TCU} ->
			monitor(process, DHA)
	end,
	End = #{dtid => <<ScfTid:32>>},
	{ok, UserData3} = ?Pkgs:encode(?PDUs, {'end',  End}),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	receive
		{'DOWN', MonitorRef, _, _, normal} -> ok
	end.

initial_dp_mo() ->
	[{userdata, [{doc, "MO InitialDP received by SLPI"}]}].

initial_dp_mo(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mt(SsfTid, AC),
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#{components := Components} = Continue,
	{basicROS, {invoke, Invoke}} = lists:last(Components),
	?'opcode-continue' = maps:get(opcode, Invoke).

dp_arming() ->
	[{userdata, [{doc, "RequestReportBCSMEvent received by SSF"}]}].

dp_arming(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#{components := Components} = Continue,
	F1 = fun({basicROS, {invoke, #{opcode := OpCode}}})
					when OpCode == ?'opcode-requestReportBCSMEvent' ->
				true;
			(_) -> false
	end,
	[{basicROS, {invoke, #{bcsmEvents := BCSMEvents}}}]
			= lists:filter(F1, Components),
	F2 = fun(#{eventTypeBCSM := _EventTyep, monitorMode := _Mode}) ->
				true;
			(_) ->
				false
	end,
	true = lists:all(F2, BCSMEvents).

apply_charging() ->
	[{userdata, [{doc, "ApplyCharging received by SSF"}]}].

apply_charging(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#{components := Components} = Continue,
	F1 = fun({basicROS, {invoke, #{opcodse := OpCode}}})
					when OpCode == ?'opcode-applyCharging' ->
				true;
			(_) -> false
	end,
	[{basicROS, {invoke, #{argument := A}}}] = lists:filter(F1, Components),
	{sendingSideID, ?leg1} = maps:get(partyToCharge, A).

call_info_request() ->
	[{userdata, [{doc, "CallInformationRequest received by SSF"}]}].

call_info_request(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, UD} -> UD
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {'continue',  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
	#{components := Components} = Continue,
	F1 = fun({basicROS, {invoke, #{opcode := OpCode}}})
					when OpCode == ?'opcode-callInformationRequest' ->
				true;
			(_) -> false
	end,
	[{basicROS, {invoke, #{argument := A}}}] = lists:filter(F1, Components),
	L = maps:get(requestedInformationTypeList, A),
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
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
	#{otid := <<ScfTid:32>>} = Continue1,
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mt(SsfTid, AC),
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
	#{otid := <<ScfTid:32>>} = Continue1,
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
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
	#{otid := <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_o_answer(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	ct:sleep(500),
	o_active = get_state(TcUser).

mt_answer() ->
	[{userdata, [{doc, "EventReportBCSM:tAnswer received by SCF"}]}].

mt_answer(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mt(SsfTid, AC),
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
	#{otid := <<ScfTid:32>>} = Continue1,
	UserData3 = pdu_t_answer(SsfTid, ScfTid, 2),
	SccpParams3 = unitdata(UserData3, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams3}),
	ct:sleep(500),
	t_active = get_state(TcUser).

mo_disconnect() ->
	[{userdata, [{doc, "EventReportBCSM:oDisconnect received by SCF"}]}].

mo_disconnect(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mo(SsfTid, AC),
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
	#{otid := <<ScfTid:32>>} = Continue1,
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-as-ssf-scfGenericAS',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_mt(SsfTid, AC),
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
	#{otid := <<ScfTid:32>>} = Continue1,
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
	#party_address{ssn = ?SSN_INAP,
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

unitdata(UserData, CalledParty, CallingParty) ->
	#'N-UNITDATA'{userData = UserData,
			sequenceControl = true,
			returnOption = true,
			calledAddress = CalledParty,
			callingAddress = CallingParty}.

pdu_initial_mo(OTID, AC) ->
	AARQ = #'AARQ-apdu'{'application-context-name' = AC},
	{ok, DialoguePDUs} = 'DialoguePDUs':encode('DialoguePDU',
			{dialogueRequest, AARQ}),
	DialoguePortion = #'EXTERNAL'{'direct-reference' = {0,0,17,773,1,1,1},
			'indirect-reference' = asn1_NOVALUE,
			'data-value-descriptor' = asn1_NOVALUE,
			encoding = {'single-ASN1-type', DialoguePDUs}},
	InitialDPArg = #{serviceKey => 100,
			callingPartyNumber => isup_calling_party(),
			callingPartysCategory => <<10>>,
			locationNumber => isup_calling_party(),
			bearerCapability => {bearerCap,<<128,144,163>>},
			eventTypeBCSM => collectedInfo,
			callReferenceNumber => crypto:strong_rand_bytes(4),
			calledPartyNumber => isup_called_party()},
	Invoke = #{invokeId => {present, 1},
			opcode => ?'opcode-initialDP',
			argument => InitialDPArg},
	Begin = #{otid => <<OTID:32>>,
			dialoguePortion => DialoguePortion,
			components => [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'begin', Begin}),
	UD.

pdu_initial_mt(OTID, AC) ->
	AARQ = #'AARQ-apdu'{'application-context-name' = AC},
	{ok, DialoguePDUs} = 'DialoguePDUs':encode('DialoguePDU',
			{dialogueRequest, AARQ}),
	DialoguePortion = #'EXTERNAL'{'direct-reference' = {0,0,17,773,1,1,1},
			'indirect-reference' = asn1_NOVALUE,
			'data-value-descriptor' = asn1_NOVALUE,
			encoding = {'single-ASN1-type', DialoguePDUs}},
	InitialDPArg = #{serviceKey => 100,
			calledPartyNumber => isup_called_party(),
			callingPartyNumber => isup_calling_party(),
			callingPartysCategory => <<10>>,
			locationNumber => isup_calling_party(),
			bearerCapability => {bearerCap,<<128,144,163>>},
			eventTypeBCSM => termAttemptAuthorized,
			callReferenceNumber => crypto:strong_rand_bytes(4)},
	Invoke = #{invokeId => {present, 1},
			opcode => ?'opcode-initialDP',
			argument => InitialDPArg},
	Begin = #{otid => <<OTID:32>>,
			dialoguePortion => DialoguePortion,
			components => [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'begin', Begin}),
	UD.

pdu_o_abandon(OTID, DTID, InvokeID) ->
	EventReportArg = #{eventTypeBCSM => oAbandon,
			legID => {receivingSideID, ?leg1},
			miscCallInfo => #{messageType => notification}},
	Invoke1 = #{invokeId => {present, InvokeID},
			opcode => ?'opcode-eventReportBCSM',
			argument => EventReportArg},
	ChargingResultArg = crypto:strong_rand_bytes(4),
	Invoke2 = #{invokeId => {present, InvokeID + 1},
			opcode => ?'opcode-applyChargingReport',
			argument => ChargingResultArg},
	RI1 = #{requestedInformationType => callAttemptElapsedTime,
			requestedInformationValue => {callAttemptElapsedTimeValue, 0}},
	TV2 = cse_codec:date_time(calendar:universal_time()),
	RI2 = #{requestedInformationType => callStopTime,
			requestedInformationValue => {callStopTimeValue, TV2}},
	RI3 = #{requestedInformationType => callConnectedElapsedTime,
			requestedInformationValue => {callConnectedElapsedTimeValue, 0}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI4 = #{requestedInformationType => releaseCause,
			requestedInformationValue => {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2, RI3, RI4],
	InfoReportArg = #{legID => {receivingSideID, ?leg2},
			requestedInformationList => RequestedInformationList},
	Invoke3 = #{invokeId => {present, InvokeID + 2},
			opcode => ?'opcode-callInformationReport',
			argument => InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #{otid => <<OTID:32>>,
			dtid => <<DTID:32>>,
			components => Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_t_abandon(OTID, DTID, InvokeID) ->
	EventReportArg = #{eventTypeBCSM => tAbandon,
			legID => {receivingSideID, ?leg2},
			miscCallInfo => #{messageType => notification}},
	Invoke1 = #{invokeId => {present, InvokeID},
			opcode => ?'opcode-eventReportBCSM',
			argument => EventReportArg},
	ChargingResultArg = crypto:strong_rand_bytes(4),
	Invoke2 = #{invokeId => {present, InvokeID + 1},
			opcode => ?'opcode-applyChargingReport',
			argument => ChargingResultArg},
	TV1 = cse_codec:date_time(calendar:universal_time()),
	RI1 = #{requestedInformationType => callStopTime,
			requestedInformationValue => {callStopTimeValue, TV1}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI2 = #{requestedInformationType => releaseCause,
			requestedInformationValue => {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2],
	InfoReportArg = #{legID => {receivingSideID, ?leg2},
			requestedInformationList => RequestedInformationList},
	Invoke3 = #{invokeId => {present, InvokeID + 2},
			opcode => ?'opcode-callInformationReport',
			argument => InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #{otid => <<OTID:32>>,
			dtid => <<DTID:32>>,
			components => Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_o_answer(OTID, DTID, InvokeID) ->
	EventReportBCSMArg = #{eventTypeBCSM => oAnswer,
			legID => {receivingSideID, ?leg2},
			miscCallInfo => #{messageType => notification}},
	Invoke = #{invokeId => {present, InvokeID},
			opcode => ?'opcode-eventReportBCSM',
			argument => EventReportBCSMArg},
	Continue = #{otid => <<OTID:32>>,
			dtid => <<DTID:32>>,
			components => [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_t_answer(OTID, DTID, InvokeID) ->
	EventReportBCSMArg = #{eventTypeBCSM => tAnswer,
			legID => {receivingSideID, ?leg2},
			miscCallInfo => #{messageType => notification}},
	Invoke = #{invokeId => {present, InvokeID},
			opcode => ?'opcode-eventReportBCSM',
			argument => EventReportBCSMArg},
	Continue = #{otid => <<OTID:32>>,
			dtid => <<DTID:32>>,
			components => [{basicROS, {invoke, Invoke}}]},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_o_disconnect(OTID, DTID, InvokeID) ->
	Cause = #cause{coding = itu, location = local_public, value = 16},
	SI = #{releaseCause => cse_codec:cause(Cause)},
	EventReportArg = #{eventTypeBCSM => oDisconnect,
			eventSpecificInformationBCSM => {oDisconnectSpecificInfo, SI},
			legID => {receivingSideID, ?leg2},
			miscCallInfo => #{messageType => notification}},
	Invoke1 = #{invokeId => {present, InvokeID},
			opcode => ?'opcode-eventReportBCSM',
			argument => EventReportArg},
	ChargingResultArg = crypto:strong_rand_bytes(4),
	Invoke2 = #{invokeId => {present, InvokeID + 1},
			opcode => ?'opcode-applyChargingReport',
			argument => ChargingResultArg},
	TV1 = rand:uniform(256) - 1,
	RI1 = #{requestedInformationType => callAttemptElapsedTime,
			requestedInformationValue => {callAttemptElapsedTimeValue, TV1}},
	TV2 = cse_codec:date_time(calendar:universal_time()),
	RI2 = #{requestedInformationType => callStopTime,
			requestedInformationValue => {callStopTimeValue, TV2}},
	TV3 = rand:uniform(3600),
	RI3 = #{requestedInformationType => callConnectedElapsedTime,
			requestedInformationValue => {callConnectedElapsedTimeValue, TV3}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI4 = #{requestedInformationType => releaseCause,
			requestedInformationValue => {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2, RI3, RI4],
	InfoReportArg = #{legID => {receivingSideID, ?leg2},
			requestedInformationList => RequestedInformationList},
	Invoke3 = #{invokeId => {present, InvokeID + 2},
			opcode => ?'opcode-callInformationReport',
			argument => InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #{otid => <<OTID:32>>,
			dtid => <<DTID:32>>,
			components => Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.

pdu_t_disconnect(OTID, DTID, InvokeID) ->
	Cause = #cause{coding = itu, location = local_public, value = 16},
	SI = #{releaseCause => cse_codec:cause(Cause)},
	EventReportArg = #{eventTypeBCSM => tDisconnect,
			eventSpecificInformationBCSM => {tDisconnectSpecificInfo, SI},
			legID => {receivingSideID, ?leg2},
			miscCallInfo => #{messageType => notification}},
	Invoke1 = #{invokeId => {present, InvokeID},
			opcode => ?'opcode-eventReportBCSM',
			argument => EventReportArg},
	ChargingResultArg = crypto:strong_rand_bytes(4),
	Invoke2 = #{invokeId => {present, InvokeID + 1},
			opcode => ?'opcode-applyChargingReport',
			argument => ChargingResultArg},
	TV1 = cse_codec:date_time(calendar:universal_time()),
	RI1 = #{requestedInformationType => callStopTime,
			requestedInformationValue => {callStopTimeValue, TV1}},
	Cause = #cause{coding = itu, location = local_public, value = 16},
	RI2 = #{requestedInformationType => releaseCause,
			requestedInformationValue => {releaseCauseValue, cse_codec:cause(Cause)}},
	RequestedInformationList = [RI1, RI2],
	InfoReportArg = #{legID => {receivingSideID, ?leg2},
			requestedInformationList => RequestedInformationList},
	Invoke3 = #{invokeId => {present, InvokeID + 2},
			opcode => ?'opcode-callInformationReport',
			argument => InfoReportArg},
	Components = [{basicROS, {invoke, I}} || I <- [Invoke1, Invoke2, Invoke3]],
	Continue = #{otid => <<OTID:32>>,
			dtid => <<DTID:32>>,
			components => Components},
	{ok, UD} = ?Pkgs:encode(?PDUs, {'continue', Continue}),
	UD.
