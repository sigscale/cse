%%% cse_server.erl
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
%%% @doc Service access point for the public API of
%%% 	the {@link //cse. cse} application.
%%%
-module(cse_server).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_server).

% export the gen_server call backs
-export([init/1, handle_call/3, handle_cast/2,
		handle_info/2, terminate/2, handle_continue/2,
		code_change/3, format_status/2]).

% export the private api
-export([]).

-record(state, {sup :: pid()}).
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
init([Sup]) ->
	process_flag(trap_exit, true),
	{ok, #state{sup = Sup}}.

-spec handle_call(Request, From, State) -> Result
	when
		Request :: term(),
		From :: {pid(), Tag :: any()},
		State :: state(),
		Result :: {reply, Reply :: term(), NewState :: state()}
				| {reply, Reply :: term(), NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {stop, Reason :: term(), Reply :: term(), NewState :: state()}
				| {stop, Reason :: term(), NewState :: state()}.
%% @see //stdlib/gen_server:handle_call/3
%% @private
handle_call({start, diameter, Address, Port, Options}, _From,
		#state{sup = Sup} = State) ->
	Children = supervisor:which_children(Sup),
	{_, DiameterSup, _, _} = lists:keyfind(cse_diameter_sup, 1, Children),
   Result = supervisor:start_child(DiameterSup, [[Address, Port, Options]]),
   {reply, Result, State};
handle_call({start, radius, Address, Port, Module, Args, Options}, _From,
		#state{sup = Sup} = State) ->
	Children = supervisor:which_children(Sup),
	{_, RadiusSup, _, _} = lists:keyfind(cse_radius_sup, 1, Children),
   Result = supervisor:start_child(RadiusSup, [[Address, Port, Module, Args, Options]]),
   {reply, Result, State};
handle_call({stop, diameter, Child}, _From, #state{sup = Sup} = State) ->
	Children = supervisor:which_children(Sup),
	{_, DiameterSup, _, _} = lists:keyfind(cse_diameter_sup, 1, Children),
   Result = supervisor:terminate_child(DiameterSup, Child),
   {reply, Result, State};
handle_call({stop, radius, Child}, _From, #state{sup = Sup} = State) ->
	Children = supervisor:which_children(Sup),
	{_, RadiusSup, _, _} = lists:keyfind(cse_radius_sup, 1, Children),
   Result = supervisor:terminate_child(RadiusSup, Child),
   {reply, Result, State};
handle_call(Request, _From, State) ->
	{stop, Request, State}.

-spec handle_cast(Request, State) -> Result
	when
		Request :: term(),
		State :: state(),
		Result :: {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {stop, Reason :: term(), NewState :: state()}.
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
handle_continue(Info, State) ->
	{stop, Info, State}.

-spec handle_info(Info, State) -> Result
	when
		Info :: timeout | term(),
		State :: state(),
		Result :: {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {stop, Reason :: term(), NewState :: state()}.
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

