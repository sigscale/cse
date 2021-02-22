%%% cse_tco_server_cb.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
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
%%% @doc This {@link //tcap/tcap_tco_server. tcap_tco_server}
%%% 	behaviour callback module implements a binding to the TCAP
%%% 	Transaction Coordinator (TCO) in the {@link //cse. cse} application.
%%%
-module(cse_tco_server_cb).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(tcap_tco_server).

% export the gen_server call backs
-export([init/1, handle_call/3, handle_cast/2,
		handle_info/2, terminate/2, handle_continue/2,
		code_change/3, format_status/2]).
% export the tco_tco_server call backs
-export([send_primitive/2, start_aei/2]).

-include_lib("sccp/include/sccp.hrl").
-include_lib("tcap/include/sccp_primitive.hrl").
-include_lib("tcap/include/tcap.hrl").
-include_lib("tcap/include/DialoguePDUs.hrl").

-record(state,
		{sup :: pid(),
		slp_sup :: pid() | undefined}).
-type state() :: #state{}.

%%----------------------------------------------------------------------
%%  The gen_server callbacks
%%----------------------------------------------------------------------

-spec init(Args) -> Result
	when
		Args :: [term()],
		Result :: {ok, State :: state()}
				| {ok, State :: state(), Timeout :: timeout() | hibernate | {continue, term()}}
				| {stop, Reason :: term()} | ignore.
%% @see //stdlib/gen_server:init/1
%% @private
init([Sup] = _Args) ->
	process_flag(trap_exit, true),
	{ok, #state{sup = Sup}, {continue, init}}.

-spec send_primitive(Primitive, State) -> any()
	when
		Primitive :: {'N', 'UNITDATA', request, UdataParams},
		UdataParams :: #'N-UNITDATA'{},
		State :: state().
%% @doc The TCO will call this function when it has a service primitive to deliver to the SCCP layer.
%% @@see //tcap/tcap_tcap_server:send_primitive/2
%% @private
send_primitive(_Primitive, _State) ->
	ok.

-spec start_aei(DialoguePortion, State) -> Result
	when
	DialoguePortion :: binary(),
	State :: state(),
	Result :: {ok, DHA, CCO, TCU, State} | {error, Reason},
	DHA :: pid(),
	CCO :: pid(),
	TCU :: pid(),
	Reason :: unknown_context | term().
%% @doc This function is called by TCO to initialize an
%% 	Application Entity Instance (AEI).
%%
%% 	Called in response to a remote TC-User initiating a dialogue.
%% 	A transaction capabilities (TC) Application Service Element (ASE)
%% 	is represented by a newly created TC component sublayer (CSL) instance.
%%
%% 	DialoguePortion is the undecoded dialogue portion.
%%
%% 	DHA is the pid of the dialogue handler in the newly created CSL.
%%
%% 	CCO is the pid of the component coordinator in the newly created CSL.
%%
%% 	TCU is the pid of the TC-User which shall received indications from the CSL.
%%
%% @@see //tcap/tcap_tcap_server:start_aei/2
%% @private
start_aei(#'EXTERNAL'{encoding = {'single-ASN1-type',
		DialoguePDUs}} = _DialoguePortion, #state{slp_sup = SlpSup} = State) ->
	case 'DialoguePDUs':decode('DialoguePDU', DialoguePDUs) of
		{ok, {dialogueRequest, #'AARQ-apdu'{'application-context-name' = AC} = APDU}} ->
			case AC of
				% ?'id-ac-CAP-gsmSSF-scfGenericAC' ->
				{0,4,0,0,1,_,3,4} ->
					case supervisor:start_child(SlpSup, [APDU]) of
						{ok, TCU} ->
							tcap:open(self(), TCU);
						{error, Reason} ->
							{error, Reason}
					end;
				_ ->
					error_logger:warning_report(["Unknown Application Context Name",
							{'application-context-name', AC}]),
					{error, unknown_context}
			end;
		{error, Reason} ->
			{error, Reason}
	end.

-spec handle_call(Request, From, State) -> Result
	when
		Request :: term(),
		From :: {pid(), Tag :: any()},
		State :: state(),
		Result :: {reply, Reply :: term(), NewState :: state()}
				| {reply, Reply :: term(), NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {primitive, Primitive, State}
				| {stop, Reason :: term(), Reply :: term(), NewState :: state()}
				| {stop, Reason :: term(), NewState :: state()},
		Primitive :: {'N', 'UNITDATA', indication, UdataParams},
		UdataParams :: #'N-UNITDATA'{}.
%% @see //stdlib/gen_server:handle_call/3
%% @private
handle_call(Request, _From, State) ->
	{stop, Request, State}.

-spec handle_cast(Request, State) -> Result
	when
		Request :: term(),
		State :: state(),
		Result :: {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {primitive, Primitive, State}
				| {stop, Reason :: term(), NewState :: state()},
		Primitive :: {'N', 'UNITDATA', indication, UdataParams},
		UdataParams :: #'N-UNITDATA'{}.
%% @doc Handle a request sent using {@link //stdlib/gen_server:cast/2.
%% 	gen_server:cast/2} or {@link //stdlib/gen_server:abcast/2.
%% 	gen_server:abcast/2,3}.
%% @@see //stdlib/gen_server:handle_cast/2
%% @private
handle_cast(Request, State) ->
	{stop, Request, State}.

-spec handle_continue(Info, State) -> Result
	when
		Info :: term(),
		State :: state(),
		Result :: {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {stop, Reason :: term(), NewState :: state()}.
%% @doc Handle continued execution.
handle_continue(init, #state{sup = TopSup} = State) ->
	Children = supervisor:which_children(TopSup),
	{_, SlpSup, _, _} = lists:keyfind(cse_slp_sup, 1, Children),
	{noreply, State#state{slp_sup = SlpSup}}.

-spec handle_info(Info, State) -> Result
	when
		Info :: timeout | term(),
		State :: state(),
		Result :: {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {primitive, Primitive, State}
				| {stop, Reason :: term(), NewState :: state()},
		Primitive :: {'N', 'UNITDATA', indication, UdataParams},
		UdataParams :: #'N-UNITDATA'{}.
%% @doc Handle a received message.
%% @@see //stdlib/gen_server:handle_info/2
%% @private
handle_info(Info, State) ->
	{stop, Info, State}.

-spec terminate(Reason, State) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
      State :: state().
%% @see //stdlib/gen_server:terminate/3
%% @private
terminate(_Reason, _State) ->
	ok.

-spec code_change(OldVersion, State, Extra) -> Result
	when
		OldVersion :: term() | {down, term()},
		State :: state(),
		Extra :: term(),
		Result :: {ok, NewState :: state()} | {error, Reason :: term()}.
%% @see //stdlib/gen_server:code_change/3
%% @private
code_change(_OldVersion, State, _Extra) ->
	{ok, State}.

-spec format_status(Opt, StatusData) -> Status
	when
      Opt :: 'normal' | 'terminate',
      StatusData :: [PDict | State],
      PDict :: [{Key :: term(), Value :: term()}],
      State :: term(),
      Status :: term().
%% @see //stdlib/gen_server:format_status/3
%% @private
format_status(_Opt, [_PDict, State] = _StatusData) ->
	[{data, [{"State", State}]}].

%%----------------------------------------------------------------------
%% internal functions
%%----------------------------------------------------------------------

