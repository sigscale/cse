%%% cse.erl
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
%%% @doc This library module implements the public API for the
%%%   {@link //cse. cse} application.
%%%
-module(cse).
-copyright('Copyright (c) 2021-2023 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse  public API
-export([start/0, stop/0]).
-export([start_diameter/3, stop_diameter/1]).
-export([add_resource_spec/1, get_resource_specs/0, find_resource_spec/1,
		delete_resource_spec/1, query_resource_spec/4]).
-export([add_resource/1, delete_resource/1,
		get_resources/0, find_resource/1, query_resource/6]).
-export([add_user/3, delete_user/1,
		get_user/1, query_users/3, update_user/3, list_users/0]).
-export([add_service/3, delete_service/1,
		get_service/1, find_service/1, get_services/0]).
-export([add_context/4, delete_context/1,
		get_context/1, find_context/1, get_contexts/0]).
-export([add_session/2, delete_session/1,
		get_session/1, find_session/1, get_sessions/0]).
-export([announce/1]).
-export([statistics/1]).

-export_type([characteristics/0, related_resources/0, resource_spec/0,
		resource_spec_rel/0, resource/0, resource_ref/0, resource_rel/0,
		resource_spec_ref/0, resource_spec_char/0, resource_spec_char_rel/0,
		resource_spec_char_val/0, char_rel/0, characteristic/0,
		target_res_schema/0, party_rel/0, in_service/0, diameter_context/0]).

-export_type([event_type/0, monitor_mode/0]).
-export_type([word/0]).

-include("cse.hrl").
-include_lib("inets/include/mod_auth.hrl").

-define(PathCatalog,       <<"/resourceCatalogManagement/v4/">>).
-define(PathInventory,     <<"/resourceInventoryManagement/v4/">>).
-define(INDEX_TABLE_SPEC,  <<"1662614478074-19">>).
-define(INDEX_ROW_SPEC,    <<"1662614480005-35">>).
-define(PREFIX_TABLE_SPEC, <<"1647577955926-50">>).
-define(PREFIX_ROW_SPEC,   <<"1647577957914-66">>).
-define(RANGE_TABLE_SPEC,  <<"1651055414682-258">>).
-define(RANGE_ROW_SPEC,    <<"1651057291061-274">>).
-define(CHUNKSIZE,         100).

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 23).
		-define(binary_to_existing_atom(Name),
				binary_to_existing_atom(Name)).
	-else.
		-define(binary_to_existing_atom(Name),
				list_to_existing_atom(binary_to_list(Name))).
	-endif.
-else.
	-define(binary_to_existing_atom(Name),
			list_to_existing_atom(binary_to_list(Name))).
-endif.

-type characteristics() :: #{CharName :: binary() => characteristic()}.
-type related_resources() :: #{RelType :: binary() => resource_rel()}.
-type resource_spec() :: #resource_spec{}.
-type resource_spec_rel() :: #resource_spec_rel{}.
-type resource() :: #resource{}.
-type resource_ref() :: #resource_ref{}.
-type resource_rel() :: #resource_rel{}.
-type resource_spec_ref() :: #resource_spec_ref{}.
-type resource_spec_char() :: #resource_spec_char{}.
-type resource_spec_char_rel() :: #resource_spec_char_rel{}.
-type resource_spec_char_val() :: #resource_spec_char_val{}.
-type char_rel() :: #char_rel{}.
-type characteristic() :: #characteristic{}.
-type target_res_schema() :: #target_res_schema{}.
-type party_rel() :: #party_rel{}.
-type in_service() :: #in_service{}.
-type diameter_context() :: #diameter_context{}.

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
		Option :: diameter:service_opt()
				| {listen, TransportOpts}
				| {connect, TransportOpts},
		TransportOpts :: diameter:transport_opt(),
		Result :: Result :: {ok, Pid} | {error, Reason},
		Pid :: pid(),
		Reason :: term().
%% @doc Start a DIAMETER request handler.
start_diameter(Address, Port, Options) ->
	gen_server:call(cse, {start, diameter, Address, Port, Options}).

-spec stop_diameter(Pid) -> Result
	when
		Pid :: pid(),
		Result :: Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Stop a DIAMETER request handler.
stop_diameter(Pid) when is_pid(Pid) ->
	gen_server:call(cse, {stop, diameter, Pid}).

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
		Reason :: table_exists | term().
%% @doc Add an entry in the Resource Specification table.
add_resource_spec(#resource_spec{name = Name, id = undefined,
		href = undefined, last_modified = undefined, related = Rels}
		= ResourceSpec1) when is_binary(Name) ->
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	Id = integer_to_list(TS) ++ "-" ++ integer_to_list(N),
	LM = {TS, N},
	Href = iolist_to_binary([?PathCatalog, "resourceSpecification/", Id]),
	case lists:keyfind(<<"based">>, #resource_spec_rel.rel_type, Rels) of
		#resource_spec_rel{id = SpecId} when
				SpecId == ?INDEX_TABLE_SPEC;
				SpecId == ?PREFIX_TABLE_SPEC;
				SpecId == ?RANGE_TABLE_SPEC ->
			ResourceSpec2 = ResourceSpec1#resource_spec{id = list_to_binary(Id),
					href = Href, last_modified = LM},
			add_resource_spec1(ResourceSpec2, Name,
					cse:query_resource_spec(start, {exact, Name}, '_', '_'));
		_Other ->
			ResourceSpec2 = ResourceSpec1#resource_spec{id = list_to_binary(Id),
					href = Href, last_modified = LM},
			add_resource_spec2(ResourceSpec2)
	end.
%% @hidden
add_resource_spec1(ResourceSpec, _Name, {eof, []}) ->
	add_resource_spec2(ResourceSpec);
