%%% cse.erl
%%% vim: ts=3
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
%%% @doc This library module implements the public API for the
%%%   {@link //cse. cse} application.
%%%
-module(cse).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse  public API
-export([start/0, stop/0]).
-export([add_resource/1]).
-export([add_user/3, list_users/0, get_user/1, delete_user/1,
		query_users/3, update_user/3]).
-export([add_service/3, get_service/1, get_services/0, delete_service/1]).

-export_type([event_type/0, monitor_mode/0]).

-include("cse.hrl").
-include_lib("inets/include/mod_auth.hrl").

-define(PathInventory, "/resourceInventoryManagement/v4/").
-define(CHUNKSIZE, 100).

%%----------------------------------------------------------------------
%%  The cse public API
%%----------------------------------------------------------------------

-spec start() -> Result
	when
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Start the {@link //cse. cse} application.
start() ->
	application:start(cse).

-spec stop() -> Result
	when
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Stop the {@link //cse. cse} application.
stop() ->
	application:stop(cse).

-spec add_user(Username, Password, UserData) -> Result
	when
		Username :: string(),
		Password :: string(),
		UserData :: [UserDataChar],
		UserDataChar :: {Name, Value},
		Name :: atom(),
		Value :: term(),
		Result :: {ok, LastModified} | {error, Reason},
		LastModified :: {integer(), integer()},
		Reason :: user_exists | term().
%% @doc Add an HTTP user.
%% 	HTTP Basic authentication (RFC7617) is required with
%% 	`Username' and `Password' used to construct the
%% 	`Authorization' header in requests.
%%
%%		`UserData' contains addtional properties specific to each user.
%% 	`Locale' is a `UserData' property used to set the language for
%%		text in the web UI.
%% 	For English use `"en"', for Spanish use `"es'"..
%%
add_user(Username, Password, UserData) when is_list(Username),
		is_list(Password), is_list(UserData) ->
	add_user1(Username, Password, UserData, get_params()).
%% @hidden
add_user1(Username, Password, UserData, {Port, Address, Dir, Group}) ->
	add_user2(Username, Password, UserData,
			Address, Port, Dir, Group, cse:get_user(Username));
add_user1(_, _, _, {error, Reason}) ->
	{error, Reason}.
%% @hidden
add_user2(Username, Password, UserData,
		Address, Port, Dir, Group, {error, no_such_user}) ->
	LM = {erlang:system_time(millisecond), erlang:unique_integer([positive])},
	NewUserData = case lists:keyfind(locale, 1, UserData) of
		{locale, Locale} when is_list(Locale) ->
			[{last_modified, LM} | UserData];
		false ->
			[{last_modified, LM}, {locale, "en"} | UserData]
	end,
	add_user3(Username, Address, Port, Dir, Group, LM,
			mod_auth:add_user(Username, Password, NewUserData, Address, Port, Dir));
add_user2(_, _, _, _, _, _, _, {error, Reason}) ->
	{error, Reason};
add_user2(_, _, _, _, _, _, _, {ok, _}) ->
	{error, user_exists}.
%% @hidden
add_user3(Username, Address, Port, Dir, Group, LM, true) ->
	add_user4(LM, mod_auth:add_group_member(Group, Username, Address, Port, Dir));
add_user3(_, _, _, _, _, _, {error, Reason}) ->
	{error, Reason}.
%% @hidden
add_user4(LM, true) ->
	{ok, LM};
add_user4(_, {error, Reason}) ->
	{error, Reason}.

-spec list_users() -> Result
	when
		Result :: {ok, Users} | {error, Reason},
		Users :: [Username],
		Username :: string(),
		Reason :: term().
%% @doc List HTTP users.
%% @equiv  mod_auth:list_users(Address, Port, Dir)
list_users() ->
	list_users1(get_params()).
%% @hidden
list_users1({Port, Address, Dir, _}) ->
	mod_auth:list_users(Address, Port, Dir);
list_users1({error, Reason}) ->
	{error, Reason}.

-spec get_user(Username) -> Result
	when
		Username :: string(),
		Result :: {ok, User} | {error, Reason},
		User :: #httpd_user{},
		Reason :: term().
%% @doc Get an HTTP user record.
%% @equiv mod_auth:get_user(Username, Address, Port, Dir)
get_user(Username) ->
	get_user(Username, get_params()).
%% @hidden
get_user(Username, {Port, Address, Dir, _}) ->
	mod_auth:get_user(Username, Address, Port, Dir);
get_user(_, {error, Reason}) ->
	{error, Reason}.

-spec delete_user(Username) -> Result
	when
		Username :: string(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Delete an existing HTTP user.
delete_user(Username) ->
	delete_user1(Username, get_params()).
%% @hidden
delete_user1(Username, {Port, Address, Dir, GroupName}) ->
	delete_user2(GroupName, Username, Address, Port, Dir,
			mod_auth:delete_user(Username, Address, Port, Dir));
delete_user1(_, {error, Reason}) ->
	{error, Reason}.
%% @hidden
delete_user2(GroupName, Username, Address, Port, Dir, true) ->
	delete_user3(mod_auth:delete_group_member(GroupName,
			Username, Address, Port, Dir));
delete_user2(_, _, _, _, _, {error, Reason}) ->
	{error, Reason}.
%% @hidden
delete_user3(true) ->
	ok;
delete_user3({error, Reason}) ->
	{error, Reason}.

-spec update_user(Username, Password, UserData) -> Result
	when
		Username :: string(),
		Password :: string(),
		UserData :: [UserDataChar],
		UserDataChar :: {Name, Value},
		Name :: atom(),
		Value :: term(),
		Result :: {ok, LM} | {error, Reason},
		LM :: {integer(), integer()},
		Reason :: term().
%% @hidden Update user password and language
update_user(Username, Password, UserData) ->
	case get_user(Username) of
		{error, Reason} ->
			{error, Reason};
		{ok, #httpd_user{}} ->
			case delete_user(Username) of
				ok ->
					case add_user(Username, Password, UserData) of
						{ok, LM} ->
							{ok, LM};
						{error, Reason} ->
							{error, Reason}
					end;
				{error, Reason} ->
					{error, Reason}
			end
	end.

-spec query_users(Cont, MatchId, MatchLocale) -> Result
	when
		Cont :: start | any(),
		MatchId :: Match,
		MatchLocale ::Match,
		Match :: {exact, string()} | {notexact, string()} | {like, string()},
		Result :: {Cont1, [#httpd_user{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query the user table.
query_users(start, '_', MatchLocale) ->
	MatchSpec = [{'_', [], ['$_']}],
	query_users1(MatchSpec, MatchLocale);
query_users(start, {Op, String} = _MatchId, MatchLocale)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchSpec = case lists:last(String) of
		$% when Op == like ->
			Prefix = lists:droplast(String),
			Username = {Prefix ++ '_', '_', '_', '_'},
			MatchHead = #httpd_user{username = Username, _ = '_'},
			[{MatchHead, [], ['$_']}];
		_ ->
			Username = {String, '_', '_', '_'},
			MatchHead = #httpd_user{username = Username, _ = '_'},
			[{MatchHead, [], ['$_']}]
	end,
	query_users1(MatchSpec, MatchLocale);
query_users(start, {notexact, String} = _MatchId, MatchLocale)
		when is_list(String) ->
	Username = {'$1', '_', '_', '_'},
	MatchHead = #httpd_user{username = Username, _ = '_'},
	MatchSpec = [{MatchHead, [{'/=', '$1', String}], ['$_']}],
	query_users1(MatchSpec, MatchLocale);
query_users(Cont, _MatchId, MatchLocale) when is_tuple(Cont) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	case mnesia:ets(F) of
		{Users, Cont1} ->
			query_users2(MatchLocale, Cont1, Users);
		'$end_of_table' ->
			{eof, []}
	end;
query_users(start, MatchId, MatchLocale) when is_tuple(MatchId) ->
	MatchCondition = [match_condition('$1', MatchId)],
	Username = {'$1', '_', '_', '_'},
	MatchHead = #httpd_user{username = Username, _ = '_'},
	MatchSpec = [{MatchHead, MatchCondition, ['$_']}],
	query_users1(MatchSpec, MatchLocale).
%% @hidden
query_users1(MatchSpec, MatchLocale) ->
	F = fun() ->
			mnesia:select(httpd_user, MatchSpec, ?CHUNKSIZE, read)
	end,
	case mnesia:ets(F) of
		{Users, Cont} ->
			query_users2(MatchLocale, Cont, Users);
		'$end_of_table' ->
			{eof, []}
	end.
%% @hidden
query_users2('_' = _MatchLocale, Cont, Users) ->
	{Cont, Users};
query_users2({exact, String} = _MatchLocale, Cont, Users)
		when is_list(String) ->
	F = fun(#httpd_user{user_data = UD}) ->
			case lists:keyfind(locale, 1, UD) of
				{_, String} ->
					true;
				_ ->
					false
			end
	end,
	{Cont, lists:filter(F, Users)};
query_users2({notexact, String} = _MatchLocale, Cont, Users)
		when is_list(String) ->
	F = fun(#httpd_user{user_data = UD}) ->
			case lists:keyfind(locale, 1, UD) of
				{_, String} ->
					false;
				_ ->
					true
			end
	end,
	{Cont, lists:filter(F, Users)};
query_users2({like, String} = _MatchLocale, Cont, Users)
		when is_list(String) ->
	F = case lists:last(String) of
		$% ->
			Prefix = lists:droplast(String),
			fun(#httpd_user{user_data = UD}) ->
					case lists:keyfind(locale, 1, UD) of
						{_, Locale} ->
							lists:prefix(Prefix, Locale);
						_ ->
							false
					end
			end;
		_ ->
			fun(#httpd_user{user_data = UD}) ->
					case lists:keyfind(locale, 1, UD) of
						{_, String} ->
							true;
						_ ->
							false
					end
			end
	end,
	{Cont, lists:filter(F, Users)}.

-spec add_resource(Resource) -> Result
	when
		Result :: {ok, Resource} | {error, Reason},
		Reason :: term().
%% @doc Create a new Resource.
add_resource(#resource{id = undefined, last_modified = undefined, name = Name,
		specification = #specification_ref{id = "1"}} = Resource)
		when is_list(Name) ->
	case mnesia:table_info(list_to_existing_atom(Name), attributes) of
		[num, value] ->
			add_resource1(Resource);
		_ ->
			exit(table_not_found)
	end;
add_resource(#resource{id = undefined, last_modified = undefined,
		specification = #specification_ref{id = SpecId}} = Resource)
		when SpecId /= "1" ->
	add_resource1(Resource).
%% @hidden
add_resource1(#resource{} = Resource) ->
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	Id = integer_to_list(TS) ++ integer_to_list(N),
	LM = {TS, N},
	Href = ?PathInventory ++ "resource/" ++ Id,
	NewResource = Resource#resource{id = Id,
			href = Href, last_modified = LM},
	F = fun() ->
			ok = mnesia:write(NewResource),
			NewResource
	end,
	add_resource2(mnesia:transaction(F)).
%% @hidden
add_resource2({atomic, #resource{} = NewResource}) ->
	{ok, NewResource};
add_resource2({aborted, Reason}) ->
	{error, Reason}.

-type event_type() :: collected_info | analysed_info | route_fail
		| busy | no_answer | answer | mid_call | disconnect1 | disconnect2
		| abandon | term_attempt.
-type monitor_mode() :: interrupted | notifyAndContinue | transparent.
-spec add_service(Key, Module, Edp) -> Result
	when
		Key :: integer(),
		Module :: atom(),
		Edp :: #{event_type() => monitor_mode()},
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @doc Create a new Service.
add_service(Key, Module, Edp) when is_integer(Key), is_atom(Module) ->
	case is_edp(Edp) of
		true ->
			Service = #service{key = Key, module = Module, edp = Edp},
			F = fun() ->
					mnesia:write(Service)
			end,
			add_service(mnesia:transaction(F), Service);
		false ->
			{error, bad_arg}
	end.
%% @hidden
add_service({atomic, ok}, Service) ->
	{ok, Service};
add_service({aborted, Reason}, _S) ->
	{error, Reason}.

-spec get_service(Key) -> Result
	when
		Key :: integer(),
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: not_found | term().
%% @doc Find a service by key.
%%
get_service(Key) when is_integer(Key) ->
	F = fun() ->
			mnesia:read(service, Key)
	end,
	case mnesia:transaction(F) of
		{atomic, [#service{} = Service]} ->
			{ok, Service};
		{atomic, []} ->
			{error, not_found}
	end.

-spec get_services() -> Result
	when
		Result :: Services | {error, Reason},
		Services :: [#service{}],
		Reason :: term().
%% @doc Get the all service records.
get_services() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
		F(mnesia:select(service, MatchSpec,
				?CHUNKSIZE, read), Acc);
		F('$end_of_table', Acc) ->
				{ok, lists:flatten(lists:reverse(Acc))};
		F({error, Reason}, _Acc) ->
				{error, Reason};
		F({Services, Cont}, Acc) ->
				F(mnesia:select(Cont), [Services | Acc])
	end,
	case mnesia:ets(F, [start, []]) of
		{error, Reason} ->
			{error, Reason};
		{ok, Result} ->
			Result
	end.

-spec delete_service(Key) -> ok
	when
		Key :: integer().
%% @doc Delete an entry from the service table.
delete_service(Key) when is_integer(Key) ->
	F = fun() ->
		mnesia:delete(service, Key, write)
	end,
	case mnesia:transaction(F) of
		{atomic, _} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec get_params() -> Result
	when
		Result :: {Port :: integer(), Address :: string(),
				Directory :: string(), Group :: string()}
				| {error, Reason :: term()}.
%% @doc Returns configurations details for currently running
%% {@link //inets. httpd} service.
%% @hidden
get_params() ->
	get_params(inets:services_info()).
%% @hidden
get_params({error, Reason}) ->
	{error, Reason};
get_params(ServicesInfo) ->
	get_params1(lists:keyfind(httpd, 1, ServicesInfo)).
%% @hidden
get_params1({httpd, _, HttpdInfo}) ->
	{_, Address} = lists:keyfind(bind_address, 1, HttpdInfo),
	{_, Port} = lists:keyfind(port, 1, HttpdInfo),
	get_params2(Address, Port, application:get_env(inets, services));
get_params1(false) ->
	{error, httpd_not_started}.
%% @hidden
get_params2(Address, Port, {ok, Services}) ->
	get_params3(Address, Port, lists:keyfind(httpd, 1, Services));
get_params2(_, _, undefined) ->
	{error, inet_services_undefined}.
%% @hidden
get_params3(Address, Port, {httpd, Httpd}) ->
	F = fun({directory, _}) ->
				true;
			(_) ->
				false
	end,
	get_params4(Address, Port, lists:filter(F, Httpd));
get_params3(_, _, false) ->
	{error, httpd_service_undefined}.
%% @hidden
get_params4(Address, Port, [{directory, {_Dir, []}} | T]) ->
	get_params4(Address, Port, T);
get_params4(Address, Port, [{directory, {Directory, Auth}} | _T]) ->
	get_params5(Address, Port, Directory,
			lists:keyfind(require_group, 1, Auth));
get_params4(_, _, []) ->
	{error, httpd_directory_undefined}.
%% @hidden
get_params5(Address, Port, Directory, {require_group, [Group | _]}) ->
	{Port, Address, Directory, Group};
get_params5(_, _, _, false) ->
	{error, httpd_group_undefined}.

-spec match_condition(MatchVariable, Match) -> MatchCondition
	when
		MatchVariable :: atom(), % '$<number>'
		Match :: {exact, term()} | {notexact, term()} | {lt, term()}
				| {lte, term()} | {gt, term()} | {gte, term()},
		MatchCondition :: {GuardFunction, MatchVariable, Term},
		Term :: any(),
		GuardFunction :: '=:=' | '=/=' | '<' | '=<' | '>' | '>='.
%% @doc Convert REST query patterns to Erlang match specification conditions.
%% @hidden
match_condition(Var, {exact, Term}) ->
	{'=:=', Var, Term};
match_condition(Var, {notexact, Term}) ->
	{'=/=', Var, Term};
match_condition(Var, {lt, Term}) ->
	{'<', Var, Term};
match_condition(Var, {lte, Term}) ->
	{'=<', Var, Term};
match_condition(Var, {gt, Term}) ->
	{'>', Var, Term};
match_condition(Var, {gte, Term}) ->
	{'>=', Var, Term}.

-spec is_edp(Edp) -> boolean()
	when
		Edp :: #{event_type() => monitor_mode()}.
%% @doc Checks whether `Edp' is correct.
%% @hidden
is_edp(Edp) when is_map(Edp) ->
	EventTypes = [collected_info, analysed_info, route_fail, busy, no_answer,
			answer, mid_call, disconnect1, disconnect2, abandon, term_attempt],
	F = fun(E) ->
		lists:member(E, EventTypes)
	end,
	is_edp(lists:all(F, maps:keys(Edp)), Edp).
%% @hidden
is_edp(true, Edp) ->
	MonitorModes = [interrupted, notifyAndContinue, transparent],
	F = fun(E) ->
		lists:member(E, MonitorModes)
	end,
	is_edp1(lists:all(F, maps:values(Edp)));
is_edp(false, _Edp) ->
	false.
%% @hidden
is_edp1(true) ->
	true;
is_edp1(false) ->
	false.
