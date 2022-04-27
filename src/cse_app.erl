%%% cse_app.erl
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
%%% @doc This {@link //stdlib/application. application} behaviour callback
%%%   module starts and stops the {@link //cse. cse} application.
%%%
-module(cse_app).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(application).

%% callbacks needed for application behaviour
-export([start/2, stop/1, config_change/3]).
%% optional callbacks for application behaviour
-export([prep_stop/1, start_phase/3]).
%% export the cse private API for installation
-export([install/0, install/1]).

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
	Tables = [resource_spec, resource, service] ++ HttpdTables,
	case mnesia:wait_for_tables(Tables, ?WAITFORTABLES) of
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
	Options = [set, public, named_table, {write_concurrency, true},
			{keypos, 1}],
	case catch ets:new(session, Options) of
		{'EXIT', Reason} ->
			{error, Reason};
		TID ->
			start8()
	end.
%% @hidden
start8() ->
	case supervisor:start_link({local, cse_sup}, cse_sup, []) of
		{ok, TopSup} ->
			{ok, DiameterServices} = application:get_env(diameter),
			start9(TopSup, DiameterServices);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
start9(TopSup, [{Addr, Port, Options} | T]) ->
	case cse:start_diameter(Addr, Port, Options) of
		{ok, _Sup} ->
			start9(TopSup, T);
		{error, Reason} ->
			{error, Reason}
	end;
start9(TopSup, []) ->
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
	case mnesia:wait_for_tables([schema], ?WAITFORSCHEMA) of
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
			case install_resource_specs() of
				ok ->
					install4(Nodes, [resource_spec | Acc]);
				{error, Reason} ->
					{error, Reason}
			end;
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
	case create_table(service, Nodes) of
		ok ->
			install6(Nodes, [service | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install6(Nodes, Acc) ->
	case application:load(inets) of
		ok ->
			error_logger:info_msg("Loaded inets.~n"),
			install7(Nodes, Acc);
		{error, {already_loaded, inets}} ->
			install7(Nodes, Acc)
	end.
%% @hidden
install7(Nodes, Acc) ->
	case is_mod_auth_mnesia() of
		true ->
			install8(Nodes, Acc);
		false ->
			error_logger:info_msg("Httpd service not defined. "
					"User table not created~n"),
			install10(Nodes, Acc)
	end.
%% @hidden
install8(Nodes, Acc) ->
	case create_table(httpd_user, Nodes) of
		ok ->
			install9(Nodes, [httpd_user | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install9(Nodes, Acc) ->
	case create_table(httpd_group, Nodes) of
		ok ->
			install10(Nodes, [httpd_group | Acc]);
		{error, Reason} ->
			{error, Reason}
	end.
%% @hidden
install10(_Nodes, Tables) ->
	case mnesia:wait_for_tables(Tables, ?WAITFORTABLES) of
		ok ->
			install11(Tables, lists:member(httpd_user, Tables));
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
install11(Tables, true) ->
	case inets:start() of
		ok ->
			error_logger:info_msg("Started inets.~n"),
			install12(Tables);
		{error, {already_started, inets}} ->
			install12(Tables);
		{error, Reason} ->
			error_logger:error_msg("Failed to start inets~n"),
			{error, Reason}
	end;
install11(Tables, false) ->
	{ok, Tables}.
%% @hidden
install12(Tables) ->
	case cse:list_users() of
		{ok, []} ->
			UserData = [{locale, "en"}],
			case cse:add_user("admin", "admin", UserData) of
				{ok, _LastModified} ->
					error_logger:info_report(["Created a default user",
							{username, "admin"}, {password, "admin"},
							{locale, "en"}]),
					{ok, Tables};
				{error, Reason} ->
					error_logger:error_report(["Failed to creat default user",
							{username, "admin"}, {password, "admin"},
							{locale, "en"}]),
					{error, Reason}
			end;
		{ok, Users} ->
			error_logger:info_report(["Found existing http users",
					{users, Users}]),
			{ok, Tables};
		{error, Reason} ->
			error_logger:error_report(["Failed to list http users",
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
	create_table1(resource, mnesia:create_table(resource,
			[{disc_copies, Nodes},
			{attributes, record_info(fields, resource)}]));
create_table(service, Nodes) when is_list(Nodes) ->
	create_table1(service, mnesia:create_table(service,
			[{disc_copies, Nodes},
			{attributes, record_info(fields, service)}]));
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
%% 		cse_rest_res_resource:prefix_row_spec_id()])
%% @private
install_resource_specs() ->
	SpecIds = [cse_rest_res_resource:prefix_table_spec_id(),
			cse_rest_res_resource:prefix_row_spec_id(),
			cse_rest_res_resource:prefix_range_table_spec_id()],
	install_resource_specs(SpecIds).

-spec install_resource_specs(SpecIds) -> Result
	when
		SpecIds :: [string()],
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
			ok
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