add_resource_spec1(ResourceSpec, Name, {Cont, []}) ->
	add_resource_spec1(ResourceSpec, Name,
			cse:query_resource_spec(Cont, {exact, Name}, '_', '_'));
add_resource_spec1(_ResourceSpec, _Name, {_Cont_, [_H | _T]}) ->
	{error, table_exists};
add_resource_spec1(_ResourceSpec, _Name, {error, Reason}) ->
	{error, Reason}.
%% @hidden
add_resource_spec2(ResourceSpec) ->
	F = fun() ->
			mnesia:write(ResourceSpec)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			{ok, ResourceSpec};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec add_resource(Resource) -> Result
	when
		Resource :: #resource{},
		Result :: {ok, Resource} | {error, Reason},
		Reason :: spec_not_found | table_not_found
				| name_in_use | missing_chars
				| already_exists | term().
%% @doc Add an entry in the Resource table.
add_resource(#resource{id = undefined,
		name = Name, last_modified = undefined} = Resource)
		when is_binary(Name) ->
	TS = erlang:system_time(millisecond),
	N = erlang:unique_integer([positive]),
	Id = integer_to_list(TS) ++ "-" ++ integer_to_list(N),
	LM = {TS, N},
	Href = iolist_to_binary([?PathInventory, "resource/", Id]),
	NewResource = Resource#resource{id = list_to_binary(Id),
			href = Href, last_modified = LM},
	add_resource1(NewResource).
%% @hidden
add_resource1(#resource{specification = #resource_spec_ref{
		id = ?INDEX_TABLE_SPEC}} = Resource) ->
	add_resource_index_table(Resource);
add_resource1(#resource{specification = #resource_spec_ref{
		id = ?PREFIX_TABLE_SPEC}} = Resource) ->
	add_resource_prefix_table(Resource);
add_resource1(#resource{specification = #resource_spec_ref{
		id = ?RANGE_TABLE_SPEC}} = Resource) ->
	add_resource_prefix_table(Resource);
add_resource1(#resource{specification = #resource_spec_ref{
		id = ?INDEX_ROW_SPEC}} = Resource) ->
	add_resource_index_row(Resource);
add_resource1(#resource{specification = #resource_spec_ref{
		id = ?PREFIX_ROW_SPEC}} = Resource) ->
	add_resource_prefix_row(Resource);
add_resource1(#resource{specification = #resource_spec_ref{
		id = ?RANGE_ROW_SPEC}} = Resource) ->
	add_resource_range_row(Resource);
add_resource1(#resource{specification = #resource_spec_ref{
		id = Other}} = Resource) ->
	add_resource3(Resource, cse:find_resource_spec(Other)).
