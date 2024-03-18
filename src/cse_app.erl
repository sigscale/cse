%%% cse_app.erl
%%% vim: ts=3
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
%%% @doc This {@link //stdlib/application. application} behaviour callback
%%%   module starts and stops the {@link //cse. cse} application.
%%%
-module(cse_app).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(application).

%% callbacks needed for application behaviour
-export([start/2, stop/1, config_change/3]).
%% optional callbacks for application behaviour
-export([prep_stop/1, start_phase/3]).
%% export the cse private API for installation
-export([install/0, install/1, join/1]).

-include_lib("inets/include/mod_auth.hrl").
-include("cse.hrl").

-record(state, {}).

-define(WAITFORSCHEMA, 10000).
-define(WAITFORTABLES, 60000).

%%----------------------------------------------------------------------
%%  The cse_app aplication callbacks
%%----------------------------------------------------------------------

-type start_type() :: normal | {takeover, node()} | {failover, node()}.
-spec start(StartType, StartArgs) -> Result
	when
		StartType :: start_type(),
		StartArgs :: term(),
		Result :: {ok, pid()} | {ok, pid(), State} | {error, Reason},
		State :: #state{},
		Reason :: term().
%% @doc Starts the application processes.
start(normal = _StartType, _Args) ->
	HttpdTables = case is_mod_auth_mnesia() of
		true ->
			[httpd_user, httpd_group];
		false ->
			[]
	end,
	Tables = [resource_spec, resource,
			cse_service, cse_context] ++ HttpdTables,
	{ok, Wait} = application:get_env(wait_tables),
	case mnesia:wait_for_tables(Tables, Wait) of
		ok ->
			start1();
		{timeout, BadTables} ->
			case force(BadTables) of
				ok ->
					error_logger:warning_report(["Force loaded mnesia tables",
							{tables, BadTables}, {module, ?MODULE}]),
					start1();
				{error, Reason} ->
					error_logger:error_report(["Failed to force load mnesia tables",
							{tables, BadTables}, {reason, Reason}, {module, ?MODULE}]),
					{error, Reason}
			end;
		{error, Reason} ->
			error_logger:error_report(["Failed to load mnesia tables",
					{tables, Tables}, {reason, Reason}, {module, ?MODULE}]),
			{error, Reason}
	end.
%% @hidden
start1() ->
	start2([cse_rest_res_resource:prefix_table_spec_id(),
			cse_rest_res_resource:prefix_row_spec_id()], []).
%% @hidden
start2([H | T], Acc) ->
	case cse:find_resource_spec(H) of
		{ok, _} ->
			start2(T, Acc);
		{error, not_found} ->
			start2(T, [H | Acc]);
		{error, Reason} ->
			{error, Reason}
	end;
start2([], Acc) when length(Acc) > 0 ->
	case install_resource_specs(Acc) of
		ok ->
			start3();
		{error, Reason} ->
			{error, Reason}
	end;
start2([], []) ->
	start3().
%% @hidden
start3() ->
	case inets:services_info() of
		ServicesInfo when is_list(ServicesInfo) ->
			{ok, Profile} = application:get_env(nrf_profile),
			start4(Profile, ServicesInfo);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start4(Profile, [{httpc, _Pid, Info} | T]) ->
	case proplists:lookup(profile, Info) of
		{profile, Profile} ->
			start5(Profile);
		_ ->
			start4(Profile, T)
	end;
start4(Profile, [_ | T]) ->
	start4(Profile, T);
start4(Profile, []) ->
	case inets:start(httpc, [{profile, Profile}]) of
		{ok, _Pid} ->
			start5(Profile);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start5(Profile) ->
	{ok, Options} = application:get_env(nrf_options),
	case httpc:set_options(Options, Profile) of
		ok ->
			start6();
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start6() ->
	Options = [set, public, named_table, {write_concurrency, true}],
	ets:new(cse_counters, Options),
	case catch ets:insert(cse_counters, {nrf_seq, 0}) of
		true ->
			start7();
		{'EXIT', Reason} ->
			{error, Reason}
	end.
%% @hidden
start7() ->
	Options = [set, public, named_table,
			{write_concurrency, true}, {keypos, 1}],
	case catch ets:new(cse_session, Options) of
		{'EXIT', Reason} ->
			{error, Reason};
		_TID ->
			start8()
	end.
%% @hidden
start8() ->
	case supervisor:start_link({local, cse_sup}, cse_sup, []) of
		{ok, TopSup} ->
			{ok, Logs} = application:get_env(logs),
			start9(TopSup, Logs);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start9(TopSup, [{LogName, Options} | T]) ->
	case cse_log:open(LogName, Options) of
		ok ->
			start9(TopSup, T);
		{error, Reason} ->
			{error, Reason}
	end;
start9(TopSup, []) ->
	{ok, DiameterServices} = application:get_env(diameter),
	start10(TopSup, DiameterServices).
%% @hidden
start10(TopSup, [] = DiameterServices) ->
	start11(TopSup, DiameterServices);
start10(TopSup, DiameterServices) ->
	case application:start(diameter) of
		ok ->
			start11(TopSup, DiameterServices);
		{error, {already_started, _}} ->
			start11(TopSup, DiameterServices);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start11(TopSup, [{Addr, Port, Options} | T]) ->
	case cse:start_diameter(Addr, Port, Options) of
		{ok, _Sup} ->
			start11(TopSup, T);
		{error, Reason} ->
			{error, Reason}
	end;
start11(TopSup, []) ->
	catch cse_mib:load(),
	{ok, TopSup}.

-spec start_phase(Phase, StartType, PhaseArgs) -> Result
	when
		Phase :: atom(),
		StartType :: start_type(),
		PhaseArgs :: term(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Called for each start phase in the application and included
%%   applications.
%% @see //kernel/app
%%
start_phase(_Phase, _StartType, _PhaseArgs) ->
	ok.

-spec prep_stop(State) -> #state{}
	when
		State :: #state{}.
%% @doc Called when the application is about to be shut down,
%%   before any processes are terminated.
%% @see //kernel/application:stop/1
%%
prep_stop(State) ->
	State.

-spec stop(State) -> any()
	when
		State :: #state{}.
%% @doc Called after the application has stopped to clean up.
%%
stop(_State) ->
	ok.

-spec config_change(Changed, New, Removed) -> ok
	when
		Changed:: [{Par, Val}],
		New :: [{Par, Val}],
		Removed :: [Par],
		Par :: atom(),
		Val :: atom().
%% @doc Called after a code  replacement, if there are any
%%   changes to the configuration  parameters.
%%
config_change(_Changed, _New, _Removed) ->
	ok.

-spec install() -> Result
	when
		Result :: {ok, Tables} | {error, Reason},
		Tables :: [atom()],
		Reason :: term().
%% @equiv install([node() | nodes()])
install() ->
	Nodes = [node() | nodes()],
	install(Nodes).

-spec install(Nodes) -> Result
	when
		Nodes :: [node()],
		Result :: {ok, Tables} | {error, Reason},
		Tables :: [atom()],
		Reason :: term().
%% @doc Initialize CSE tables.
%% 	`Nodes' is a list of the nodes where
%% 	{@link //cse. cse} tables will be replicated.
%%
%% 	If {@link //mnesia. mnesia} is not running an attempt
%% 	will be made to create a schema on all available nodes.
%% 	If a schema already exists on any node
%% 	{@link //mnesia. mnesia} will be started on all nodes
%% 	using the existing schema.
%%
%% @private
%%
install(Nodes) when is_list(Nodes) ->
	case mnesia:system_info(is_running) of
		no ->
			case mnesia:create_schema(Nodes) of
				ok ->
					error_logger:info_report("Created mnesia schema",
							[{nodes, Nodes}]),
					install1(Nodes);
				{error, {_, {already_exists, _}}} ->
						error_logger:info_report("mnesia schema already exists",
						[{nodes, Nodes}]),
					install1(Nodes);
				{error, Reason} ->
					error_logger:error_report(["Failed to create schema",
							mnesia:error_description(Reason),
							{nodes, Nodes}, {error, Reason}]),
					{error, Reason}
			end;
		_ ->
			install2(Nodes)
	end.
%% @hidden
install1([Node] = Nodes) when Node == node() ->
	case mnesia:start() of
		ok ->
			error_logger:info_msg("Started mnesia~n"),
			install2(Nodes);
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
					{error, Reason}]),
			{error, Reason}
	end;
install1(Nodes) ->
	case rpc:multicall(Nodes, mnesia, start, [], 60000) of
		{Results, []} ->
			F = fun(ok) ->
						false;
					(_) ->
						true
			end,
			case lists:filter(F, Results) of
				[] ->
					error_logger:info_report(["Started mnesia on all nodes",
							{nodes, Nodes}]),
					install2(Nodes);
				NotOKs ->
					error_logger:error_report(["Failed to start mnesia"
							" on all nodes", {nodes, Nodes}, {errors, NotOKs}]),
					{error, NotOKs}
			end;
		{Results, BadNodes} ->
			error_logger:error_report(["Failed to start mnesia"
					" on all nodes", {nodes, Nodes}, {results, Results},
					{badnodes, BadNodes}]),
			{error, {Results, BadNodes}}
	end.
%% @hidden
install2(Nodes) ->
	Wait = case application:get_env(cse, wait_tables) of
		{ok, Wait1} ->
			Wait1;
		undefined ->
			ok = application:load(cse),
			{ok, Wait1} = application:get_env(cse, wait_tables),
			Wait1
	end,
	case mnesia:wait_for_tables([schema], Wait) of
		ok ->
			install3(Nodes, []);
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason};
		{timeout, BadTables} ->
			error_logger:error_report(["Timeout waiting for tables",
					{tables, BadTables}]),
			{error, timeout}
	end.
%% @hidden
install3(Nodes, Acc) ->
	case create_table(resource_spec, Nodes) of
		ok ->
			install4(Nodes, [resource_spec | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install4(Nodes, Acc) ->
	case create_table(resource, Nodes) of
		ok ->
			install5(Nodes, [resource | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install5(Nodes, Acc) ->
	case create_table(cse_service, Nodes) of
		ok ->
			install6(Nodes, [cse_service | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
install6(Nodes, Acc) ->
	case create_table(cse_context, Nodes) of
		ok ->
			install7(Nodes, [cse_context | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install7(Nodes, Acc) ->
	case application:load(inets) of
		ok ->
			error_logger:info_msg("Loaded inets.~n"),
			install8(Nodes, Acc);
		{error, {already_loaded, inets}} ->
			install8(Nodes, Acc)
	end.
%% @hidden
install8(Nodes, Acc) ->
	case is_mod_auth_mnesia() of
		true ->
			install9(Nodes, Acc);
		false ->
			error_logger:info_msg("Httpd service not defined. "
					"User table not created~n"),
			install11(Nodes, Acc)
	end.
%% @hidden
install9(Nodes, Acc) ->
	case create_table(httpd_user, Nodes) of
		ok ->
			install10(Nodes, [httpd_user | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install10(Nodes, Acc) ->
	case create_table(httpd_group, Nodes) of
		ok ->
			install11(Nodes, [httpd_group | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install11(_Nodes, Tables) ->
	{ok, Wait} = application:get_env(cse, wait_tables),
	case mnesia:wait_for_tables(Tables, Wait) of
		ok ->
			install12(Tables, lists:member(httpd_user, Tables));
		{timeout, Tables} ->
			error_logger:error_report(["Timeout waiting for tables",
					{tables, Tables}]),
			{error, timeout};
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
					{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
install12(Tables, true) ->
	case inets:start() of
		ok ->
			error_logger:info_msg("Started inets.~n"),
			install13(Tables);
		{error, {already_started, inets}} ->
			install13(Tables);
		{error, Reason} ->
			error_logger:error_msg("Failed to start inets~n"),
			{error, Reason}
	end;
install12(Tables, false) ->
	install14(Tables).
%% @hidden
install13(Tables) ->
	case cse:list_users() of
		{ok, []} ->
			UserData = [{locale, "en"}],
			case cse:add_user("admin", "admin", UserData) of
				{ok, _LastModified} ->
					error_logger:info_report(["Created a default user",
							{username, "admin"}, {password, "admin"},
							{locale, "en"}]),
					install14(Tables);
				{error, Reason} ->
					error_logger:error_report(["Failed to creat default user",
							{username, "admin"}, {password, "admin"},
							{locale, "en"}]),
					{error, Reason}
			end;
		{ok, Users} ->
			error_logger:info_report(["Found existing http users",
					{users, Users}]),
			install14(Tables);
		{error, Reason} ->
			error_logger:error_report(["Failed to list http users",
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
install14(Tables) ->
	case install_resource_specs() of
		ok ->
			install15([resource_spec | Tables ]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install15(Tables) ->
	cse:add_context("32251@3gpp.org",
			cse_slp_prepaid_diameter_ps_fsm, [], []),
	cse:add_context("32260@3gpp.org",
			cse_slp_prepaid_diameter_ims_fsm, [], []),
	cse:add_context("32270@3gpp.org",
			cse_slp_prepaid_diameter_mms_fsm, [], []),
	cse:add_context("32274@3gpp.org",
			cse_slp_prepaid_diameter_sms_fsm, [], []),
	cse:add_context("32276@3gpp.org",
			cse_slp_prepaid_diameter_ims_fsm, [], []),
	{ok, Tables}.

-spec join(Node) -> Result
	when
		Node :: atom(),
		Result :: {ok, Tables} | {error, Reason},
		Tables :: [atom()],
		Reason :: term().
%% @doc Join an existing cluster.
%%
%% 	Tables will be copied from the given `Node'.
%%
join(Node) when is_atom(Node)  ->
	case mnesia:system_info(is_running) of
		no ->
			join1(Node);
		Running ->
			error_logger:error_report(["mnesia running", {is_running, Running}]),
			{error, mnesia_running}
	end.
%% @hidden
join1(Node) ->
	case net_kernel:connect_node(Node) of
		true ->
			join2(Node);
		Connect ->
			error_logger:error_report(["Failed to connect node",
					{result, Connect}]),
			{error, Connect}
	end.
%% @hidden
join2(Node) ->
	case rpc:call(Node, mnesia, add_table_copy, [schema, node(), ram_copies]) of
		{atomic, ok} ->
			join3(Node);
		{aborted, {already_exists, schema, _}} ->
			error_logger:info_msg("Found existing schema table on ~s.~n", [Node]),
			join3(Node);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join3(Node) ->
	case application:start(mnesia) of
		ok ->
			join4(Node);
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
					{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join4(Node) ->
	case mnesia:change_config(extra_db_nodes, [Node]) of
		{ok, _Nodes} ->
			join5(Node);
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
					{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join5(Node) ->
	case mnesia:change_table_copy_type(schema, node(), disc_copies) of
		{atomic, ok} ->
			error_logger:info_msg("Copied schema table from ~s.~n", [Node]),
			join6(Node, mnesia:system_info(db_nodes), [schema]);
		{aborted, {already_exists, schema, _, disc_copies}} ->
			error_logger:info_msg("Found existing schema table on ~s.~n", [Node]),
			join6(Node, mnesia:system_info(db_nodes), [schema]);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join6(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [resource_spec, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied resource_spec table from ~s.~n", [Node]),
			join7(Node, Nodes, [resource_spec | Acc]);
		{aborted, {already_exists, resource_spec, _}} ->
			error_logger:info_msg("Found existing resource_spec table on ~s.~n", [Node]),
			join7(Node, Nodes, [resource_spec | Acc]);
		{aborted, {no_exists, {resource_spec, _}}} ->
			case create_table(resource_spec, Nodes) of
				ok ->
					join7(Node, Nodes, [resource_spec | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join7(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [resource, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied resource table from ~s.~n", [Node]),
			join8(Node, Nodes, [resource | Acc]);
		{aborted, {already_exists, resource, _}} ->
			error_logger:info_msg("Found existing resource table on ~s.~n", [Node]),
			join8(Node, Nodes, [resource | Acc]);
		{aborted, {no_exists, {resource, _}}} ->
			case create_table(resource, Nodes) of
				ok ->
					join8(Node, Nodes, [resource | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join8(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [cse_service, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied cse_service table from ~s.~n", [Node]),
			join9(Node, Nodes, [cse_service | Acc]);
		{aborted, {already_exists, cse_service, _}} ->
			error_logger:info_msg("Found existing cse_service table on ~s.~n", [Node]),
			join9(Node, Nodes, [cse_service | Acc]);
		{aborted, {no_exists, {cse_service, _}}} ->
			case create_table(cse_service, Nodes) of
				ok ->
					join9(Node, Nodes, [cse_service | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join9(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [cse_context, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied cse_context table from ~s.~n", [Node]),
			join10(Node, Nodes, [cse_context | Acc]);
		{aborted, {already_exists, cse_context, _}} ->
			error_logger:info_msg("Found existing cse_context table on ~s.~n", [Node]),
			join10(Node, Nodes, [cse_context | Acc]);
		{aborted, {no_exists, {cse_context, _}}} ->
			case create_table(cse_context, Nodes) of
				ok ->
					join10(Node, Nodes, [cse_context | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join10(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [m3ua_as, node(), ram_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied m3ua_as table from ~s.~n", [Node]),
			join11(Node, Nodes, [m3ua_as | Acc]);
		{aborted, {already_exists, m3ua_as, _}} ->
			error_logger:info_msg("Found existing m3ua_as table on ~s.~n", [Node]),
			join11(Node, Nodes, [m3ua_as | Acc]);
		{aborted, {no_exists, {m3ua_as , _}}} ->
			error_logger:info_msg("No m3ua_as table found on ~s.~n", [Node]),
			join11(Node, Nodes, Acc);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join11(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [m3ua_asp, node(), ram_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied m3ua_asp table from ~s.~n", [Node]),
			join12(Node, Nodes, [m3ua_asp | Acc]);
		{aborted, {already_exists, m3ua_asp, _}} ->
			error_logger:info_msg("Found existing m3ua_asp table on ~s.~n", [Node]),
			join12(Node, Nodes, [m3ua_asp | Acc]);
		{aborted, {no_exists, {m3ua_asp , _}}} ->
			error_logger:info_msg("No m3ua_asp table found on ~s.~n", [Node]),
			join12(Node, Nodes, Acc);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join12(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [gtt_as, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied gtt_as table from ~s.~n", [Node]),
			join13(Node, Nodes, [gtt_as | Acc]);
		{aborted, {already_exists, gtt_as, _}} ->
			error_logger:info_msg("Found existing gtt_as table on ~s.~n", [Node]),
			join13(Node, Nodes, [gtt_as | Acc]);
		{aborted, {no_exists, {gtt_as , _}}} ->
			error_logger:info_msg("No gtt_as table found on ~s.~n", [Node]),
			join13(Node, Nodes, Acc);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join13(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [gtt_ep, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied gtt_ep table from ~s.~n", [Node]),
			join14(Node, Nodes, [gtt_ep | Acc]);
		{aborted, {already_exists, gtt_ep, _}} ->
			error_logger:info_msg("Found existing gtt_ep table on ~s.~n", [Node]),
			join14(Node, Nodes, [gtt_ep | Acc]);
		{aborted, {no_exists, {gtt_ep , _}}} ->
			error_logger:info_msg("No gtt_ep table found on ~s.~n", [Node]),
			join14(Node, Nodes, Acc);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join14(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [gtt_pc, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied gtt_pc table from ~s.~n", [Node]),
			join15(Node, Nodes, [gtt_pc | Acc]);
		{aborted, {already_exists, gtt_pc, _}} ->
			error_logger:info_msg("Found existing gtt_pc table on ~s.~n", [Node]),
			join15(Node, Nodes, [gtt_pc | Acc]);
		{aborted, {no_exists, {gtt_pc , _}}} ->
			error_logger:info_msg("No gtt_pc table found on ~s.~n", [Node]),
			join15(Node, Nodes, Acc);
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join15(Node, Nodes, Acc) ->
   case application:load(inets) of
      ok ->
         error_logger:info_msg("Loaded inets.~n"),
         join16(Node, Nodes, Acc);
      {error, {already_loaded, inets}} ->
         join16(Node, Nodes, Acc);
      {error, Reason} ->
         {error, Reason}
   end.
%% @hidden
join16(Node, Exist, Acc) ->
   case is_mod_auth_mnesia() of
      true ->
         join17(Node, Exist, Acc);
      false ->
         error_logger:info_msg("Httpd service not defined. "
               "User table not created~n"),
         join17(Node, Exist, Acc)
   end.
%% @hidden
join17(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [httpd_user, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied httpd_user table from ~s.~n", [Node]),
			join18(Node, Nodes, [httpd_user | Acc]);
		{aborted, {already_exists, httpd_user, _}} ->
			error_logger:info_msg("Found existing httpd_user table on ~s.~n", [Node]),
			join18(Node, Nodes, [httpd_user | Acc]);
		{aborted, {no_exists, {httpd_user, _}}} ->
			case create_table(httpd_user, Nodes) of
				ok ->
					join18(Node, Nodes, [httpd_user | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join18(Node, Nodes, Acc) ->
	case rpc:call(Node, mnesia, add_table_copy, [httpd_group, node(), disc_copies]) of
		{atomic, ok} ->
			error_logger:info_msg("Copied httpd_group table from ~s.~n", [Node]),
			join19(Node, Nodes, [httpd_group | Acc]);
		{aborted, {already_exists, httpd_group, _}} ->
			error_logger:info_msg("Found existing httpd_group table on ~s.~n", [Node]),
			join19(Node, Nodes, [httpd_group | Acc]);
		{aborted, {no_exists, {httpd_group, _}}} ->
			case create_table(httpd_group, Nodes) of
				ok ->
					join19(Node, Nodes, [httpd_group | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
		{aborted, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
				{error, Reason}]),
			{error, Reason}
	end.
%% @hidden
join19(_Node, _Nodes, Tables) ->
	case mnesia:wait_for_tables(Tables, ?WAITFORTABLES) of
		ok ->
			{ok, Tables};
		{timeout, BadTables} ->
			error_logger:error_report(["Timeout waiting for tables",
					{tables, BadTables}]),
			{error, timeout};
		{error, Reason} ->
			error_logger:error_report([mnesia:error_description(Reason),
					{error, Reason}]),
			{error, Reason}
	end.

%%----------------------------------------------------------------------
%%  Internal functions
%%----------------------------------------------------------------------

-spec force(Tables) -> Result
	when
		Tables :: [TableName],
		Result :: ok | {error, Reason},
		TableName :: atom(),
		Reason :: term().
%% @doc Try to force load bad tables.
%% @private
force([H | T]) ->
	case mnesia:force_load_table(H) of
		yes ->
			force(T);
		ErrorDescription ->
			{error, ErrorDescription}
	end;
force([]) ->
	ok.

-spec create_table(Table, Nodes) -> Result
	when
		Table :: atom(),
		Nodes :: [node()],
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Create mnesia table.
%% @private
create_table(resource_spec, Nodes) when is_list(Nodes) ->
	create_table1(resource_spec, mnesia:create_table(resource_spec,
			[{disc_copies, Nodes},
			{attributes, record_info(fields, resource_spec)}]));
create_table(resource, Nodes) when is_list(Nodes) ->
	{ok, Type} = application:get_env(cse, resource_table_type),
	create_table1(resource, mnesia:create_table(resource,
			[{Type, Nodes},
			{attributes, record_info(fields, resource)}]));
create_table(cse_service, Nodes) when is_list(Nodes) ->
	create_table1(cse_service, mnesia:create_table(cse_service,
			[{disc_copies, Nodes},
			{record_name, in_service},
			{attributes, record_info(fields, in_service)}]));
create_table(cse_context, Nodes) when is_list(Nodes) ->
	create_table1(cse_context, mnesia:create_table(cse_context,
			[{disc_copies, Nodes},
			{record_name, diameter_context},
			{attributes, record_info(fields, diameter_context)}]));
create_table(httpd_user, Nodes) when is_list(Nodes) ->
	create_table1(httpd_user,
			mnesia:create_table(httpd_user, [{type, bag},
			{disc_copies, Nodes},
			{attributes, record_info(fields, httpd_user)}]));
create_table(httpd_group, Nodes) when is_list(Nodes) ->
	create_table1(httpd_group,
			mnesia:create_table(httpd_group,
			[{type, bag}, {disc_copies, Nodes},
			{attributes, record_info(fields, httpd_group)}])).
%% @hidden
create_table1(Table, {atomic, ok}) ->
	error_logger:info_msg("Created new ~w table.~n", [Table]),
	ok;
create_table1(Table, {aborted, {already_exists, Table}}) ->
	error_logger:info_msg("Found existing ~w table.~n", [Table]),
	ok;
create_table1(_Table, {aborted, {not_active, _, Node} = Reason}) ->
	error_logger:error_report(["Mnesia not started on node", {node, Node}]),
	{error, Reason};
create_table1(_Table, {aborted, Reason}) ->
	error_logger:error_report([mnesia:error_description(Reason), {error, Reason}]),
	{error, Reason}.

-spec install_resource_specs() -> Result
	when
		Result :: ok | {error, Reason},
		Reason :: term().
%% @equiv install_resource_specs([cse_rest_res_resource:prefix_table_spec_id(),
%% 		cse_rest_res_resource:prefix_row_spec_id(),
%%			cse_rest_res_resource:prefix_range_table_spec_id(),
%%			cse_rest_res_resource:prefix_range_row_spec_id()])
%% @private
install_resource_specs() ->
	SpecIds = [cse_rest_res_resource:index_table_spec_id(),
			cse_rest_res_resource:index_row_spec_id(),
			cse_rest_res_resource:prefix_table_spec_id(),
			cse_rest_res_resource:prefix_row_spec_id(),
			cse_rest_res_resource:prefix_range_table_spec_id(),
			cse_rest_res_resource:prefix_range_row_spec_id()],
	install_resource_specs(SpecIds).

-spec install_resource_specs(SpecIds) -> Result
	when
		SpecIds :: [binary()],
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Install static Resource Specifications.
%% @private
install_resource_specs([H | T]) ->
	Spec = cse_rest_res_resource:static_spec(H),
	F = fun() ->
				mnesia:write(resource_spec, Spec, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			install_resource_specs(T);
		{aborted, Reason} ->
			{error, Reason}
	end;
install_resource_specs([]) ->
	ok.

-spec is_mod_auth_mnesia() -> boolean().
%% @doc Check if inets mod_auth uses mmnesia tables.
%% @hidden
is_mod_auth_mnesia() ->
	case application:get_env(inets, services) of
		{ok, InetsServices} ->
			is_mod_auth_mnesia1(InetsServices);
		undefined ->
			false
	end.
%% @hidden
is_mod_auth_mnesia1(InetsServices) ->
	case lists:keyfind(httpd, 1, InetsServices) of
		{httpd, HttpdInfo} ->
			F = fun({directory, _}) ->
						true;
					(_) ->
						false
			end,
			is_mod_auth_mnesia2(lists:filter(F, HttpdInfo));
		false ->
			false
	end.
%% @hidden
is_mod_auth_mnesia2([{directory, {_Dir, []}} | T]) ->
	is_mod_auth_mnesia2(T);
is_mod_auth_mnesia2([{directory, {_, DirectoryInfo}} | T]) ->
	case lists:keyfind(auth_type, 1, DirectoryInfo) of
		{auth_type, mnesia} ->
			true;
		_ ->
			is_mod_auth_mnesia2(T)
	end;
is_mod_auth_mnesia2([]) ->
	false.

