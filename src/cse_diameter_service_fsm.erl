%%% cse_diameter_service_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
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
%%% 	module handles {@link //diameter. diameter} service  events.
%%%
-module(cse_diameter_service_fsm).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([wait_for_start/3, started/3, wait_for_stop/3]).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("kernel/include/inet.hrl").

-type state() :: wait_for_start | started | wait_for_stop.
-type statedata() :: #{transport_ref =>  undefined | reference(),
		address => inet:ip_address(),
		port => inet:port_number(),
		options => list()}.

-define(DIAMETER_SERVICE(A, P), {cse_diameter_service_fsm, A, P}).
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
	TOptions2 = transport_options(TOptions1, Address, Port),
	SOptions2 = service_options(SOptions1),
	SvcName = ?DIAMETER_SERVICE(Address, Port),
	diameter:subscribe(SvcName),
	case diameter:start_service(SvcName, SOptions2) of
		ok ->
			process_flag(trap_exit, true),
			case diameter:add_transport(SvcName, TOptions2) of
				{ok, Ref} ->
					{ok, Alarms} = application:get_env(cse, snmp_alarms),
					Data = #{transport_ref => Ref, address => Address,
							port => Port, options => Options, alarms => Alarms},
					{ok, wait_for_start, Data};
				{error, Reason} ->
					{stop, Reason}
			end;
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
wait_for_start(_EventType, null = _EventContent, _Data) ->
	keep_state_and_data;
