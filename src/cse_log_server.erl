%%% cse_log_server.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_server. gen_server} behaviour callback
%%% 	module provides an event manager for a named log in the
%%% 	{@link //cse. cse} application.
%%%
-module(cse_log_server).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_server).

% export the gen_server call backs
-export([init/1, handle_call/3, handle_cast/2,
		handle_info/2, terminate/2, handle_continue/2,
		code_change/3, format_status/2]).
% export the cse_log_server private api
-export([codec_worker/5]).

-include_lib("kernel/include/logger.hrl").

-record(state,
		{sup :: pid(),
		job_sup :: pid() | undefined,
		log :: disk_log:log(),
		codec :: {Module :: atom(), Function :: atom()} | undefined,
		process = false :: boolean(),
		format = internal :: internal | external,
		dopts :: [tuple()] | undefined}).
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
init([Sup | Options]) ->
	{ok, LogDir} = application:get_env(log_dir),
	State = #state{sup = Sup},
	{State1, Options1} = case lists:keytake(codec, 1, Options) of
		{value, {codec, {M, F}}, O1} when is_atom(M), is_atom(F) ->
			{State#state{codec = {M, F}}, O1};
		false ->
			{State, Options}
	end,
	{State2, Options2} = case lists:keytake(process, 1, Options1) of
		{value, {process, Process}, O2} when is_boolean(Process) ->
			{State1#state{process = Process}, O2};
		false ->
			{State1, Options1}
	end,
	Options3 = case lists:keytake(filename, 1, Options2) of
		{value, {filename, Filename}, O3} when is_list(Filename) ->
			case filename:pathtype(Filename) of
				absolute ->
					Options2;
				relative ->
					[{filename, filename:join(LogDir, Filename)} | O3]
			end;
		false ->
			Options2
	end,
	State3 = case lists:keyfind(format, 1, Options3) of
		{format, Format} ->
			State2#state{format = Format};
		false ->
			State2
	end,
	case disk_log:open(Options3) of
		{ok, Log} ->
			process_flag(trap_exit, true),
			State4 = State3#state{log = Log, dopts = Options3},
			{ok, State4, {continue, init}};
		{repaired, Log, {recovered, Rec}, {badbytes, Bad}} ->
			?LOG_WARNING([{?MODULE, init}, {disk_log, Log},
					{recovered, Rec}, {badbytes, Bad}]),
			process_flag(trap_exit, true),
			State4 = State3#state{log = Log, dopts = Options3},
			{ok, State4, {continue, init}};
		{error, Reason} ->
			{stop, Reason}
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
				| {stop, Reason :: term(), Reply :: term(), NewState :: state()}
				| {stop, Reason :: term(), NewState :: state()}.
%% @see //stdlib/gen_server:handle_call/3
%% @private
handle_call({log, Item}, _From, #state{format = internal} = State) ->
	handle_call1(log, Item, State);
handle_call({blog, Item}, _From, #state{format = external} = State) ->
	handle_call1(blog, Item, State);
handle_call({alog, Item}, _From, #state{format = internal} = State) ->
	handle_call1(alog, Item, State);
handle_call({balog, Item}, _From, #state{format = external} = State) ->
	handle_call1(balog, Item, State);
handle_call(close, _From, State) ->
	{stop, shutdown, State}.
%% @hidden
handle_call1(Operation, Item,
		#state{process = false,
		log = Log, codec = {Module, Function}} = State) ->
	case catch Module:Function(Item) of
		{'EXIT', Reason} ->
			{reply, {error, Reason}, State};
		LogItem ->
			case disk_log:Operation(Log, LogItem) of
				ok ->
					{reply, ok, State};
				{error, Reason} ->
					{reply, {error, Reason}, State}
			end
	end;
handle_call1(Operation, Item,
		#state{process = true, job_sup = Sup,
		log = Log, codec = {Module, Function}} = State) ->
	case supervisor:start_child(Sup,
			[[Log, Operation, Module, Function, Item]]) of
		{ok, _Child} ->
			{reply, ok, State};
		{error, Reason} ->
			{reply, {error, Reason}, State}
	end.

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

-spec handle_continue(Continue, State) -> Result
	when
		Continue :: term(),
		State :: state(),
		Result :: {noreply, NewState :: state()}
				| {noreply, NewState :: state(), timeout() | hibernate | {continue, term()}}
				| {stop, Reason :: term(), NewState :: state()}.
%% @doc Handle continued execution.
handle_continue(init, #state{sup = Sup} = State) ->
	Children = supervisor:which_children(Sup),
	{_, JobSup, _, _} = lists:keyfind(cse_log_job_sup, 1, Children),
	{noreply, State#state{job_sup = JobSup}}.

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
%%  The cse_log_server private API
%%----------------------------------------------------------------------

-spec codec_worker(Log, Operation, Module, Function, Item) -> Result
	when
		Log :: disk_log:log(),
		Operation :: log | blog | alog | balog,
		Module :: atom(),
		Function :: atom(),
		Item :: term(),
		Result :: {stop, normal} | {error, Reason},
		Reason :: term().
%% @doc Child worker of the `cse_log_job_sup' supervisor.
%% @private
codec_worker(Log, Operation, Module, Function, Item) ->
	proc_lib:init_ack({ok, self()}),
	case disk_log:Operation(Log, Module:Function(Item)) of
		ok ->
			exit(normal);
		{error, Reason} ->
			exit(Reason)
	end.
		
%%----------------------------------------------------------------------
%% internal functions
%%----------------------------------------------------------------------

