%%% cse.erl
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
%%% @doc This library module implements the public API for the
%%%   {@link //cse. cse} application.
%%%
-module(cse).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse  public API
-export([start/0, stop/0]).
-export([start_diameter/3]).
-export([add_resource_spec/1, get_resource_specs/0, find_resource_spec/1,
		delete_resource_spec/1, query_resource_spec/5]).
-export([add_resource/1, get_resources/0, find_resource/1, delete_resource/1,
		query_resource/5]).
-export([add_user/3, list_users/0, get_user/1, delete_user/1,
		query_users/3, update_user/3]).
-export([add_service/3, find_service/1, get_services/0, delete_service/1]).
-export([announce/1]).
-export([add_session/2, get_session/1, get_sessions/0, delete_session/1]).

-export_type([event_type/0, monitor_mode/0]).
-export_type([word/0]).

-include("cse.hrl").
-include_lib("inets/include/mod_auth.hrl").

-define(PathCatalog, "/resourceCatalogManagement/v4/").
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

-spec start_diameter(Address, Port, Options) -> Result
	when
		Address :: inet:ip_address(),
		Port :: pos_integer(),
		Options :: [Option],
		Option :: diameter:service_opt(),
		Result :: Result :: {ok, Pid} | {error, Reason},
		Pid :: pid(),
		Reason :: term().
%% @doc Start a DIAMETER request handler.
start_diameter(Address, Port, Options) ->
	gen_server:call(cse, {start, diameter, Address, Port, Options}).

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

-spec add_resource_spec(Specification) -> Result
	when
		Specification :: #resource_spec{},
		Result :: {ok, Specification} | {error, Reason},
		Reason :: term().
%% @doc Add an entry in the Resource Specification table.
add_resource_spec(#resource_spec{name = Name, id = undefined,
		href = undefined, last_modified = undefined, related = Rels}
		= ResourceSpecification) when is_list(Name) ->
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	Id = integer_to_list(TS) ++ "-" ++ integer_to_list(N),
	LM = {TS, N},
	Href = ?PathCatalog ++ "resourceSpecification/" ++ Id,
	NewSpec = case lists:keytake("based", #resource_spec_rel.rel_type, Rels) of
		{value, BasedRel, Rest} ->
			ResourceSpecification#resource_spec{id = Id,
					href = Href, last_modified = LM, related = [BasedRel | Rest]};
		false ->
			ResourceSpecification#resource_spec{id = Id,
					href = Href, last_modified = LM}
	end,
	F = fun() ->
			mnesia:write(NewSpec)
	end,
	add_resource_spec1(mnesia:transaction(F), NewSpec).
