%%% cse_slp_inap_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
%%% @author Vance Shipley <vances@sigscale.org> [http://www.sigscale.org]
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
%%% @reference <a href="https://www.etsi.org/deliver/etsi_i_ets/300300_300399/30037401/01_60/ets_30037401e01p.pdf">
%%% 	ETS 300 374-1</a> Core Intelligent Network Application Protocol (INAP);
%%% 	Capability Set 1 (CS1)
%%% @reference <a href="https://www.etsi.org/deliver/etsi_en/301100_301199/30114001/01.03.04_60/en_30114001v010304p.pdf">
%%%	ETSI EN 301 140-1</a> Intelligent Network Application Protocol (INAP);
%%% 	Capability Set 2 (CS2)
%%% @reference <a href="https://www.itu.int/rec/T-REC-Q.1224-199709-I">Q.1224</a>
%%% 	Distributed Functional Plane for Intelligent Network Capability Set 2
%%%
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements an initial  Service Logic Processing Program (SLP)
%% 	for ETSI Intelligent Network Application Part (INAP) within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	An `InitialDP' procedure contains a `serviceKey' parameter which
%%% 	indicates the IN service requested and is used to select which
%%% 	Service Logic Processing Program (SLP) should be used.
%%%
%%% 	A service table lookup provides the name of another
%%% 	{@link //stdlib/gen_statem. gen_statem} behaviour callback module
%%% 	implementing the target SLP and this process continues using the
%%% 	new callback.
%%%
-module(cse_slp_inap_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3]).

-include("cse.hrl").
-include_lib("tcap/include/DialoguePDUs.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("inap/include/CS2-operationcodes.hrl").
-include_lib("inap/include/CS2-errorcodes.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: null.
-type statedata() :: #{dha =>  pid() | undefined,
		cco => pid() | undefined,
		did => 0..4294967295 | undefined,
		ac => tuple() | undefined,
		tr_state => idle | init_sent | init_received | active,
		scf => sccp_codec:party_address() | undefined,
		ssf => sccp_codec:party_address() | undefined}.

-define(Pkgs, 'CS2-SSF-SCF-pkgs-contracts-acs').

%%----------------------------------------------------------------------
%%  The cse_slp_inap_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	[state_functions, state_enter].

-spec init(Args) -> Result
	when
		Args :: [term()],
		Result :: {ok, State, Data} | {ok, State, Data, Actions}
				| ignore | {stop, Reason},
		State :: state(),
		Data :: statedata(),
		Actions :: Action | [Action],
		Action :: gen_statem:action(),
		Reason :: term().
%% @doc Initialize the {@module} finite state machine.
%%
%% 	Initialize a Service Logic Processing Program (SLP) instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init([_APDU]) ->
	process_flag(trap_exit, true),
	{ok, null, #{}}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(enter, null = _EventContent, _Data) ->
	keep_state_and_data;
null(cast, {register_csl, DHA, CCO} = _EventContent, Data) ->
	link(DHA),
	NewData = Data#{dha => DHA, cco => CCO},
	{keep_state, NewData};
null(cast, {'TC', 'BEGIN', indication,
		#'TC-BEGIN'{appContextName = AC,
				dialogueID = DialogueID, qos = _QoS,
				destAddress = DestAddress, origAddress = OrigAddress,
				componentsPresent = true, userInfo = _UserInfo}} = _EventContent,
		Data) when not is_map_key(did, Data) ->
	NewData = Data#{did => DialogueID, ac => AC, tr_state => init_received,
			scf => DestAddress, ssf => OrigAddress},
	{keep_state, NewData};
null(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = ?'opcode-initialDP',
				dialogueID = DialogueID, invokeID = InvokeID,
				parameters = Argument} = Invoke},
		#{did := DialogueID, ac := AC, dha := DHA, cco := CCO,
				ssf := SSF, scf := SCF} = Data) ->
	case ?Pkgs:decode('GenericSSF-SCF-PDUs_InitialDPArg', Argument) of
		{ok, #{serviceKey := ServiceKey} = InitialDPArg} ->
			case cse:find_service(ServiceKey) of
				{ok, #in_service{key = ServiceKey, module = CbModule,
						data = ServiceData, opts = Opts}}
						when is_atom(CbModule), is_map(Data), is_list(Opts) ->
					apply_opts(Opts),
					NewData = maps:merge(ServiceData, Data),
					Actions = [{push_callback_module, CbModule},
							{next_event, internal, {Invoke, InitialDPArg}}],
					{repeat_state, NewData, Actions};
				{error, not_found} ->
					Error = #'TC-U-ERROR'{dialogueID = DialogueID,
							invokeID = InvokeID,
							error = ?'errcode-missingCustomerRecord'},
					gen_statem:cast(CCO, {'TC', 'U-ERROR', request, Error}),
					End = #'TC-END'{dialogueID = DialogueID,
							appContextName = AC, qos = {true, true},
							termination = basic},
					gen_statem:cast(DHA, {'TC', 'END', request, End}),
					?LOG_WARNING([{ac, AC}, {did, DialogueID},
							{ssf, sccp_codec:party_address(SSF)}, {scf,sccp_codec:party_address(SCF)},
							{serviceKey, ServiceKey}, {slp, not_found}]),
					keep_state_and_data
			end;
		{ok, #{}} ->
			Reject = #'TC-U-REJECT'{dialogueID = DialogueID,
					invokeID = InvokeID,
					problemCode =  {returnError, mistypedParameter}},
			gen_statem:cast(CCO, {'TC', 'U-REJECT', request, Reject}),
			End = #'TC-END'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					termination = basic},
			gen_statem:cast(DHA, {'TC', 'END', request, End}),
			keep_state_and_data;
		{error, _Reason} ->
			Reject = #'TC-U-REJECT'{dialogueID = DialogueID,
					invokeID = InvokeID,
					problemCode =  {returnError, mistypedParameter}},
			gen_statem:cast(CCO, {'TC', 'U-REJECT', request, Reject}),
			End = #'TC-END'{dialogueID = DialogueID,
					appContextName = AC, qos = {true, true},
					termination = basic},
			gen_statem:cast(DHA, {'TC', 'END', request, End}),
			keep_state_and_data
	end;