wait_for_start(info, #diameter_event{info = start} = _EventContent, Data) ->
	{next_state, started, Data};
wait_for_start(info, {'EXIT', _Pid, noconnection}, Data) ->
	{stop, noconnection, Data};
wait_for_start(info, #diameter_event{info = stop, service = Service},
		#{service := Service} = Data) ->
	{stop, stop, Data}.

-spec started(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>started</em> state.
%% @private
started(_EventType, null = _EventContent, _Data) ->
	keep_state_and_data;
started(info, #diameter_event{info = Event, service = Service},
		#{alarms := Alarms} = Data) when element(1, Event) == up;
		element(1, Event) == down ->
	{_PeerRef, #diameter_caps{origin_host = {_, P}}} = element(3, Event),
	Peer = binary_to_list(P),
	error_logger:info_report(["DIAMETER peer connection state changed",
			{service, Service}, {event, element(1, Event)},
			{peer, Peer}]),
	ok = send_notification(element(1, Event), Peer, Alarms),
	{next_state, started, Data};
started(info, #diameter_event{info = Event, service = Service},
		Data) when element(1, Event) == closed ->
	{_CER, _Caps, #diameter_caps{origin_host = {_, Peer}}, _Packet} = element(3, Event),
	error_logger:info_report(["DIAMETER peer connection state changed",
			{service, Service}, {event, element(1, Event)},
			{peer, binary_to_list(Peer)}]),
	{stop, stop, Data};
started(info, #diameter_event{info = {watchdog,
			_Ref, _PeerRef, {_From, _To}, _Config}}, Data) ->
	{next_state, started, Data};
started(info, {'EXIT', _Pid, noconnection}, Data) ->
	{stop, noconnection, Data};
started(info, #diameter_event{info = stop, service = Service},
		#{service := Service} = Data) ->
	{stop, stop, Data};
started(info, #diameter_event{info = Event, service = Service},
		Data) ->
	error_logger:info_report(["DIAMETER event",
			{service, Service}, {event, Event}]),
	{next_state, started, Data}.

-spec wait_for_stop(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>wait_for_stop</em> state.
%% @private
wait_for_stop(_EventType, null = _EventContent, _Data) ->
	keep_state_and_data;
wait_for_stop(info, #diameter_event{info = Event, service = Service},
		#{alarms := Alarms} = Data) when element(1, Event) == up;
		element(1, Event) == down ->
	{_PeerRef, #diameter_caps{origin_host = {_, P}}} = element(3, Event),
	Peer = binary_to_list(P),
	error_logger:info_report(["DIAMETER peer connection state changed",
			{service, Service}, {event, element(1, Event)},
			{peer, Peer}]),
	ok = send_notification(element(1, Event), Peer, Alarms),
	{next_state, started, Data};
wait_for_stop(info, #diameter_event{info = {watchdog,
			_Ref, _PeerRef, {_From, _To}, _Config}}, Data) ->
	{next_state, shutdown, Data};
wait_for_stop(info, #diameter_event{info = Event, service = Service},
		#{service := Service} = Data) ->
	error_logger:info_report(["DIAMETER event",
			{service, Service}, {event, Event}]),
	{next_state, shutdown, Data};
wait_for_stop(info, {'EXIT', _Pid, noconnection}, Data) ->
	{stop, noconnection, Data};
wait_for_stop(info, #diameter_event{info = stop, service = Service},
		#{service := Service} = Data) ->
	{stop, stop, Data}.

-spec send_notification(Event, Peer, AlarmList) -> ok
	when
		Event :: up | down,
		Peer :: string(),
		AlarmList :: [Alarms],
		Alarms :: {Notification, Options},
		Notification  :: atom(),
		Options :: [{OptionName, OptionValue}],
		OptionName :: term(),
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
send_notification1(Notification, false, Varbinds) ->
	case catch snmpa:send_notification(snmp_master_agent,
			Notification, no_receiver, Varbinds) of
		ok ->
			ok;
		{'EXIT', Reason} ->
			error_logger:info_report(["SNMP Notification send faliure",
					{notification, Notification}, {notify_name, false},
					{error, Reason}])
	end;
send_notification1(Notification, {notify_name, NotifyName}, Varbinds) ->
	case catch snmpa:send_notification(snmp_master_agent,
			Notification, no_receiver, NotifyName, Varbinds) of
		ok ->
			ok;
		{'EXIT', Reason} ->
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
terminate(_Reason1, _StateName, #{transport_ref := TransRef,
		address := Address, port := Port} = _Data) ->
	SvcName = ?DIAMETER_SERVICE(Address, Port),
	case diameter:remove_transport(SvcName, TransRef) of
		ok ->
			diameter:stop_service(SvcName);
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
	BaseApplications = [{application, [{alias, ?BASE_APPLICATION},
				{dictionary, ?BASE_APPLICATION_DICT},
				{module, ?BASE_APPLICATION_CALLBACK},
				{request_errors, callback}]}],
	{NewApps, Options3} = case lists:keytake(application, 1, Options2) of
		false ->
			{BaseApplications, Options2};
		{value, DiameterApplications, Opts} ->
			{BaseApplications ++ [DiameterApplications], Opts}
	end,
	{SVendorIds, Options4} = case lists:keytake('Supported-Vendor-Id', 1, Options3) of
		false ->
			{[?IANA_PEN_3GPP], Options3};
		{_ ,{_, SVI}, Opts1} ->
			{[?IANA_PEN_3GPP] ++ SVI, Opts1}
	end,
	{ok, Vsn} = application:get_key(vsn),
	Version = list_to_integer([C || C <- Vsn, C /= $.]),
	BaseOptions = [{'Vendor-Id', ?IANA_PEN_SigScale},
		{'Product-Name', "SigScale CSE"},
		{'Firmware-Revision', Version},
		{'Supported-Vendor-Id', SVendorIds},
		{restrict_connections, false},
		{string_decode, false}],
	BaseOptions ++ Options4 ++ NewApps.

-spec transport_options(Options, Address, Port) -> Result
	when
		Options :: [tuple()],
		Address :: inet:ip_address(),
		Port :: inet:port_number(),
		Result :: {listen, Options}.
%% @doc Returns options for a DIAMETER transport layer
%% @hidden
transport_options(Options, Address, Port) ->
	Options1 = case lists:keymember(transport_module, 1, Options) of
		true ->
			Options;
		false ->
			[{transport_module, diameter_tcp} | Options]
	end,
	Options2 = case lists:keyfind(transport_config, 1, Options1) of
		{transport_config, Opts} ->
			Opts1 = lists:keystore(reuseaddr, 1, Opts, {reuseaddr, true}),
			Opts2 = lists:keystore(ip, 1, Opts1, {ip, Address}),
			Opts3 = lists:keystore(port, 1, Opts2, {port, Port}),
			lists:keyreplace(transport_config, 1, Options1, {transport_config, Opts3});
		false ->
			Opts = [{reuseaddr, true}, {ip, Address}, {port, Port}],
			[{transport_config, Opts} | Options1]
	end,
	{listen, Options2}.

-spec split_options(Options) -> Result
	when
		Options :: [tuple()],
		Result :: {TOptions, SOptions},
		TOptions :: [tuple()],
		SOptions :: [tuple()].
%% @doc Split `Options' list into transport and service options.
split_options(Options) ->
	split_options(Options, [], []).
%% @hidden
split_options([{'Origin-Host', DiameterIdentity} = H | T], Acc1, Acc2)
		when is_list(DiameterIdentity) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Origin-Realm', DiameterIdentity} = H | T], Acc1, Acc2)
		when is_list(DiameterIdentity) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{application, ApplicationsOpts} = H | T], Acc1, Acc2)
		when is_list(ApplicationsOpts) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Host-IP-Address', Addresses} = H | T], Acc1, Acc2)
		when is_list(Addresses), is_tuple(hd(Addresses)) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Vendor-Id', _} | T], Acc1, Acc2) ->
	split_options(T, Acc1, Acc2);
split_options([{'Product-Name', _} | T], Acc1, Acc2) ->
	split_options(T, Acc1, Acc2);
split_options([{'Origin-State-Id', _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Supported-Vendor-Id', _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Auth-Application-Id', Id} = H | T], Acc1, Acc2)
		when is_list(Id) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Acct-Application-Id', Id} = H | T], Acc1, Acc2)
		when is_list(Id) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Inband-Security-Id', _} = H| T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Vendor-Specific-Application-Id', _} = H| T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{'Firmware-Revision', _} | T], Acc1, Acc2) ->
	split_options(T, Acc1, Acc2);
split_options([{capx_timeout, Timeout} = H | T], Acc1, Acc2)
		when is_integer(Timeout) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{incoming_maxlen, MaxLength} = H | T], Acc1, Acc2)
		when is_integer(MaxLength) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{pool_size, PoolSize} = H | T], Acc1, Acc2)
		when is_integer(PoolSize) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{watchdog_timer, TwInit} = H | T], Acc1, Acc2)
		when is_integer(TwInit) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{transport_module, diameter_tcp} = H | T], Acc1, Acc2) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{transport_module, diameter_sctp} = H | T], Acc1, Acc2) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{transport_config, _} = H | T], Acc1, Acc2) ->
	split_options(T, [H | Acc1], Acc2);
split_options([{decode_format, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{restrict_connections, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{sequence, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{share_peers, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{strict_arities, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{string_decode, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{traffic_counters, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([{use_shared_peers, _} = H | T], Acc1, Acc2) ->
	split_options(T, Acc1, [H | Acc2]);
split_options([_H | T], Acc1, Acc2) ->
	split_options(T, Acc1, Acc2);
split_options([], Acc1, Acc2) ->
	{Acc1, Acc2}.