%% @hidden
add_resource3(Resource, {ok, #resource_spec{related = Related}}) ->
	add_resource4(Resource, Related);
add_resource3(_Resource, {error, not_found}) ->
	{error, spec_not_found};
add_resource3(_Resource, {error, Reason}) ->
	{error, Reason}.
%% @hidden
add_resource4(Resource, Related) ->
	case lists:keyfind(?INDEX_TABLE_SPEC, #resource_spec_rel.id, Related) of
		#resource_spec_rel{rel_type = <<"based">>} ->
			add_resource_index_table(Resource);
		_ ->
			add_resource5(Resource, Related)
	end.
%% @hidden
add_resource5(Resource, Related) ->
	case lists:keyfind(?PREFIX_TABLE_SPEC, #resource_spec_rel.id, Related) of
		#resource_spec_rel{rel_type = <<"based">>} ->
			add_resource_prefix_table(Resource);
		_ ->
			add_resource6(Resource, Related)
	end.
%% @hidden
add_resource6(Resource, Related) ->
	case lists:keyfind(?RANGE_TABLE_SPEC, #resource_spec_rel.id, Related) of
		#resource_spec_rel{rel_type = <<"based">>} ->
			add_resource_prefix_table(Resource);
		_ ->
			add_resource7(Resource, Related)
	end.
%% @hidden
add_resource7(Resource, Related) ->
	case lists:keyfind(?INDEX_ROW_SPEC, #resource_spec_rel.id, Related) of
		#resource_spec_rel{rel_type = <<"based">>} ->
			add_resource_index_row(Resource);
		_ ->
			add_resource8(Resource, Related)
	end.
%% @hidden
add_resource8(Resource, Related) ->
	case lists:keyfind(?PREFIX_ROW_SPEC, #resource_spec_rel.id, Related) of
		#resource_spec_rel{rel_type = <<"based">>} ->
			add_resource_prefix_row(Resource);
		_ ->
			add_resource9(Resource, Related)
	end.
%% @hidden
add_resource9(Resource, Related) ->
	case lists:keyfind(?RANGE_ROW_SPEC, #resource_spec_rel.id, Related) of
		#resource_spec_rel{rel_type = <<"based">>} ->
			add_resource_range_row(Resource);
		_ ->
			add_resource10(Resource)
	end.
%% @hidden
add_resource10(Resource) ->
	F = fun() ->
			mnesia:write(Resource)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			{ok, Resource};
		{aborted, Reason} ->
			{error, Reason}
	end.

%% @hidden
add_resource_index_table(#resource{name = Name} = Resource) ->
	case mnesia:table_info(?binary_to_existing_atom(Name), attributes) of
		[key, val] ->
			F = fun() ->
					mnesia:write(Resource)
			end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					{ok, Resource};
				{aborted, Reason} ->
					{error, Reason}
			end;
		_ ->
			{error, table_not_found}
	end.

%% @hidden
add_resource_index_row(#resource{related = Related} = Resource) ->
	case maps:find(<<"contained">>, Related) of
		{ok, #resource_rel{rel_type = <<"contained">>,
				resource = #resource_ref{name = Table}}} ->
			add_resource_index_row(Table, Resource);
		error ->
			{error, table_not_found}
	end.
%% @hidden
add_resource_index_row(Table,
		#resource{characteristic = Chars} = Resource) ->
	case maps:find(<<"key">>, Chars) of
		{ok, #characteristic{name = <<"key">>, value = Key}} ->
			case maps:find(<<"value">>, Chars) of
				{ok, #characteristic{name = <<"value">>, value = Value}} ->
					add_resource_index_row(Table, Resource, Key, Value);
				error ->
					{error, missing_chars}
			end;
		error ->
			{error, missing_chars}
	end.
%% @hidden
add_resource_index_row(TableS, Resource, Key, Value) ->
	TableA = ?binary_to_existing_atom(TableS),
	Record = {TableA, Key, Value},
	F = fun() ->
			mnesia:write(TableA, Record, write),
			mnesia:write(Resource)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			{ok, Resource};
		{aborted, Reason} ->
			{error, Reason}
	end.

%% @hidden
add_resource_prefix_table(#resource{name = Name} = Resource) ->
	case mnesia:table_info(?binary_to_existing_atom(Name), attributes) of
		[num, value] ->
			F = fun() ->
					mnesia:write(Resource)
			end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					{ok, Resource};
				{aborted, Reason} ->
					{error, Reason}
			end;
		_ ->
			{error, table_not_found}
	end.

%% @hidden
add_resource_prefix_row(#resource{related = Related} = Resource) ->
	case maps:find(<<"contained">>, Related) of
		{ok, #resource_rel{rel_type = <<"contained">>,
				resource = #resource_ref{name = Table}}} ->
			add_resource_prefix_row(Table, Resource);
		error ->
			{error, table_not_found}
	end.
%% @hidden
add_resource_prefix_row(Table,
		#resource{characteristic = Chars} = Resource) ->
	case maps:find(<<"prefix">>, Chars) of
		{ok, #characteristic{name = <<"prefix">>, value = Prefix}} ->
			case maps:find(<<"value">>, Chars) of
				{ok, #characteristic{name = <<"value">>, value = Value}} ->
					add_resource_prefix_row(Table, Resource, Prefix, Value);
				error ->
					{error, missing_chars}
			end;
		error ->
			{error, missing_chars}
	end.
%% @hidden
add_resource_prefix_row(Table, Resource, Prefix, Value) ->
	case cse_gtt:insert(Table, Prefix, Value) of
		{ok, #gtt{}} ->
			F = fun() ->
					mnesia:write(Resource)
			end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					{ok, Resource};
				{aborted, Reason} ->
					{error, Reason}
			end;
		{error, already_exists} ->
			{error, already_exists};
		{error, Reason} ->
			{error, Reason}
	end.

%% @hidden
add_resource_range_row(#resource{related = Related} = Resource) ->
	case maps:find(<<"contained">>, Related) of
		{ok, #resource_rel{rel_type = <<"contained">>,
				resource = #resource_ref{name = Table}}} ->
			add_resource_range_row(Table, Resource);
		error ->
			{error, table_not_found}
	end.
%% @hidden
add_resource_range_row(Table,
		#resource{characteristic = Chars} = Resource) ->
	case maps:find(<<"start">>, Chars) of
		{ok, #characteristic{name = <<"start">>, value = Start}} ->
			case maps:find(<<"end">>, Chars) of
				{ok, #characteristic{name = <<"end">>, value = End}} ->
					case maps:find(<<"value">>, Chars) of
						{ok, #characteristic{name = <<"value">>, value = Value}} ->
							add_resource_range_row(Table, Resource, Start, End, Value);
						error ->
							{error, missing_chars}
					end;
				error ->
					{error, missing_chars}
			end;
		error ->
			{error, missing_chars}
	end.
%% @hidden
add_resource_range_row(Table, Resource, Start, End, Value) ->
	case cse_gtt:add_range(Table, Start, End, Value) of
		ok ->
			F = fun() ->
					mnesia:write(Resource)
			end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					{ok, Resource};
				{aborted, Reason} ->
					{error, Reason}
			end;
		{error, conflict} ->
			{error, already_exists}
	end.

-spec get_resource_specs() -> Result
	when
		Result :: [#resource_spec{}] | {error, Reason},
		Reason :: term().
%% @doc List all entries in the Resource Specification table.
get_resource_specs() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
				F(mnesia:select(resource_spec, MatchSpec, ?CHUNKSIZE, read), Acc);
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
		Result :: [#resource{}] | {error, Reason},
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
	case catch mnesia:ets(F, [start, []]) of
		[] ->
			{error, not_found};
		Acc when is_list(Acc) ->
			lists:flatten(lists:reverse(Acc));
		{'EXIT', Reason} ->
			{error, Reason}
	end.

-spec find_resource_spec(ID) -> Result
	when
		ID :: binary() | string(),
		Result :: {ok, ResourceSpecification} | {error, Reason},
		ResourceSpecification :: #resource_spec{},
		Reason :: not_found | term().
%% @doc Get a Resource Specification by identifier.
find_resource_spec(ID) when is_list(ID) ->
	find_resource_spec(list_to_binary(ID));
find_resource_spec(ID) when is_binary(ID) ->
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
		ID :: binary() | string(),
		Result :: {ok, Resource} | {error, Reason},
		Resource :: #resource{},
		Reason :: not_found | term().
%% @doc Get a Resource by identifier.
find_resource(ID) when is_list(ID) ->
	find_resource(list_to_binary(ID));
find_resource(ID) when is_binary(ID) ->
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
		ID :: binary() | string(),
		Result :: ok | {error, Reason},
		Reason :: not_found | term().
%% @doc Delete an entry from the Resource Specification table.
delete_resource_spec(ID) when is_list(ID) ->
	delete_resource_spec(list_to_binary(ID));
delete_resource_spec(ID) when is_binary(ID) ->
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
		ID :: binary() | string(),
		Result :: ok | {error, Reason},
		Reason :: not_found | term().
%% @doc Delete an entry from the Resource table.
delete_resource(ID) when is_list(ID) ->
	delete_resource(list_to_binary(ID));
delete_resource(ID) when is_binary(ID) ->
	F = fun() ->
			case mnesia:read(resource, ID, write) of
				[#resource{id = ID} = Resource1] ->
					{mnesia:delete(resource, ID, write), Resource1};
				[] ->
					mnesia:abort(not_found)
			end
	end,
	case mnesia:transaction(F) of
		{aborted, Reason} ->
			{error, Reason};
		{atomic, {ok, #resource{name = Name,
				specification = #resource_spec_ref{id = ?INDEX_TABLE_SPEC}}}} ->
			TableName = ?binary_to_existing_atom(Name),
			case mnesia:clear_table(TableName) of
				{atomic, ok} ->
					ok;
				{aborted, Reason} ->
					{error, Reason}
			end;
		{atomic, {ok, #resource{name = Name,
				specification = #resource_spec_ref{id = ?PREFIX_TABLE_SPEC}}}} ->
			cse_gtt:clear_table(Name);
		{atomic, {ok, #resource{name = Name,
				specification = #resource_spec_ref{id = ?RANGE_TABLE_SPEC}}}} ->
			cse_gtt:clear_table(Name);
		{atomic, {ok, #resource{specification = #resource_spec_ref{
				id = ?INDEX_ROW_SPEC}} = Resource2}} ->
			delete_resource_row(?INDEX_ROW_SPEC, Resource2);
		{atomic, {ok, #resource{specification = #resource_spec_ref{
				id = ?PREFIX_ROW_SPEC}} = Resource2}} ->
			delete_resource_row(?PREFIX_ROW_SPEC, Resource2);
		{atomic, {ok, #resource{specification = #resource_spec_ref{
				id = ?RANGE_ROW_SPEC}} = Resource2}} ->
			delete_resource_row(?RANGE_ROW_SPEC, Resource2);
		{atomic, {ok, #resource{name = Name,
				specification = #resource_spec_ref{id = SpecId}} = Resource2}} ->
			case cse:find_resource_spec(SpecId) of
				{ok, #resource_spec{related = Related}} ->
					case lists:keyfind(<<"based">>,
							#resource_spec_rel.rel_type, Related) of
						#resource_spec_rel{id = ?INDEX_TABLE_SPEC, rel_type = <<"based">>} ->
							TableName = ?binary_to_existing_atom(Name),
							case mnesia:clear_table(TableName) of
								{atomic, ok} ->
									ok;
								{aborted, Reason} ->
									{error, Reason}
							end;
						#resource_spec_rel{id = ?PREFIX_TABLE_SPEC, rel_type = <<"based">>} ->
							cse_gtt:clear_table(Name);
						#resource_spec_rel{id = ?RANGE_TABLE_SPEC, rel_type = <<"based">>} ->
							cse_gtt:clear_table(Name);
						#resource_spec_rel{id = ?INDEX_ROW_SPEC, rel_type = <<"based">>} ->
							delete_resource_row(?INDEX_ROW_SPEC, Resource2);
						#resource_spec_rel{id = ?PREFIX_ROW_SPEC, rel_type = <<"based">>} ->
							delete_resource_row(?PREFIX_ROW_SPEC, Resource2);
						#resource_spec_rel{id = ?RANGE_ROW_SPEC, rel_type = <<"based">>} ->
							delete_resource_row(?RANGE_ROW_SPEC, Resource2);
						_ ->
							ok
					end;
				{error, Reason} ->
					{error, Reason}
			end
	end.

%% @hidden
delete_resource_row(Based,
		#resource{related = #{<<"contained">> := #resource_rel{
		resource = #resource_ref{name = Table}}}} = Resource) ->
	delete_resource_row(Based, Table, Resource);
delete_resource_row(_Based, _Resource) ->
	{error, table_not_found}.
%% @hidden
delete_resource_row(?INDEX_ROW_SPEC, Table, #resource{
		characteristic = #{<<"key">> := #characteristic{value = Key}}}) ->
	TableName = ?binary_to_existing_atom(Table),
	F = fun()  ->
			mnesia:delete(TableName, Key, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			{error, Reason}
	end;
delete_resource_row(?PREFIX_ROW_SPEC, Table, #resource{
		characteristic = #{<<"prefix">> := #characteristic{value = Prefix}}}) ->
	TableName = ?binary_to_existing_atom(Table),
	cse_gtt:delete(TableName, Prefix);
delete_resource_row(?RANGE_ROW_SPEC, Table, #resource{
		characteristic = #{<<"start">> := #characteristic{value = Start},
		<<"end">> := #characteristic{value = End}}}) ->
	TableName = ?binary_to_existing_atom(Table),
	cse_gtt:delete_range(TableName, Start, End);
delete_resource_row(_Based, _Table, _Resource) ->
	{error, table_not_found}.

-dialyzer({nowarn_function, query_resource_spec1/5}).
-spec query_resource_spec(Cont, MatchName,
		MatchRelId, MatchRelType) -> Result
	when
		Cont :: start | any(),
		MatchName :: {exact, MatchValue} | {like, MatchValue} | '_',
		MatchRelId :: {exact, MatchValue} | '_',
		MatchRelType :: {exact, MatchValue} | {like, MatchValue} | '_',
		MatchValue :: string() | binary(),
		Result :: {Cont1, [#resource_spec{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query the Resource Specification table.
%%
%% 	The resource specification table may be queried using
%% 	match operations on select attributes. The `exact'
%% 	operator matches when the entire target value matches
%% 	`MatchValue' exactly. The `like' operator may be used
%% 	for partial matching. If the operator is `like', and
%% 	the last character of `MatchValue' is `%', the value
%% 	before the `%' is matched against the prefix of the
%% 	same length of the target value. All match operations
%% 	must succeed to select a resource specification.
%% 	
%% 	Resource specifications may be selected by name with
%% 	`MatchName'.
%%
%% 	Resource specifications may be selected by related
%% 	resource specification. The name of a relationship
%% 	type (`rel_type') (e.g. `"based"') may be	matched
%% 	with `MatchRelType'. The identifier (`id') of the
%% 	related resource specification mab be matched with
%% 	`MatchRelId'. Note that matching is limited to the
%% 	the first relationship in the list.
%%
query_resource_spec(Cont, '_' = _MatchName,
		MatchRelId, MatchRelType) ->
	MatchHead = #resource_spec{_ = '_'},
	query_resource_spec1(Cont, MatchHead, [],
			MatchRelId, MatchRelType);
query_resource_spec(Cont, {Op, MatchValue},
		MatchRelId, MatchRelType) when is_list(MatchValue) ->
	query_resource_spec(Cont, {Op, list_to_binary(MatchValue)},
			MatchRelId, MatchRelType);
query_resource_spec(Cont, {exact, MatchValue},
		MatchRelId, MatchRelType) when is_binary(MatchValue) ->
	MatchHead = #resource_spec{name = MatchValue, _ = '_'},
	query_resource_spec1(Cont, MatchHead, [],
			MatchRelId, MatchRelType);
query_resource_spec(Cont, {like, MatchValue},
		MatchRelId, MatchRelType) when is_binary(MatchValue) ->
	case binary:last(MatchValue) of
		$% ->
			Size = byte_size(MatchValue) - 1,
			Prefix = binary_part(MatchValue, 0, Size),
			MatchHead = #resource_spec{name = '$1', _ = '_'},
			BinaryPart = {'binary_part', '$1', 0, Size},
			MatchConditions = [{'==', BinaryPart, Prefix}],
			query_resource_spec1(Cont, MatchHead, MatchConditions,
					MatchRelId, MatchRelType);
		_ ->
			MatchHead = #resource_spec{name = MatchValue, _ = '_'},
			query_resource_spec1(Cont, MatchHead, [],
					MatchRelId, MatchRelType)
	end.
%% @hidden
query_resource_spec1(Cont, MatchHead, MatchConditions, '_', '_') ->
	MatchSpec = [{MatchHead, MatchConditions, ['$_']}],
	query_resource_spec2(Cont, MatchSpec);
query_resource_spec1(Cont, MatchHead, MatchConditions,
		{Op, MatchValue}, MatchRelType) when is_list(MatchValue) ->
	query_resource_spec1(Cont, MatchHead, MatchConditions,
		{Op, list_to_binary(MatchValue)}, MatchRelType);
query_resource_spec1(Cont, MatchHead, MatchConditions,
		MatchRelId, {Op, MatchValue}) when is_list(MatchValue) ->
	query_resource_spec1(Cont, MatchHead, MatchConditions,
		MatchRelId, {Op, list_to_binary(MatchValue)});
query_resource_spec1(Cont, MatchHead, MatchConditions,
		 MatchRelId, MatchRelType) ->
	MatchRelId1 = case MatchRelId of
		{exact, MatchValue1} ->
			MatchValue1;
		'_' ->
			'_'
	end,
	{MatchRelType1, MatchConditions2} = case MatchRelType of
		{like, MatchValue2} when binary_part(MatchValue2,
				byte_size(MatchValue2), - 1) == <<$->> ->
			Size = byte_size(MatchValue2) - 1,
			Prefix = binary_part(MatchValue2, 0, Size),
			BinaryPart = {'binary_part', '$2', 0, Size},
			MatchConditions1 = [{'==', BinaryPart, Prefix}],
			{'$2', MatchConditions ++ MatchConditions1};
		{like, MatchValue2} ->
			{MatchValue2, MatchConditions};
		{exact, MatchValue2} ->
			{MatchValue2, MatchConditions};
		'_' ->
			{'_', MatchConditions}
	end,
	Related = [#resource_spec_rel{id = MatchRelId1,
			rel_type = MatchRelType1, _ = '_'} | '_'],
	MatchHead1 = MatchHead#resource_spec{related = Related},
	MatchSpec = [{MatchHead1, MatchConditions2, ['$_']}],
	query_resource_spec2(Cont, MatchSpec).
%% @hidden
query_resource_spec2(start, MatchSpec) ->
	F = fun() ->
			mnesia:select(resource_spec, MatchSpec, ?CHUNKSIZE, read)
	end,
	query_resource_spec3(mnesia:ets(F));
query_resource_spec2(Cont, _MatchSpec) ->
	F = fun() ->
			mnesia:select(Cont)
	end,
	query_resource_spec3(mnesia:ets(F)).
%% @hidden
query_resource_spec3({Resources, Cont}) ->
	{Cont, Resources};
query_resource_spec3('$end_of_table') ->
	{eof, []}.

-spec query_resource(Cont, MatchName, MatchResSpecId,
		MatchRelType, MatchRelName, MatchChars) -> Result
	when
		Cont :: start | any(),
		MatchName :: {exact, MatchValue} | {like, MatchValue} | '_',
		MatchResSpecId :: {exact, MatchValue} | '_',
		MatchRelType :: {exact, MatchValue} | '_',
		MatchRelName :: {exact, MatchValue} | '_',
		MatchChars :: [{{exact, CharName}, {exact, CharValue}}] | '_',
		MatchValue :: string() | binary(),
		CharName :: MatchValue,
		CharValue :: MatchValue | '_',
		Result :: {Cont1, [#resource{}]} | {error, Reason},
		Cont1 :: eof | any(),
		Reason :: term().
%% @doc Query the Resource table.
%%
%% 	The resource table may be queried using match operations
%% 	on select attributes. The `exact' operator matches when
%% 	the entire target value matches `MatchValue' exactly. The
%% 	`like' operator may be used for partial matching. If the
%% 	operator is `like', and the last character of `MatchValue'
%% 	is `%', the value before the `%' is matched against the
%% 	prefix of the same length of the target value. All match
%% 	operations must succeed to select a resource.
%% 	
%% 	Resources may be selected by name with `MatchName'.
%%
%% 	Resources may be selected by identifier of the resource
%% 	specification they reference with `MatchResSpecId'.
%%
%% 	Resources may be selected by related resource.  The name
%% 	of a resource relationship (e.g. `"contained"') may be
%% 	matched with `MatchRelType' and optionally the name of
%% 	the related resource with `MatchRelName'. Note that
%% 	use of `MatchRelName' requires a value for `MatchRelType'
%% 	to also be provided.
%%
%% 	Resources may be selected by characteristic values. A
%% 	list of resource characteristic name/value pair match
%% 	operations may be provided in `MatchChars'.
%% 	
query_resource(Cont, '_' = _MatchName, MatchResSpecId,
		MatchRelType, MatchRelName, MatchChars) ->
	MatchHead = #resource{_ = '_'},
	query_resource1(Cont, MatchHead, [], MatchResSpecId,
			MatchRelType, MatchRelName, MatchChars);
query_resource(Cont, {Op, MatchValue}, MatchResSpecId,
		MatchRelType, MatchRelName, MatchChars)
		when is_list(MatchValue) ->
	query_resource(Cont, {Op, list_to_binary(MatchValue)},
		MatchResSpecId, MatchRelType, MatchRelName, MatchChars);
query_resource(Cont, {exact, MatchValue}, MatchResSpecId,
		MatchRelType, MatchRelName, MatchChars)
		when is_binary(MatchValue) ->
	MatchHead = #resource{name = MatchValue, _ = '_'},
	query_resource1(Cont, MatchHead, [],
		MatchResSpecId, MatchRelType, MatchRelName, MatchChars);
query_resource(Cont, {like, MatchValue}, MatchResSpecId,
		MatchRelType, MatchRelName, MatchChars)
		when is_binary(MatchValue) ->
	case binary:last(MatchValue) of
		$% ->
			Size = byte_size(MatchValue) - 1,
			Prefix = binary_part(MatchValue, 0, Size),
			MatchHead = #resource{name = '$1', _ = '_'},
			BinaryPart = {'binary_part', '$1', 0, Size},
			MatchConditions = [{'==', BinaryPart, Prefix}],
			query_resource1(Cont, MatchHead, MatchConditions,
					MatchResSpecId, MatchRelType, MatchRelName, MatchChars);
		_ ->
			MatchHead = #resource{name = MatchValue, _ = '_'},
			query_resource1(Cont, MatchHead, [],
					MatchResSpecId, MatchRelType, MatchRelName, MatchChars)
	end.
%% @hidden
query_resource1(Cont, MatchHead, MatchConditions, '_' = _MatchResSpecId,
		MatchRelType, MatchRelName, MatchChars) ->
	query_resource2(Cont, MatchHead, MatchConditions,
			MatchRelType, MatchRelName, MatchChars);
query_resource1(Cont, MatchHead, MatchConditions, {Op, MatchValue},
		MatchRelType, MatchRelName, MatchChars) when is_list(MatchValue) ->
	query_resource1(Cont, MatchHead, MatchConditions,
			{Op, list_to_binary(MatchValue)}, MatchRelType,
			MatchRelName, MatchChars);
query_resource1(Cont, MatchHead, MatchConditions, {exact, MatchValue},
		MatchRelType, MatchRelName, MatchChars) when is_binary(MatchValue) ->
	ResourceSpecRef = #resource_spec_ref{id = MatchValue, _ = '_'},
	MatchHead1 = MatchHead#resource{specification = ResourceSpecRef},
	query_resource2(Cont, MatchHead1, MatchConditions,
			MatchRelType, MatchRelName, MatchChars).
%% @hidden
query_resource2(Cont, MatchHead, MatchConditions, '_', '_', MatchChars) ->
	query_resource3(Cont, MatchHead, MatchConditions, MatchChars);
query_resource2(Cont, MatchHead, MatchConditions,
		{Op, MatchValue}, MatchRelName, MatchChars) when is_list(MatchValue) ->
	query_resource2(Cont, MatchHead, MatchConditions,
			{Op, list_to_binary(MatchValue)}, MatchRelName, MatchChars);
query_resource2(Cont, MatchHead, MatchConditions, MatchRelType,
		{Op, MatchValue}, MatchChars) when is_list(MatchValue) ->
	query_resource2(Cont, MatchHead, MatchConditions, MatchRelType,
			{Op, list_to_binary(MatchValue)}, MatchChars);
query_resource2(Cont, MatchHead, MatchConditions,
		MatchRelType, MatchRelName, MatchChars) ->
	{MatchRelType1, MatchConditions2} = case MatchRelType of
		{like, MatchValue1} when binary_part(MatchValue1,
				byte_size(MatchValue1), - 1) == <<$->> ->
			Size1 = byte_size(MatchValue1) - 1,
			Prefix1 = binary_part(MatchValue1, 0, Size1),
			BinaryPart1 = {'binary_part', '$2', 0, Size1},
			MatchConditions1 = [{'==', BinaryPart1, Prefix1}],
			{'$2', MatchConditions ++ MatchConditions1};
		{like, MatchValue1} ->
			{MatchValue1, MatchConditions};
		{exact, MatchValue1} ->
			{MatchValue1, MatchConditions};
		'_' ->
			{'_', MatchConditions}
	end,
	{MatchRelName1, MatchConditions4} = case MatchRelName of
		{like, MatchValue2} when binary_part(MatchValue2,
				byte_size(MatchValue2), - 1) == <<$->> ->
			Size2 = byte_size(MatchValue2) - 1,
			Prefix2 = binary_part(MatchValue2, 0, Size2),
			BinaryPart2 = {'binary_part', '$3', 0, Size2},
			MatchConditions3 = [{'==', BinaryPart2, Prefix2}],
			{'$3', MatchConditions2 ++ MatchConditions3};
		{like, MatchValue2} ->
			{MatchValue2, MatchConditions2};
		{exact, MatchValue2} ->
			{MatchValue2, MatchConditions2};
		'_' ->
			{'_', MatchConditions2}
	end,
	ResourceRef = #resource_ref{name = MatchRelName1, _ = '_'},
	ResourceRel = #resource_rel{resource = ResourceRef, _ = '_'},
	Related = #{MatchRelType1 => ResourceRel},
	MatchHead1 = MatchHead#resource{related = Related},
	query_resource3(Cont, MatchHead1, MatchConditions4, MatchChars).
%% @hidden
query_resource3(Cont, MatchHead, MatchConditions, '_' = _MatchChars) ->
	MatchSpec = [{MatchHead, MatchConditions, ['$_']}],
	query_resource4(Cont, MatchSpec);
query_resource3(Cont, #resource{characteristic = '_'} = MatchHead,
		MatchConditions, MatchChars) ->
	query_resource3(Cont, MatchHead#resource{characteristic = #{}},
		MatchConditions, MatchChars);
query_resource3(Cont, MatchHead, MatchConditions,
		[{{exact, CharName}, {exact, CharValue}} | T])
		when is_list(CharName) ->
	query_resource3(Cont, MatchHead, MatchConditions,
		[{{exact, list_to_binary(CharName)}, {exact, CharValue}} | T]);
query_resource3(Cont, MatchHead, MatchConditions,
		[{{exact, CharName}, {exact, CharValue}} | T])
		when is_list(CharValue) ->
	query_resource3(Cont, MatchHead, MatchConditions,
		[{{exact, CharName}, {exact, list_to_binary(CharValue)}} | T]);
query_resource3(Cont,
		#resource{characteristic = Characteristics} = MatchHead,
		MatchConditions, [{{exact, CharName}, {exact, CharValue}} | T])
		when is_map(Characteristics), is_binary(CharName),
		((is_binary(CharValue)) or (CharValue == '_')) ->
	Characteristic = #characteristic{name = CharName,
			value = CharValue, _ = '_'},
	Characteristics1 = Characteristics#{CharName => Characteristic},
	MatchHead1 = MatchHead#resource{characteristic = Characteristics1},
	query_resource3(Cont, MatchHead1, MatchConditions, T);
query_resource3(Cont, MatchHead, MatchConditions, []) ->
	MatchSpec = [{MatchHead, MatchConditions, ['$_']}],
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

-spec add_service(Key, Module, EDP) -> ok
	when
		Key :: 0..2147483647,
		Module :: atom(),
		EDP :: #{event_type() => monitor_mode()}.
%% @doc Register an IN Service Logic Processing Program (SLP).
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
			Service = #in_service{key = Key, module = Module, edp = EDP},
			F = fun() ->
					mnesia:write(cse_service, Service, write)
			end,
			case mnesia:transaction(F) of
				{atomic, ok} ->
					ok;
				{aborted, Reason} ->
					exit(Reason)
			end;
		false ->
			error(function_clause, [Key, Module, EDP])
	end.

-spec get_service(Key) -> Result
	when
		Key :: 0..2147483647,
		Result :: in_service().
%% @doc Get the IN SLP registered with `Key'.
get_service(Key) when is_integer(Key) ->
	F = fun() ->
			mnesia:read(cse_service, Key, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#in_service{} = Service]} ->
			Service;
		{atomic, []} ->
			exit(not_found);
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec find_service(Key) -> Result
	when
		Key :: 0..2147483647,
		Result :: {ok, in_service()} | {error, Reason},
		Reason :: not_found | term().
%% @doc Find an IN SLP registered with `Key'.
find_service(Key) when is_integer(Key) ->
	F = fun() ->
			mnesia:read(cse_service, Key, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#in_service{} = Service]} ->
			{ok, Service};
		{atomic, []} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_services() -> Services
	when
		Services :: [in_service()].
%% @doc Get all registered IN SLPs.
get_services() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
				F(mnesia:select(cse_service,
						MatchSpec, ?CHUNKSIZE, read), Acc);
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
%% @doc Delete an IN SLP registration.
delete_service(Key) when is_integer(Key) ->
	F = fun() ->
		mnesia:delete(cse_service, Key, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec add_context(ContextId, Module, Args, Opts) -> ok
	when
		ContextId :: diameter:'UTF8String'(),
		Module :: atom(),
		Args :: [term()],
		Opts :: [term()].
%% @doc Register a DIAMETER Service Logic Processing Program (SLP).
%%
%% 	The `Service-Context-Id' of a `Credit-Control-Request'
%% 	identifies the service logic logic which should be
%% 	provided for the call.  An SLP is implemented in a
%% 	`Module'.
%%
add_context(ContextId, Module, Args, Opts)
		when (is_list(ContextId) or is_binary(ContextId)),
		is_atom(Module), is_list(Args), is_list(Opts) ->
	Context = #diameter_context{id = iolist_to_binary(ContextId),
			module = Module, args = Args, opts = Opts},
	F = fun() ->
			mnesia:write(cse_context, Context, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec get_context(ContextId) -> Result
	when
		ContextId :: diameter:'UTF8String'(),
		Result :: diameter_context().
%% @doc Get the IN SLP registered with `ContextId'.
get_context(ContextId)
		when is_list(ContextId); is_binary(ContextId) ->
	case catch iolist_to_binary(ContextId) of
		ContextId1 when is_binary(ContextId1) ->
			get_context1(ContextId1);
		{'EXIT', _} ->
			error(function_clause, [ContextId])
	end.
%% @hidden
get_context1(ContextId) ->
	F = fun() ->
			mnesia:read(cse_context, ContextId, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#diameter_context{} = Context]} ->
			Context;
		{atomic, []} ->
			exit(not_found);
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec find_context(ContextId) -> Result
	when
		ContextId :: diameter:'UTF8String'(),
		Result :: {ok, diameter_context()} | {error, Reason},
		Reason :: not_found | term().
%% @doc Find a DIAMETER SLP registered with `Key'.
find_context(ContextId)
		when is_list(ContextId); is_binary(ContextId) ->
	case catch iolist_to_binary(ContextId) of
		ContextId1 when is_binary(ContextId1) ->
			find_context1(ContextId1);
		{'EXIT', _} ->
			error(function_clause, [ContextId])
	end.
%% @hidden
find_context1(ContextId) ->
	F = fun() ->
			mnesia:read(cse_context, ContextId, read)
	end,
	case mnesia:transaction(F) of
		{atomic, [#diameter_context{} = Service]} ->
			{ok, Service};
		{atomic, []} ->
			{error, not_found};
		{aborted, Reason} ->
			{error, Reason}
	end.

-spec get_contexts() -> Contexts
	when
		Contexts :: [diameter_context()].
%% @doc Get all registered DIAMETER SLPs.
get_contexts() ->
	MatchSpec = [{'_', [], ['$_']}],
	F = fun F(start, Acc) ->
				F(mnesia:select(cse_context,
						MatchSpec, ?CHUNKSIZE, read), Acc);
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

-spec delete_context(ContextId) -> ok
	when
		ContextId :: diameter:'UTF8String'().
%% @doc Delete a DIAMETER SLP registration.
delete_context(ContextId)
		when is_list(ContextId); is_binary(ContextId) ->
	case catch iolist_to_binary(ContextId) of
		ContextId1 when is_binary(ContextId1) ->
			delete_context1(ContextId1);
		{'EXIT', _} ->
			error(function_clause, [ContextId])
	end.
%% @hidden
delete_context1(ContextId) ->
	F = fun() ->
		mnesia:delete(cse_context, ContextId, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

-spec add_session(SessionId, SLPI) -> ok
	when
		SessionId :: binary(),
		SLPI :: pid().
%% @doc Register a DIAMETER SLP instance (SLPI).
%%
%% 	The DIAMETER `Session-Id' AVP is registered with
%% 	the `pid()' of an SLPI handling the session.
%%
add_session(SessionId, SLPI)
		when is_binary(SessionId), is_pid(SLPI) ->
	ets:insert(cse_session, {SessionId, SLPI}),
	ok.

-spec get_session(SessionId) -> SLPI
	when
		SessionId :: binary(),
		SLPI :: pid().
%% @doc Get the SLPI registered with `SessionId'.
get_session(SessionId)
		when is_binary(SessionId) ->
	[{_, SLPI}] = ets:lookup(cse_session, SessionId),
	SLPI.

-spec find_session(SessionId) -> Result
	when
		SessionId :: binary(),
		Result :: {ok, SLPI} | {error, Reason},
		SLPI :: pid(),
		Reason :: not_found | term().
%% @doc Find an SLPI registered with `SessionId'.
find_session(SessionId)
		when is_binary(SessionId) ->
	case catch ets:lookup(cse_session, SessionId) of
		[] ->
			{error, not_found};
		{'EXIT', Reason} ->
			{error, Reason};
		[{_, SLPI}] ->
			{ok, SLPI}
	end.

-spec get_sessions() -> Sessions
	when
		Sessions :: [Session],
		Session :: {SessionId, SLPI},
		SessionId :: binary(),
		SLPI :: pid().
%% @doc Get all registered SLPI.
get_sessions() ->
	ets:tab2list(cse_session).

-spec delete_session(SessionId) -> ok
	when
		SessionId :: binary().
%% @doc Delete an SLPI registration.
delete_session(SessionId)
		when is_binary(SessionId) ->
	ets:delete(cse_session, SessionId),
	ok.

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

-spec statistics(Item) -> Result
   when
      Item :: scheduler_utilization,
      Result :: {ok, {Etag, Interval, Report}} | {error, Reason},
      Etag :: string(),
      Interval :: pos_integer(),
      Report :: [ItemResult],
      ItemResult :: {SchedulerId, Utilization},
      SchedulerId :: pos_integer(),
      Utilization :: non_neg_integer(),
      Reason :: term().
%% @doc Get system statistics.
statistics(Item) ->
   case catch gen_server:call(cse_statistics, Item) of
      {Etag, Interval, Report} ->
         {ok, {Etag, Interval, Report}};
      {error, Reason} ->
         {error, Reason};
      {'EXIT', {noproc,_}} ->
         case catch supervisor:start_child(cse_statistics_sup, []) of
            {ok, Child} ->
               case catch gen_server:call(Child, Item) of
                  {Etag, Interval, Report} ->
                     {ok, {Etag, Interval, Report}};
                  {error, Reason} ->
                     {error, Reason}
               end;
            {error, Reason} ->
               {error, Reason};
            {'EXIT', {noproc,_}} ->
               {error, cse_down}
         end
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

