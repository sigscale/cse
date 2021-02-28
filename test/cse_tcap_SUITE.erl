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
-export([start_dialogue/0, start_dialogue/1]).

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
	Callback = #tcap_tco_cb{init = fun Cb:init/1,
		handle_call = fun Cb:handle_call/3,
		handle_cast =  fun Cb:handle_cast/2,
		handle_info = Finfo,
		terminate = fun Cb:terminate/2,
		handle_continue = fun Cb:handle_continue/2,
		send_primitive = Fsend,
		start_aei = fun Cb:start_aei/2,
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
	[start_dialogue].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

start_dialogue() ->
	[{userdata, [{doc, "Start a TCAP Dialougue"}]}].

start_dialogue(Config) ->
	TCO = ?config(tco, Config),
	TCO ! {?MODULE, self()},
	AC = ?'id-ac-CAP-gsmSSF-scfGenericAC',
	SsfParty = #party_address{ssn = ?SSN_CAMEL,
			nai = international,
			translation_type = undefined,
			numbering_plan = isdn_tele,
			encoding_scheme = bcd_odd,
			gt = [1,4,1,6,5,5,5,1,2,3,4]},
	ScfParty = #party_address{ssn = ?SSN_CAMEL,
			nai = international,
			translation_type = undefined,
			numbering_plan = isdn_tele,
			encoding_scheme = bcd_odd,
			gt = [1,4,1,6,5,5,5,5,6,7,8]},
	SsfTid = tid(),
	UserData1 = pdu_initial_dp(SsfTid, AC),
	SccpParams1 = #'N-UNITDATA'{userData = UserData1,
			sequenceControl = true,
			returnOption = true,
			calledAddress = ScfParty,
			callingAddress = SsfParty},
	gen_server:cast(TCO, {'N', 'UNITDATA', indication, SccpParams1}),
	SccpParams2 = receive
		{'N', 'UNITDATA', request, #'N-UNITDATA'{} = UD1} ->
			UD1
	end,
	#'N-UNITDATA'{userData = UserData2,
			sequenceControl = true,
			returnOption = true,
			calledAddress = SsfParty,
			callingAddress = ScfParty} = SccpParams2,
	Pkgs = 'CAP-gsmSSF-gsmSCF-pkgs-contracts-acs',
	{ok, {continue,  Continue}} = Pkgs:decode('GenericSSF-gsmSCF-PDUs',
		UserData2),
	#'GenericSSF-gsmSCF-PDUs_continue'{otid = <<_ScfTid:32>>,
			dtid = <<_SsfTid:32>>,
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

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

tid() ->
	rand:uniform(4294967295).

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
	{ok, UD} = 'CAP-gsmSSF-gsmSCF-pkgs-contracts-acs':encode('GenericSSF-gsmSCF-PDUs',
			{'begin', Begin}),
	UD.

