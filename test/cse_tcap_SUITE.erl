%%% cse_tcap_SUITE.erl
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
%%% Test suite for the Transaction Capabilities stack integration
%%% of the {@link //cse. cse} application.
%%%
-module(cse_tcap_SUITE).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% export test cases
-export([start_dialogue/0, start_dialogue/1,
		end_dialogue/0, end_dialogue/1,
		collected_info/0, collected_info/1]).

-include_lib("sccp/include/sccp.hrl").
-include_lib("tcap/include/sccp_primitive.hrl").
-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("cap/include/CAP-operationcodes.hrl").
-include_lib("cap/include/CAP-object-identifiers.hrl").
-include_lib("cap/include/CAP-gsmSSF-gsmSCF-pkgs-contracts-acs.hrl").
-include_lib("map/include/MAP-MS-DataTypes.hrl").
-include_lib("common_test/include/ct.hrl").

-define(SSN_CAMEL, 146).

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
	PrivDir = ?config(priv_dir, Config),
	application:load(mnesia),
	ok = application:set_env(mnesia, dir, PrivDir),
	{ok, [m3ua_asp, m3ua_as]} = m3ua_app:install(),
	{ok, [gtt_ep,gtt_as,gtt_pc]} = gtt_app:install(),
	ok = application:start(inets),
	ok = application:start(snmp),
	ok = application:start(sigscale_mibs),
	ok = application:start(m3ua),
	ok = application:start(tcap),
	ok = application:start(gtt),
	ok = application:unload(cse),
	ok = application:load(cse),
	{ok, Cb} = application:get_env(cse, tsl_callback),
	Finfo = fun({?MODULE, TestCasePid}, State) ->
				F = fun F(P, S, N) ->
						case element(N, S) of
							[{?MODULE, _}] ->
								setelement(N, S, [{?MODULE, P}]);
							_ ->
								F(P, S, N + 1)
						end
				end,
				{noreply, F(TestCasePid, State, 2)};
			(Info, State) ->
				Cb:handle_info(Info, State)
	end,
	Fsend = fun(Primitive, State) ->
				F = fun F(S, N) ->
						case element(N, S) of
							[{?MODULE, Pid}] ->
								Pid;
							_ ->
								F(S, N + 1)
						end
				end,
				F(State, 2) ! Primitive,
				{noreply, State}
	end,
	Fstart = fun(DialoguePortion, State) ->
				case Cb:start_aei(DialoguePortion, State) of
					{ok, DHA, CCO, TCU, State} ->
						F = fun F(S, N) ->
								case element(N, S) of
									[{?MODULE, Pid}] ->
										Pid;
									_ ->
										F(S, N + 1)
								end
						end,
						F(State, 2) ! {csl, DHA, TCU},
						{ok, DHA, CCO, TCU, State};
					{error, Reason} ->
						{error, Reason}
				end
	end,
	Callback = #tcap_tco_cb{init = fun Cb:init/1,
		handle_call = fun Cb:handle_call/3,
		handle_cast =  fun Cb:handle_cast/2,
		handle_info = Finfo,
		terminate = fun Cb:terminate/2,
		handle_continue = fun Cb:handle_continue/2,
		send_primitive = Fsend,
		start_aei = Fstart,
		code_change = fun Cb:code_change/3,
		format_status = fun Cb:format_status/2},
	ok = application:set_env(cse, tsl_callback, Callback),
	ok = application:set_env(cse, tsl_args, [{?MODULE, undefined}]),
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
	[start_dialogue, end_dialogue, collected_info].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

start_dialogue() ->
	[{userdata, [{doc, "Start a TCAP Dialogue"}]}].

start_dialogue(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_dp(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, #'N-UNITDATA'{} = UD1} -> UD1
	end,
	#'N-UNITDATA'{userData = UserData2,
			sequenceControl = true,
			returnOption = true,
			calledAddress = SsfParty,
			callingAddress = ScfParty} = SccpParams2,
	{ok, {continue,  Continue}} = ?Pkgs:decode(?PDUs, UserData2),
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
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_dp(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, #'N-UNITDATA'{} = UD1} -> UD1
	end,
	#'N-UNITDATA'{userData = UserData2} = SccpParams2,
	{ok, {continue,  Continue1}} = ?Pkgs:decode(?PDUs, UserData2),
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

collected_info() ->
	[{userdata, [{doc, "InitialDP received by SLPI"}]}].

collected_info(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = party(),
	ScfParty = party(),
	SsfTid = tid(),
	UserData1 = pdu_initial_dp(SsfTid, AC),
	SccpParams1 = unitdata(UserData1, ScfParty, SsfParty),
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	TcUser = receive
		{csl, _DHA, TCU} -> TCU
	end,
	receive
		{'N', 'UNITDATA', request, #'N-UNITDATA'{}} -> ok
	end,
	analyse_information = get_state(TcUser).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

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
	#party_address{ssn = ?SSN_CAMEL,
			nai = international,
			translation_type = undefined,
			numbering_plan = isdn_tele,
			encoding_scheme = bcd_odd,
			gt = Acc}.

unitdata(UserData, CalledParty, CallingParty) ->
	#'N-UNITDATA'{userData = UserData,
			sequenceControl = true,
			returnOption = true,
			calledAddress = CalledParty,
			callingAddress = CallingParty}.

pdu_initial_dp(OTID, AC) ->
	AARQ = #'AARQ-apdu'{'application-context-name' = AC},
	{ok, DialoguePDUs} = 'DialoguePDUs':encode('DialoguePDU',
			{dialogueRequest, AARQ}),
	DialoguePortion = #'EXTERNAL'{'direct-reference' = {0,0,17,773,1,1,1},
			'indirect-reference' = asn1_NOVALUE,
			'data-value-descriptor' = asn1_NOVALUE,
			encoding = {'single-ASN1-type', DialoguePDUs}},
	LocationInformation = #'LocationInformation'{
			ageOfLocationInformation = 0,
			'vlr-number' = <<193,65,97,85,5,0,240>>,
			cellGlobalIdOrServiceAreaIdOrLAI =
			{cellGlobalIdOrServiceAreaIdFixedLength, <<0,1,16,0,1,0,1>>}},
	InitialDPArg = #'GenericSSF-gsmSCF-PDUs_InitialDPArg'{
			serviceKey = 91,
			callingPartyNumber = <<129,16,65,97,85,21,50,4>>,
			callingPartysCategory = <<10>>,
			locationNumber = <<129,19,65,97,85,21,50,4>>,
			bearerCapability = {bearerCap,<<128,144,163>>},
			eventTypeBCSM = collectedInfo,
			iMSI = <<0,1,16,16,50,84,118,152>>,
			locationInformation = LocationInformation,
			'ext-basicServiceCode' = {'ext-Teleservice', <<17>>},
			callReferenceNumber = <<9,4,193,244>>,
			mscAddress = <<193,65,97,85,5,0,240>>,
			calledPartyBCDNumber = <<161,65,97,85,85,118,248>>,
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

