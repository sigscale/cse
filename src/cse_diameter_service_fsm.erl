%%% cse_diameter_service_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module handles {@link //diameter. diameter} service events.
%%%
-module(cse_diameter_service_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([wait_for_start/3, started/3]).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("kernel/include/inet.hrl").
-include_lib("kernel/include/logger.hrl").

-type state() :: wait_for_start | started.
-type statedata() :: #{transport_ref :=  undefined | reference(),
		address := inet:ip_address(),
		port := inet:port_number(),
		options := list(),
		backoff := pos_integer(),
		alarms := list()}.
-export_type([statedata/0]).

-define(DIAMETER_SERVICE(A, P), {cse, A, P}).
-define(BASE_APPLICATION, cse_diameter_base_application).
-define(BASE_APPLICATION_DICT, diameter_gen_base_rfc6733).
-define(BASE_APPLICATION_CALLBACK, cse_diameter_base_application_cb).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

%%----------------------------------------------------------------------
%%  The cse_diameter_service_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	[state_functions].

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
%% 	Initialize a Diameter Service instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init([Address, Port, Options] = _Args) ->
	{TOptions1, SOptions1} = split_options(Options),
	TOptions2 = transport_options(Address, Port, TOptions1),
	SOptions2 = service_options(SOptions1),
	SvcName = ?DIAMETER_SERVICE(Address, Port),
	diameter:subscribe(SvcName),
	case diameter:start_service(SvcName, SOptions2) of
		ok ->
			Data = #{address => Address, port => Port,
					options => Options, service => SvcName},
			init1(TOptions2, SOptions2, Data);
		{error, Reason} ->
			{stop, Reason}
	end.
%% @hidden
init1(TOptions, [{application, AOptions} | T] = _SOptions, Data) ->
	Module = case lists:keyfind(module, 1, AOptions) of
		{_, Mod} when is_atom(Mod) ->
			Mod;
		{_, [Mod | _]} when is_atom(Mod) ->
			Mod
	end,
	ok = code:ensure_modules_loaded([Module]),
	case erlang:function_exported(Module, init, 1) of
		true ->
			case Module:init(Data) of
				ok ->
					init1(TOptions, T, Data);
				{error, Reason} ->
					{stop, Reason}
			end;
		false ->
			init1(TOptions, T, Data)
	end;
init1(TOptions, [_App | T] = _SOptions, Data) ->
	init1(TOptions, T, Data);
init1(TOptions, [] = _SOptions, Data) ->
	init2(TOptions, Data).