%% @hidden
add_resource_spec1({atomic, ok}, #resource_spec{} = NewSpecification) ->
	{ok, NewSpecification};
add_resource_spec1({aborted, Reason}, _NewSpecification) ->
	{error, Reason}.

-spec add_resource(Resource) -> Result
	when
		Resource :: #resource{},
		Result :: {ok, Resource} | {error, Reason},
		Reason :: term().
%% @doc Add an entry in the Resource table.
add_resource(#resource{id = undefined,
		name = Name, last_modified = undefined,
		specification = #resource_spec_ref{id = SpecId}} = Resource)
		when is_list(Name) ->
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	case SpecId of
		TableSpecId ->
			add_resource1(Resource);
		Other ->
			case cse:find_resource_spec(Other) of
				{ok, #resource_spec{related = Related}} ->
					case lists:keyfind(TableSpecId, #resource_spec_rel.id, Related) of
						#resource_spec_rel{rel_type = "based"} ->
							add_resource1(Resource);
						_ ->
							add_resource2(Resource)
					end;
				{error, Reason} ->
					{error, Reason}
			end
	end.
%% @hidden
add_resource1(#resource{name = Name} = Resource) ->
	case mnesia:table_info(list_to_existing_atom(Name), attributes) of
		[num, value] ->
			add_resource2(Resource);
		_ ->
			{error, table_not_found}
	end.
%% @hidden
add_resource2(#resource{} = Resource) ->
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	Id = integer_to_list(TS) ++ integer_to_list(N),
	LM = {TS, N},
	Href = ?PathInventory ++ "resource/" ++ Id,
	NewResource = Resource#resource{id = Id,
			href = Href, last_modified = LM},
	F = fun() ->
			mnesia:write(NewResource)
	end,
	add_resource3(mnesia:transaction(F), NewResource).
%% @hidden
add_resource3({atomic, ok}, #resource{} = NewResource) ->
	{ok, NewResource};
add_resource3({aborted, Reason}, _NewResource) ->
	{error, Reason}.

-spec get_resource_specs() -> Result
	when
		Result :: [#resource_spec{}] | {error, Reason},
		Reason :: term().
%% @doc List all entries in the Resource Specification table.
get_resource_specs() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
				F(mnesia:select(resource_spec, MatchSpec, 100, read), Acc);
			F('$end_of_table', Acc) ->
				Acc;
			F({error, Reason}, _Acc) ->
				{error, Reason};
			F({L, Cont}, Acc) ->
				F(mnesia:select(Cont), [L | Acc])
	end,
	case catch mnesia:ets(F, [start, []]) of
		[] ->
			{error, not_found};
		Acc when is_list(Acc) ->
			lists:flatten(lists:reverse(Acc));
		{'EXIT', Reason} ->
			{error, Reason}
	end.

-spec get_resources() -> Result
	when
		Result :: {ok, [#resource{}]} | {error, Reason},
		Reason :: term().
%% @doc List all entries in the Resource table.
get_resources() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
				F(mnesia:select(resource, MatchSpec, ?CHUNKSIZE, read), Acc);
			F('$end_of_table', Acc) ->
				Acc;
			F({error, Reason}, _Acc) ->
				{error, Reason};
			F({L, Cont}, Acc) ->
				F(mnesia:select(Cont), [L | Acc])
	end,
	case mnesia:ets(F, [F, start, []]) of
		{ok, Acc} when is_list(Acc) ->
			{ok, lists:flatten(lists:reverse(Acc))};
		{error, Reason} ->
			{error, Reason}
	end.

-spec find_resource_spec(ID) -> Result
	when
		ID :: string(),
		Result :: {ok, ResourceSpecification} | {error, Reason},
		ResourceSpecification :: #resource_spec{},
		Reason :: not_found | term().
%% @doc Get a Resource Specification by identifier.
find_resource_spec(ID) when is_list(ID) ->
	F = fun() ->
			mnesia:read(resource_spec, ID, read)
	end,
	case mnesia:transaction(F) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, [Resource]} ->
			{ok, Resource};
		{atomic, []} ->
			{error, not_found}
	end.

-spec find_resource(ID) -> Result
	when
		ID :: string(),
		Result :: {ok, Resource} | {error, Reason},
		Resource :: #resource{},
		Reason :: not_found | term().
%% @doc Get a Resource by identifier.
find_resource(ID) when is_list(ID) ->
	F = fun() ->
			mnesia:read(resource, ID, read)
	end,
	case mnesia:transaction(F) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, [Resource]} ->
			{ok, Resource};
		{atomic, []} ->
			{error, not_found}
	end.

-spec delete_resource_spec(ID) -> Result
	when
		ID :: string(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Delete an entry from the Resource Specification table.
delete_resource_spec(ID) when is_list(ID) ->
	F = fun() ->
			case mnesia:read(resource_spec, ID, write) of
				[#resource_spec{id = ID}] ->
					mnesia:delete(resource_spec, ID, write);
				[] ->
					mnesia:abort(not_found)
			end
	end,
	case mnesia:transaction(F) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, ok} ->
			ok
	end.

-spec delete_resource(ID) -> Result
	when
		ID :: string(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Delete an entry from the Resource table.
delete_resource(ID) when is_list(ID) ->
	F = fun() ->
			case mnesia:read(resource, ID, write) of
				[#resource{id = ID} = Resource] ->
					{mnesia:delete(resource, ID, write), Resource};
				[] ->
					mnesia:abort(not_found)
			end
	end,
	TableSpecId = cse_rest_res_resource:prefix_table_spec_id(),
	case mnesia:transaction(F) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, {ok, #resource{name = Name,
				specification = #resource_spec_ref{id = TableSpecId}}}} ->
			cse_gtt:clear_table(Name);
		{atomic, {ok, _R}} ->
			ok
	end.

-spec query_resource_spec(Cont, MatchId,
		MatchName, MatchRelId, MatchRelType) -> Result
	when
		Cont :: start | any(),
		MatchId :: Match,
		MatchName :: Match,
		MatchRelId :: Match,
		MatchRelType :: Match,
		Match :: {exact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#resource_spec{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query the Resource Specification table.
query_resource_spec(Cont, '_', MatchName, MatchRelId, MatchRelType) ->
	MatchHead = #resource_spec{_ = '_'},
	query_resource_spec1(Cont, MatchHead, MatchName, MatchRelId, MatchRelType);
query_resource_spec(Cont, {Op, String}, MatchName, MatchRelId, MatchRelType)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead = case lists:last(String) of
		$% when Op == like ->
			#resource_spec{id = lists:droplast(String) ++ '_', _ = '_'};
		_ ->
			#resource_spec{id = String, _ = '_'}
	end,
	query_resource_spec1(Cont, MatchHead, MatchName, MatchRelId, MatchRelType).
%% @hidden
query_resource_spec1(Cont, MatchHead, '_', MatchRelId, MatchRelType) ->
	query_resource_spec2(Cont, MatchHead, MatchRelId, MatchRelType);
query_resource_spec1(Cont, MatchHead1, {Op, String}, MatchRelId, MatchRelType)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead2 = case lists:last(String) of
		$% when Op == like ->
			MatchHead1#resource_spec{name = lists:droplast(String) ++ '_'};
		_ ->
			MatchHead1#resource_spec{name = String}
	end,
	query_resource_spec2(Cont, MatchHead2, MatchRelId, MatchRelType).
%% @hidden
query_resource_spec2(Cont, MatchHead, '_', MatchRelType) ->
	query_resource_spec3(Cont, MatchHead, MatchRelType);
query_resource_spec2(Cont, MatchHead1, {Op, String}, MatchRelType)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead2 = case lists:last(String) of
		$% when Op == like ->
			MatchHead1#resource_spec{related = [#resource_spec_rel{id
					= lists:droplast(String) ++ '_', _ = '_'} | _ = '_']};
		_ ->
			MatchHead1#resource_spec{related
					= [#resource_spec_rel{id = String, _ = '_'} | _ = '_']}
	end,
	query_resource_spec3(Cont, MatchHead2, MatchRelType).
%% @hidden
query_resource_spec3(Cont, MatchHead, '_') ->
	MatchSpec = [{MatchHead, [], ['$_']}],
	query_resource_spec4(Cont, MatchSpec);
query_resource_spec3(Cont, MatchHead1, {Op, String})
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead2 = case lists:last(String) of
		$% when Op == like ->
			MatchHead1#resource_spec{related = [#resource_spec_rel{rel_type
					= lists:droplast(String) ++ '_', _ = '_'} | _ = '_']};
		_ ->
			MatchHead1#resource_spec{related
					= [#resource_spec_rel{rel_type = String, _ = '_'} | _ = '_']}
	end,
	MatchSpec = [{MatchHead2, [], ['$_']}],
	query_resource_spec4(Cont, MatchSpec).
%% @hidden
query_resource_spec4(start, MatchSpec) ->
	F = fun() ->
			mnesia:select(resource_spec, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_resource_spec5(mnesia:ets(F));
query_resource_spec4(Cont, _MatchSpec) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	query_resource_spec5(mnesia:ets(F)).
%% @hidden
query_resource_spec5({Resources, Cont}) ->
	{Cont, Resources};
query_resource_spec5('$end_of_table') ->
	{eof, []}.

-spec query_resource(Cont, MatchId, MatchName,
		MatchResSpecId, MatchRelName) -> Result
	when
		Cont :: start | any(),
		MatchId :: Match,
		MatchName :: Match,
		MatchResSpecId :: Match,
		MatchRelName :: Match,
		Match :: {exact, string()} | {like, string()} | '_',
		Result :: {Cont1, [#resource{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query the Resource table.
query_resource(Cont, '_', MatchName, MatchResSpecId, MatchRelName) ->
	MatchHead = #resource{_ = '_'},
	query_resource1(Cont, MatchHead, MatchName,
			MatchResSpecId, MatchRelName);
query_resource(Cont, {Op, String}, MatchName, MatchResSpecId, MatchRelName)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead = case lists:last(String) of
		$% when Op == like ->
			#resource{id = lists:droplast(String) ++ '_', _ = '_'};
		_ ->
			#resource{id = String, _ = '_'}
	end,
	query_resource1(Cont, MatchHead, MatchName,
			MatchResSpecId, MatchRelName).
%% @hidden
query_resource1(Cont, MatchHead, '_', MatchResSpecId, MatchRelName) ->
	query_resource2(Cont, MatchHead, MatchResSpecId, MatchRelName);
query_resource1(Cont, MatchHead1, {Op, String}, MatchResSpecId, MatchRelName)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead2 = case lists:last(String) of
		$% when Op == like ->
			MatchHead1#resource{name = lists:droplast(String) ++ '_'};
		_ ->
			MatchHead1#resource{name = String}
	end,
	query_resource2(Cont, MatchHead2, MatchResSpecId, MatchRelName).
%% @hidden
query_resource2(Cont, MatchHead, '_', MatchRelName) ->
	query_resource3(Cont, MatchHead, MatchRelName);
query_resource2(Cont, MatchHead1, {Op, String}, MatchRelName)
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead2 = case lists:last(String) of
		$% when Op == like ->
			MatchHead1#resource{specification = #resource_spec_ref{id
					= lists:droplast(String) ++ '_', _ = '_'}};
		_ ->
			MatchHead1#resource{specification
					= #resource_spec_ref{id = String, _ = '_'}}
	end,
	query_resource3(Cont, MatchHead2, MatchRelName).
%% @hidden
query_resource3(Cont, MatchHead, '_') ->
	MatchSpec = [{MatchHead, [], ['$_']}],
	query_resource4(Cont, MatchSpec);
query_resource3(Cont, MatchHead1, {Op, String})
		when is_list(String), ((Op == exact) orelse (Op == like)) ->
	MatchHead2 = case lists:last(String) of
		$% when Op == like ->
			MatchHead1#resource{related = [#resource_rel{name
					= lists:droplast(String) ++ '_', _ = '_'}]};
		_ ->
			MatchHead1#resource{related
					= [#resource_rel{name = String, _ = '_'}]}
	end,
	MatchSpec = [{MatchHead2, [], ['$_']}],
	query_resource4(Cont, MatchSpec).
%% @hidden
query_resource4(start, MatchSpec) ->
	F = fun() ->
			mnesia:select(resource, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_resource5(mnesia:ets(F));
query_resource4(Cont, _MatchSpec) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	query_resource5(mnesia:ets(F)).
%% @hidden
query_resource5({Resources, Cont}) ->
	{Cont, Resources};
query_resource5('$end_of_table') ->
	{eof, []}.

-type event_type() :: collected_info | analysed_info | route_fail
		| busy | no_answer | answer | mid_call | disconnect1 | disconnect2
		| abandon | term_attempt.
-type monitor_mode() :: interrupted | notifyAndContinue | transparent.

-spec add_service(Key, Module, EDP) -> Result
	when
		Key :: 0..2147483647,
		Module :: atom(),
		EDP :: #{event_type() => monitor_mode()},
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: term().
%% @doc Add a Service Logic Processing Program (SLP).
%%
%% 	The `serviceKey' of an `InitialDP' identifies the IN service
%% 	logic which should be provided for the call.  An SLP is
%%		implemented in a `Module'. Event Detection Points (`EDP')
%% 	required by the SLP are provided to control the `SSF'.
%%
add_service(Key, Module, EDP) when is_integer(Key),
		is_atom(Module), is_map(EDP)  ->
	case is_edp(EDP) of
		true ->
			Service = #service{key = Key, module = Module, edp = EDP},
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

-spec find_service(Key) -> Result
	when
		Key :: 0..2147483647,
		Result :: {ok, #service{}} | {error, Reason},
		Reason :: not_found | term().
%% @doc Find a service by key.
%%
find_service(Key) when is_integer(Key) ->
	F = fun() ->
			mnesia:read(service, Key)
	end,
	case mnesia:transaction(F) of
		{atomic, [#service{} = Service]} ->
			{ok, Service};
		{atomic, []} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_services() -> Services
	when
		Services :: [#service{}].
%% @doc Get all service records.
get_services() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
				F(mnesia:select(service, MatchSpec, ?CHUNKSIZE, read), Acc);
			F('$end_of_table', Acc) ->
				{ok, Acc};
			F({error, Reason}, _Acc) ->
				{error, Reason};
			F({L, Cont}, Acc) ->
				F(mnesia:select(Cont), [L| Acc])
	end,
	case mnesia:ets(F, [start, []]) of
		{ok, Acc} when is_list(Acc) ->
			lists:flatten(lists:reverse(Acc));
		{error, Reason} ->
			exit(Reason)
	end.

-spec delete_service(Key) -> ok
	when
		Key :: 0..2147483647.
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

-type word() :: zero |one | two | three | four | five | six
				| seven | eight | nine | ten | eleven | twelve
				| thirteen | fourteen | fifteen | sixteen
				| seventeen | eighteen | nineteen | twenty
				| thirty | forty | fifty | sixty | seventy
				| eighty | ninety | hundred | thousand
				| million | billion | trillion | dollar | dollars
				| cent | cents | 'and' | negative.

-spec announce(Amount) -> Result
	when
		Amount :: integer(),
		Result :: [Word],
		Word :: word().
%% @doc Convert a monetary amount to an announcement list.
%%
%% 	Given an `Amount', in cents, returns a list of words
%% 	which "spell out" the monetary amount. It is expected
%% 	that the caller will map the result `Word's to specific
%% 	announcement file identifiers for use in an IN
%% 	`PlayAnnouncement' operation or DIAMETER
%% 	`Announcement-Information' AVP.
%%
announce(Amount) when is_integer(Amount), Amount < 0  ->
	announce(-Amount, [negative]);
announce(0) ->
	[zero];
announce(Amount) when is_integer(Amount), Amount > 0 ->
	announce(Amount, []).
%% @hidden
announce(Amount, Acc) when Amount > 99 ->
	NewAcc = case announce1(Amount div 100, []) of
		[one]  ->
			Acc ++ [one, dollar];
		Dollars ->
			Acc ++ Dollars ++ [dollars]
	end,
	case Amount rem 100 of
		0 ->
			NewAcc;
		Cents ->
			announce(Cents, NewAcc ++ ['and'])
	end;
announce(Amount, Acc) when Amount < 100 ->
	case announce1(Amount, []) of
		[one]  ->
			Acc ++ [one, cent];
		Cents ->
			Acc ++ Cents ++ [cents]
	end.
%% @hidden
announce1(Amount, Acc)
		when Amount > 999999999999, Amount < 1000000000000000 ->
	Trillions = announce1(Amount div 1000000000000, []),
	NewAcc = Acc ++ Trillions ++ [trillion],
	announce1(Amount rem 1000000000000, NewAcc);
announce1(Amount, Acc)
		when Amount > 999999999, Amount < 1000000000000 ->
	Billions = announce1(Amount div 1000000000, []),
	NewAcc = Acc ++ Billions ++ [billion],
	announce1(Amount rem 1000000000, NewAcc);
announce1(Amount, Acc)
		when Amount > 999999, Amount < 1000000000 ->
	Millions = announce1(Amount div 1000000, []),
	NewAcc = Acc ++ Millions ++ [million],
	announce1(Amount rem 1000000, NewAcc);
announce1(Amount, Acc)
		when Amount > 999, Amount < 1000000 ->
	Thousands = announce1(Amount div 1000, []),
	NewAcc = Acc ++ Thousands ++ [thousand],
	announce1(Amount rem 1000, NewAcc);
announce1(Amount, Acc)
		when Amount > 99, Amount < 1000 ->
	Hundreds = announce1(Amount div 100, []),
	NewAcc = Acc ++ Hundreds ++ [hundred],
	announce1(Amount rem 100, NewAcc);
announce1(Amount, Acc)
		when Amount > 89, Amount < 100 ->
	announce1(Amount - 90, Acc ++ [ninety]);
announce1(Amount, Acc)
		when Amount > 79, Amount < 90 ->
	announce1(Amount - 80, Acc ++ [eighty]);
announce1(Amount, Acc)
		when Amount > 69, Amount < 80 ->
	announce1(Amount - 70, Acc ++ [seventy]);
announce1(Amount, Acc)
		when Amount > 59, Amount < 70 ->
	announce1(Amount - 60, Acc ++ [sixty]);
announce1(Amount, Acc)
		when Amount > 49, Amount < 60 ->
	announce1(Amount - 50, Acc ++ [fifty]);
announce1(Amount, Acc)
		when Amount > 39, Amount < 50 ->
	announce1(Amount - 40, Acc ++ [forty]);
announce1(Amount, Acc)
		when Amount > 29, Amount < 40 ->
	announce1(Amount - 30, Acc ++ [thirty]);
announce1(Amount, Acc)
		when Amount > 19, Amount < 30 ->
	announce1(Amount - 20, Acc ++ [twenty]);
announce1(19, Acc) ->
	Acc ++ [nineteen];
announce1(18, Acc) ->
	Acc ++ [eighteen];
announce1(17, Acc) ->
	Acc ++ [seventeen];
announce1(16, Acc) ->
	Acc ++ [sixteen];
announce1(15, Acc) ->
	Acc ++ [fifteen];
announce1(14, Acc) ->
	Acc ++ [fourteen];
announce1(13, Acc) ->
	Acc ++ [thirteen];
announce1(12, Acc) ->
	Acc ++ [twelve];
announce1(11, Acc) ->
	Acc ++ [eleven];
announce1(10, Acc) ->
	Acc ++ [ten];
announce1(9, Acc) ->
	Acc ++ [nine];
announce1(8, Acc) ->
	Acc ++ [eight];
announce1(7, Acc) ->
	Acc ++ [seven];
announce1(6, Acc) ->
	Acc ++ [six];
announce1(5, Acc) ->
	Acc ++ [five];
announce1(4, Acc) ->
	Acc ++ [four];
announce1(3, Acc) ->
	Acc ++ [three];
announce1(2, Acc) ->
	Acc ++ [two];
announce1(1, Acc) ->
	Acc ++ [one];
announce1(0, Acc) ->
	Acc.

-spec add_session(SessionId, PID) -> Result
	when
		SessionId :: binary(),
		PID :: pid(),
		Result :: {ok, {SessionId, PID}} | {error, Reason},
		Reason :: term().
%% @doc Add a Session Table Entry
%%
%% 	The `SessionId' identifies a Diameter session.
%% 	The `PID' identifies a SLIP process.
%%
add_session(SessionId, PID) when is_binary(SessionId),
		is_pid(PID) ->
	Service = {SessionId, PID},
	case catch ets:insert(session, Service) of
		true ->
			{ok, Service};
		{'EXIT', Reason} ->
			{error, Reason}
	end.

-spec get_session(SessionId) -> Result
	when
		SessionId :: binary(),
		Result :: {ok, {SessionId, PID}} | {error, Reason},
		PID :: pid(),
		Reason :: not_found | term().
%% @doc Get a Session by SessionId.
get_session(SessionId) when is_binary(SessionId) ->
	case catch ets:lookup(session, SessionId) of
		[] ->
			{error, not_found};
		{'EXIT', Reason} ->
			{error, Reason};
		[{SessionId, PID}] ->
			{ok, {SessionId, PID}}
	end.

-spec get_sessions() -> Result
	when
		Result :: Sessions | {error, Reason},
		Sessions :: [Session],
		Session :: {SessionId, PID},
		SessionId :: binary(),
		PID :: pid(),
		Reason :: term().
%% @doc Get all entries from the Session table.
get_sessions() ->
	case catch ets:tab2list(session) of
		Sessions when length(Sessions) > 0 ->
			Sessions;
		{'EXIT', Reason} ->
			{error, Reason}
	end.

-spec delete_session(SessionId) -> ok
	when
		SessionId :: binary().
%% @doc Delete an entry from the session table.
delete_session(SessionId) when is_binary(SessionId) ->
	case catch ets:delete(session, SessionId) of
		true ->
			ok;
		{'EXIT', Reason} ->
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

-spec is_edp(EDP) -> boolean()
	when
		EDP :: #{event_type() => monitor_mode()}.
%% @doc Checks whether `EDP' is correct.
%% @hidden
is_edp(EDP) when is_map(EDP) ->
	EventTypes = [collected_info, analysed_info, route_fail, busy, no_answer,
			answer, mid_call, disconnect1, disconnect2, abandon, term_attempt],
	F = fun(E) ->
		lists:member(E, EventTypes)
	end,
	is_edp(lists:all(F, maps:keys(EDP)), EDP).
%% @hidden
is_edp(true, EDP) ->
	MonitorModes = [interrupted, notifyAndContinue, transparent],
	F = fun(E) ->
		lists:member(E, MonitorModes)
	end,
	is_edp1(lists:all(F, maps:values(EDP)));
is_edp(false, _EDP) ->
	false.
%% @hidden
is_edp1(true) ->
	true;
is_edp1(false) ->
	false.