null(cast, {'TC', 'INVOKE', indication,
		#'TC-INVOKE'{operation = Other,
				dialogueID = DialogueID, invokeID = InvokeID} = _Invoke},
		#{did := DialogueID, as := AC, dha := DHA, cco := CCO,
				ssf := SSF, scf := SCF} = _Data) ->
	Reject = #'TC-U-REJECT'{dialogueID = DialogueID,
			invokeID = InvokeID,
			problemCode = {invoke, unrecognizedOperation}},
	gen_statem:cast(CCO, {'TC', 'U-REJECT', request, Reject}),
	End = #'TC-END'{dialogueID = DialogueID,
			appContextName = AC, qos = {true, true},
			termination = basic},
	gen_statem:cast(DHA, {'TC', 'END', request, End}),
	?LOG_WARNING([{ac, AC}, {did, DialogueID},
			{ssf, sccp_codec:party_address(SSF)}, {scf, sccp_codec:party_address(SCF)}, {operation, Other},
			{error, unrecognizedOperation}]),
	keep_state_and_data;
null(info, {'EXIT', DHA, Reason}, #{dha := DHA} = _Data) ->
	{stop, Reason}.

-spec handle_event(EventType, EventContent, State, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		State :: state(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(State).
%% @doc Handles events received in any state.
%% @private
%%
handle_event(_EventType, _EventContent, _State, _Data) ->
	keep_state_and_data.

-spec terminate(Reason, State, Data) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state(),
		Data ::  statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_statem:terminate/3
%% @private
%%
terminate(_Reason, _State, _Data) ->
	ok.

-spec code_change(OldVsn, OldState, OldData, Extra) -> Result
	when
		OldVsn :: Version | {down, Version},
		Version ::  term(),
		OldState :: state(),
		OldData :: statedata(),
		Extra :: term(),
		Result :: {ok, NewState, NewData} |  Reason,
		NewState :: state(),
		NewData :: statedata(),
		Reason :: term().
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_statem:code_change/3
%% @private
%%
code_change(_OldVsn, OldState, OldData, _Extra) ->
	{ok, OldState, OldData}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
apply_opts([{debug, Dbgs} | T]) ->
	apply_debug(Dbgs),
	apply_opts(T);
apply_opts([]) ->
	ok.

%% @hidden
apply_debug([trace | T]) ->
	spawn(sys, trace, [self(), true]),
	apply_debug(T);
apply_debug([log | T]) ->
	spawn(sys, log, [self(), true]),
	apply_debug(T);
apply_debug([{log, N} | T])
		when is_integer(N), N > 0 ->
	spawn(sys, log, [self(), {true, N}]),
	apply_debug(T);
apply_debug([{log_to_file, Filename} | T])
		when is_list(Filename) ->
	spawn(sys, log_to_file, [self(), Filename]),
	apply_debug(T);
apply_debug([statistics | T]) ->
	spawn(sys, statistics, [self(), true]),
	apply_debug(T);
apply_debug([{install, {Func, _FuncState} = FuncSpec} | T])
		when is_function(Func) ->
	spawn(sys, install, [self(), FuncSpec]),
	apply_debug(T);
apply_debug([{install, {_FuncId, Func, _FuncState} = FuncSpec} | T])
		when is_function(Func) ->
	spawn(sys, install, [self(), FuncSpec]),
	apply_debug(T);
apply_debug([]) ->
	ok.