%% @hidden
init2(TOptions, #{service := SvcName} = Data) ->
	process_flag(trap_exit, true),
	case diameter:add_transport(SvcName, TOptions) of
		{ok, Ref} ->
			{ok, Alarms} = application:get_env(cse, snmp_alarms),
			Data1 = Data#{transport_ref => Ref, alarms => Alarms},
			{ok, wait_for_start, Data1};
		{error, Reason} ->
			{stop, Reason}
	end.

-spec wait_for_start(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_for_start</em> state.
%% @private
wait_for_start(info = _EventType,
		#diameter_event{service = Service, info = start} = _EventContent,
		#{service := Service} = Data) ->
	{next_state, started, Data};
wait_for_start(info,
		#diameter_event{service = Service, info = stop},
		#{service := Service} = Data) ->
	{stop, stop, Data};
wait_for_start(info, {'EXIT', _Pid, Reason}, Data) ->
	{stop, Reason, Data}.

-spec started(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>started</em> state.
%% @private
started(info = _EventType,
		#diameter_event{service = Service, info = Info},
		#{alarms := Alarms, service := Service} = _Data)
		when element(1, Info) == up; element(1, Info) == down ->
	{_, #diameter_caps{origin_host = {_, OH}}} = element(3, Info),
	OriginHost = binary_to_list(OH),
	State = element(1, Info),
	F = fun(R, #{single_line := false}) ->
				Format = "    ~s~n    service: ~w~n"
						"    peer: ~s~n    state: ~w~n",
				Args = [maps:get(title, R), maps:get(service, R),
						maps:get(peer, R), maps:get(state, R)],
				io_lib:fwrite(Format, Args);
			(R, #{single_line := true}) ->
				Format = "~s: service:~w, peer:~s, state:~w",
				Args = [maps:get(title, R), maps:get(service, R),
						maps:get(peer, R), maps:get(state, R)],
				io_lib:fwrite(Format, Args)
	end,
	Report = #{module => ?MODULE,
			title => "DIAMETER peer connection state changed",
			service => Service, peer => OriginHost,
			state => State},
	Metadata = #{report_cb => F},
	?LOG_WARNING(Report, Metadata),
	send_notification(State, OriginHost, Alarms),
	keep_state_and_data;
started(info, #diameter_event{service = Service,
				info = {reconnect, _Ref, _Opts}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info, #diameter_event{service = Service,
				info = {closed, _Ref,
						{'CER', _ResultCode, _Caps, _Pkt},
						_Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info,
		#diameter_event{service = Service,
				info = {closed, _Ref,
						{'CER', _Caps, {_ResultCode, _Pkt}},
						_Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info,
		#diameter_event{service = Service,
				info = {closed, _Ref,
						{'CER', timeout},
						_Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info = _EventType,
		#diameter_event{service = Service,
				info = {closed, _Ref,
						{'CEA', _Result, _Caps, _Pkt},
						_Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info = _EventType,
		#diameter_event{service = Service,
				info = {closed, _Ref,
						{'CEA', _Caps, _Pkt},
						_Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info = _EventType,
		#diameter_event{service = Service,
				info = {closed, _Ref,
						{'CEA', timeout},
						_Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info, #diameter_event{service = Service,
				info = {watchdog, _Ref, _PeerRef, {_From, _To}, _Config}},
		#{service := Service} = _Data) ->
	keep_state_and_data;
started(info, #diameter_event{service = Service,
				info = _Other}, #{service := Service} = _Data) ->
	keep_state_and_data;
started(info, #diameter_event{service = Service,
				 info = stop},
		#{service := Service} = Data) ->
	{stop, stop, Data};
started(info, {'EXIT', _Pid, Reason}, Data) ->
	{stop, Reason, Data}.

-spec send_notification(Event, Peer, AlarmList) -> ok
	when
		Event :: up | down,
		Peer :: string(),
		AlarmList :: [Alarms],
		Alarms :: {Notification, Options},
		Notification  :: atom(),
		Options :: [{OptionName, OptionValue}],
		OptionName :: notify_name,
		OptionValue :: term().
%% @doc Send a SNMP Notification.
send_notification(up, Peer, AlarmList) ->
	case lists:keyfind(dbpPeerConnectionUpNotif, 1, AlarmList) of
		{Notification, Options} ->
			NotifyName = lists:keyfind(notify_name, 1, Options),
			Varbinds = [{dbpPeerId, Peer}],
			send_notification1(Notification, NotifyName, Varbinds);
		false ->
			ok
	end;
send_notification(down, Peer, AlarmList) ->
	case lists:keyfind(dbpPeerConnectionDownNotif, 1, AlarmList) of
		{Notification, Options} ->
			NotifyName = lists:keyfind(notify_name, 1, Options),
			Varbinds = [{dbpPeerId, Peer}],
			send_notification1(Notification, NotifyName, Varbinds);
		false ->
			ok
	end.
%% @hidden
send_notification1(Notification, false = NotifyName, Varbinds) ->
	case catch snmpa:send_notification(snmp_master_agent,
			Notification, no_receiver, Varbinds) of
		ok ->
			ok;
		{Error, Reason} when Error == error; Error == 'EXIT' ->
			error_logger:info_report(["SNMP Notification send faliure",
					{notification, Notification}, {notify_name, NotifyName},
					{error, Reason}])
	end;
send_notification1(Notification, {notify_name, NotifyName}, Varbinds) ->
	case catch snmpa:send_notification(snmp_master_agent,
			Notification, no_receiver, NotifyName, Varbinds) of
		ok ->
			ok;
		{Error, Reason} when Error == error; Error == 'EXIT' ->
			error_logger:info_report(["SNMP Notification send faliure",
					{notification, Notification}, {notify_name, NotifyName},
					{error, Reason}])
	end.

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
terminate(_Reason, _StateName, #{transport_ref := TransRef,
		address := Address, port := Port} = _Data) ->
	SvcName = ?DIAMETER_SERVICE(Address, Port),
	ok = diameter:stop_service(SvcName),
	case diameter:remove_transport(SvcName, TransRef) of
		ok ->
			ok;
		{error, Reason1} ->
			error_logger:error_report(["Failed to remove transport",
					{module, ?MODULE}, {error, Reason1}])
	end.

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

-spec service_options(Options) -> Options
	when
		Options :: [tuple()].
%% @doc Returns options for a DIAMETER service
%% @hidden
service_options(Options) ->
	{Options1, Realm} = case lists:keyfind('Origin-Realm', 1, Options) of
		{'Origin-Realm', R} ->
			{Options, R};
		false ->
			OriginRealm = case inet_db:res_option(domain) of
				S when length(S) > 0 ->
					S;
				_ ->
					"example.net"
			end,
			{[{'Origin-Realm', OriginRealm} | Options], OriginRealm}
	end,
	{ok, Hostname} = inet:gethostname(),
	Options2 = case lists:keyfind('Origin-Host', 1, Options1) of
		{_, _OriginHost} ->
			Options1;
		false when length(Hostname) > 0 ->
			[{'Origin-Host', Hostname ++ "." ++ Realm} | Options1];
		false ->
			[{'Origin-Host', "cse." ++ Realm} | Options1]
	end,
	BaseApps = [{application, [{alias, ?BASE_APPLICATION},
				{dictionary, ?BASE_APPLICATION_DICT},
				{module, ?BASE_APPLICATION_CALLBACK},
				{request_errors, callback}]}],
	Fold = fun({application, _} = App, {Apps, Opts}) ->
				{[App | Apps], Opts};
			(Opt, {Apps, Opts}) ->
				{Apps, [Opt | Opts]}
	end,
	{LocalApps, Options3} = lists:foldl(Fold, {BaseApps, []}, Options2),
	{SVendorIds, Options4} = case lists:keytake('Supported-Vendor-Id',
			1, Options3) of
		false ->
			{[?IANA_PEN_3GPP], Options3};
		{_ ,{_, SVI}, Opts1} ->
			{SVI, Opts1}
	end,
	Options5 = case lists:keymember('Inband-Security-Id', 1, Options4) of
		true ->
			Options4;
		false ->
			[{'Inband-Security-Id', [0]} | Options4]
	end,
	{ok, Vsn} = application:get_key(vsn),
	Version = list_to_integer([C || C <- Vsn, C /= $.]),
	BaseOptions = [{'Vendor-Id', ?IANA_PEN_SigScale},
		{'Product-Name', "SigScale CSE"},
		{'Firmware-Revision', Version},
		{'Supported-Vendor-Id', SVendorIds},
		{restrict_connections, false},
		{string_decode, false}],
	BaseOptions ++ Options5 ++ LocalApps.

-spec transport_options(Address, Port, Options) -> Options
	when
		Address :: inet:ip_address(),
		Port :: inet:port_number(),
		Options :: {listen, [diameter:transport_opt()]}
				| {connect, [diameter:transport_opt()]}.
%% @doc Returns options for a DIAMETER transport layer.
%% @hidden
transport_options(Address, Port, {Role, TOptions}) ->
	TOptions1 = case lists:keymember(transport_module, 1, TOptions) of
		true ->
			TOptions;
		false ->
			[{transport_module, diameter_tcp} | TOptions]
	end,
	{Config5, TOptions3} = case lists:keytake(transport_config, 1, TOptions1) of
		{value, {_, Config1}, TOptions2} ->
			Config2 = lists:keystore(reuseaddr, 1, Config1, {reuseaddr, true}),
			Config3 = lists:keystore(port, 1, Config2, {port, Port}),
			Config4 = lists:usort([{ip, Address} | Config3]),
			{Config4, TOptions2};
		false ->
			Config1 = [{reuseaddr, true}, {ip, Address}, {port, Port}],
			{Config1, TOptions1}
	end,
	transport_options1(Role, Config5, TOptions3).
%% @hidden
transport_options1(listen, Config, TOptions) ->
	{listen, [{transport_config, Config} | TOptions]};
transport_options1(connect, Config, TOptions) ->
	true = lists:keymember(raddr, 1, Config),
	true = lists:keymember(rport, 1, Config),
	{connect, [{transport_config, Config} | TOptions]}.

-spec split_options(Options) -> Result
	when
		Options :: [tuple()],
		Result :: {Transport, Service},
		Transport :: {listen, [diameter:transport_opt()]}
				| {connect, [diameter:transport_opt()]},
		Service :: [diameter:service_opt()].
%% @doc Split `Options' list into transport and service options.
split_options(Options) ->
	case lists:keytake(connect, 1, Options) of
		{value, Connect, Service} ->
			{Connect, Service};
		false ->
			case lists:keytake(listen, 1, Options) of
				{value, Listen, Service} ->
					{Listen, Service};
				false ->
					{{listen, []}, Options}
			end
	end.

