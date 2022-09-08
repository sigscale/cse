%%% cse_rest_res_resource.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022 SigScale Global Inc.
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //cse. cse} application.
%%%
-module(cse_rest_res_resource).
-copyright('Copyright (c) 2022 SigScale Global Inc.').

% export cse_rest_res_resource public API
-export([content_types_accepted/0, content_types_provided/0]).
-export([get_resource_spec/1, get_resource_specs/2, add_resource_spec/1,
		delete_resource_spec/2, resource_spec/1]).
-export([get_resource/1, get_resource/2, add_resource/1, delete_resource/2,
		resource/1]).
% export cse_rest_res_resource private API
-export([prefix_table_spec_id/0, prefix_row_spec_id/0, static_spec/1,
		prefix_range_table_spec_id/0, prefix_range_row_spec_id/0]).

-include("cse.hrl").

-define(specPath, "/resourceCatalogManagement/v4/resourceSpecification/").
-define(inventoryPath, "/resourceInventoryManagement/v4/resource/").

-define(PREFIX_TABLE_SPEC,       "1647577955926-50").
-define(PREFIX_ROW_SPEC,         "1647577957914-66").
-define(PREFIX_RANGE_TABLE_SPEC, "1651055414682-258").
-define(PREFIX_RANGE_ROW_SPEC,   "1651057291061-274").

%%----------------------------------------------------------------------
%%  cse_rest_res_resource public API functions
%%----------------------------------------------------------------------

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json", "application/json-patch+json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/json"].

-spec get_resource_spec(ID) -> Result
	when
		ID :: string(),
		Result :: {ok, Headers, Body} | {error, Status},
		Headers :: [tuple()],
		Body :: string(),
		Status :: 404 | 500.
%% @doc Retrieve a Resource Specification.
%%
%% 	Respond to `GET /resourceCatalogManagement/v4/resourceSpecification/{id}'.
get_resource_spec(ID) ->
	case cse:find_resource_spec(ID) of
		{ok, #resource_spec{} = Specification} ->
			Body = zj:encode(resource_spec(Specification)),
			Headers = [{content_type, "application/json"}],
			{ok, Headers, Body};
		{error, not_found} ->
			{error, 404};
		{error, _Reason} ->
			{error, 500}
	end.

-spec get_resource_specs(Query, Headers) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		Headers :: [tuple()],
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode},
		ErrorCode :: 400 | 404 | 500.
%% @doc Respond to `GET /resourceCatalogManagement/v4/resourceSpecification'.
%% 	Retrieve all Resource Specifications.
get_resource_specs(Query, Headers) ->
	try
		{Query1, MatchId} = get_param("id", Query, '_'),
		{Query2, MatchName} = get_param("name", Query1, '_'),
		case get_filters(Query2) of
			{Query3, []} ->
				MatchRelId = '_',
				MatchRelType = '_',
				{Query3, [MatchId, MatchName, MatchRelId, MatchRelType]};
			{Query3, Filters} ->
				case match_filters("resourceSpecRelationship", Filters) of
					{ok, MatchRelId, MatchRelType} ->
						{Query3, [MatchId, MatchName, MatchRelId, MatchRelType]};
					{error, not_found} ->
						{Query3, [MatchId, MatchName, '_', '_']}
				end
		end
	of
		{Query4, Args} ->
			Codec = fun resource_spec/1,
			query_filter({cse, query_resource_spec, Args}, Codec, Query4, Headers)
	catch
		_Error:_Reason ->
			{error, 400}
	end.

-spec add_resource_spec(RequestBody) -> Result
	when
		RequestBody :: list(),
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
			| {error, ErrorCode :: integer()}.
%% @doc Respond to `POST /resourceCatalogManagement/v4/resourceSpecification'.
%% 	Handle `POST' request on `ResourceSpecification' collection.
add_resource_spec(RequestBody) ->
	try
		{ok, ResSpecMap} = zj:decode(RequestBody),
		resource_spec(ResSpecMap)
	of
		#resource_spec{} = ResourceSpec ->
			add_resource_spec1(ResourceSpec)
	catch
		_:_Reason ->
			{error, 400}
	end.
%% @hidden
add_resource_spec1(#resource_spec{name = Name,
		related = [#resource_spec_rel{id = ?PREFIX_TABLE_SPEC,
		rel_type = "based"} | _]} = ResourceSpec) ->
	add_resource_spec2(ResourceSpec, Name,
			cse:query_resource_spec(start, '_', {exact, Name}, '_', '_'));
add_resource_spec1(#resource_spec{} = ResourceSpec) ->
	add_resource_spec3(cse:add_resource_spec(ResourceSpec)).
%% @hidden
add_resource_spec2(ResourceSpec, _Name, {eof, []}) ->
	add_resource_spec3(cse:add_resource_spec(ResourceSpec));
add_resource_spec2(ResourceSpec, Name, {Cont, []}) ->
	add_resource_spec2(ResourceSpec, Name,
			cse:query_resource_spec(Cont, '_', {exact, Name}, '_', '_'));
add_resource_spec2(_ResourceSpec, _Name, {_Cont_, [_H | _T]}) ->
	{error, 409};
add_resource_spec2(_ResourceSpec, _Name, {error, _Reason}) ->
	{error, 500}.
%% @hidden
add_resource_spec3({ok, #resource_spec{href = Href,
		last_modified = LM} = NewResSpec}) ->
	Body = zj:encode(resource_spec(NewResSpec)),
	Headers = [{location, Href}, {etag, cse_rest:etag(LM)},
			{content_type, "application/json"}],
	{ok, Headers, Body};
add_resource_spec3({error, _Reason}) ->
	{error, 400}.

-spec delete_resource_spec(Id, Query) -> Result
	when
		Id :: string(),
		Query :: [{unicode:chardata(), unicode:chardata() | true}],
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()} .
%% @doc Respond to `DELETE /resourceCatalogyManagement/v4/resourceSpecification/{id}'
%%    request to remove a Resource Specification.
delete_resource_spec(Id, _Query)
		when Id == ?PREFIX_TABLE_SPEC;
		Id == ?PREFIX_ROW_SPEC;
		Id == ?PREFIX_RANGE_TABLE_SPEC;
		Id == ?PREFIX_RANGE_ROW_SPEC ->
	{error, 405};
delete_resource_spec(Id, []) ->
	case cse:delete_resource_spec(Id) of
		ok ->
			{ok, [], []};
		{error, not_found} ->
			{error, 404};
		{error, _Reason} ->
			{error, 500}
	end.

-spec get_resource(Id) -> Result
	when
		Id :: string(),
		Result   :: {ok, Headers, Body} | {error, Status},
		Headers  :: [tuple()],
		Body     :: iolist(),
		Status   :: 400 | 404 | 500.
%% @doc Respond to `GET /resourceInventoryManagement/v4/resource/{id}'.
%%    Retrieve resource from inventory management.
get_resource(Id) ->
	case cse:find_resource(Id) of
		{ok, #resource{last_modified = LM} = Resource} ->
			Headers = [{content_type, "application/json"},
							{etag, cse_rest:etag(LM)}],
			Body = zj:encode(resource(Resource)),
					{ok, Headers, Body};
		{error, not_found} ->
			{error, 404};
		{error, _Reason} ->
			{error, 500}
	end.

-spec get_resource(Query, Headers) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		Headers :: [tuple()],
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()}.
%% @doc Body producing function for
%% 	`GET|HEAD /resourceInventoryManagement/v4/resource'
%% 	requests.
get_resource(Query, Headers) ->
	try
		{Query1, MatchName} = get_param("name", Query, '_'),
		{Query2, MatchSpecId} = get_param("resourceSpecification.id", Query1, '_'),
		case get_filters(Query2) of
			{Query3, []} ->
				MatchRelType= '_',
				MatchRelName = '_',
				MatchChars = '_',
				{Query3, [MatchName, MatchSpecId,
						MatchRelType, MatchRelName, MatchChars]};
			{Query3, Filters} ->
				{MatchRelType, MatchRelName}
						= case match_filters("resourceRelationship", Filters) of
					{ok, RelType, RelName} ->
						{RelType, RelName};
					{error, not_found} ->
						{'_', '_'}
				end,
				case match_filters("resourceCharacteristic", Filters) of
					{ok, '_', '_'} ->
						{Query3, [MatchName, MatchSpecId,
								MatchRelType, MatchRelName, '_']};
					{ok, MatchCharName, MatchCharValue} ->
						MatchChars = [{MatchCharName, MatchCharValue}],
						{Query3, [MatchName, MatchSpecId,
								MatchRelType, MatchRelName, MatchChars]};
					{error, not_found} ->
						{Query3, [MatchName, MatchSpecId,
								MatchRelType, MatchRelName, '_']}
				end
		end
	of
		{Query4, Args} ->
			Codec = fun resource/1,
			query_filter({cse, query_resource, Args}, Codec, Query4, Headers)
	catch
		_Error:_Reason ->
			{error, 400}
	end.

%% @hidden
query_filter(MFA, Codec, Query, Headers) ->
	case lists:keytake("fields", 1, Query) of
		{value, {_, Filters}, NewQuery} ->
			query_filter(MFA, Codec, NewQuery, Filters, Headers);
		false ->
			query_filter(MFA, Codec, Query, [], Headers)
	end.
%% @hidden
query_filter(MFA, Codec, Query, Filters, Headers) ->
	case {lists:keyfind("if-match", 1, Headers),
			lists:keyfind("if-range", 1, Headers),
			lists:keyfind("range", 1, Headers)} of
		{{"if-match", Etag}, false, {"range", Range}} ->
			case global:whereis_name(Etag) of
				undefined ->
					{error, 412};
				PageServer ->
					case cse_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_page(Codec, PageServer,
									Etag, Query, Filters, Start, End)
					end
			end;
		{{"if-match", Etag}, false, false} ->
			case global:whereis_name(Etag) of
				undefined ->
					{error, 412};
				PageServer ->
					query_page(Codec, PageServer, Etag,
							Query, Filters, undefined, undefined)
			end;
		{false, {"if-range", Etag}, {"range", Range}} ->
			case global:whereis_name(Etag) of
				undefined ->
					case cse_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_start(MFA, Codec, Query, Filters, Start, End)
					end;
				PageServer ->
					case cse_rest:range(Range) of
						{error, _} ->
							{error, 400};
						{ok, {Start, End}} ->
							query_page(Codec, PageServer,
									Etag, Query, Filters, Start, End)
					end
			end;
		{{"if-match", _}, {"if-range", _}, _} ->
			{error, 400};
		{_, {"if-range", _}, false} ->
			{error, 400};
		{false, false, {"range", "items=1-" ++ _ = Range}} ->
			case cse_rest:range(Range) of
				{error, _} ->
					{error, 400};
				{ok, {Start, End}} ->
					query_start(MFA, Codec, Query, Filters, Start, End)
			end;
		{false, false, {"range", _Range}} ->
			{error, 416};
		{false, false, false} ->
			query_start(MFA, Codec, Query, Filters, undefined, undefined)
	end.

%% @hidden
query_page(Codec, PageServer, Etag, Query, _Filters, Start, End) ->
	case gen_server:call(PageServer, {Start, End}) of
		{error, Status} ->
			{error, Status};
		{[] = Result, ContentRange} ->
			Body = zj:encode(Result),
			Headers = [{content_type, "application/json"},
					{etag, Etag}, {accept_ranges, "items"},
					{content_range, ContentRange}],
			{ok, Headers, Body};
		{[#gtt{} | _] = Result, ContentRange} ->
			case lists:keyfind("resourceRelationship.resource.name", 1,
					Query) of
				{_, Table} ->
					Objects = [gtt(Table, {Prefix, Value})
							|| #gtt{num = Prefix, value = Value} <- Result],
					Body = zj:encode(Objects),
					Headers = [{content_type, "application/json"},
							{etag, Etag}, {accept_ranges, "items"},
							{content_range, ContentRange}],
					{ok, Headers, Body};
				false ->
					{error, 400}
			end;
		{Result, ContentRange} ->
			JsonObj = lists:map(Codec, Result),
			Body = zj:encode(JsonObj),
			Headers = [{content_type, "application/json"},
					{etag, Etag}, {accept_ranges, "items"},
					{content_range, ContentRange}],
			{ok, Headers, Body}
	end.

%% @hidden
query_start({M, F, A}, Codec, Query, Filters, RangeStart, RangeEnd) ->
	case supervisor:start_child(cse_rest_pagination_sup, [[M, F, A]]) of
		{ok, PageServer, Etag} ->
			query_page(Codec, PageServer, Etag,
					Query, Filters, RangeStart, RangeEnd);
		{error, _Reason} ->
			{error, 500}
	end.

-spec add_resource(RequestBody) -> Result
	when
		RequestBody :: [tuple()],
		Result   :: {ok, Headers, Body} | {error, Status},
		Headers  :: [tuple()],
		Body     :: iolist(),
		Status   :: 400 | 500 .
%% @doc Respond to
%% 	`POST /resourceInventoryManagement/v4/resource'.
%%    Add a new resource in inventory.
add_resource(RequestBody) ->
	try
		{ok, ResMap} = zj:decode(RequestBody),
		resource(ResMap)
	of
		#resource{} = Resource ->
			add_resource1(Resource)
	catch
		_Error:_Reason ->
			{error, 400}
	end.
%% @hidden
add_resource1(#resource{specification
		= #resource_spec_ref{id = ?PREFIX_TABLE_SPEC}} = Resource) ->
	add_resource_prefix_table(Resource);
add_resource1(#resource{specification
		= #resource_spec_ref{id = ?PREFIX_RANGE_TABLE_SPEC}} = Resource) ->
	add_resource_prefix_table(Resource);
add_resource1(#resource{specification
		= #resource_spec_ref{id = ?PREFIX_ROW_SPEC}} = Resource) ->
	add_resource_prefix_row(Resource);
add_resource1(#resource{specification
		= #resource_spec_ref{id = ?PREFIX_RANGE_ROW_SPEC}} = Resource) ->
	add_resource_range_row(Resource);
add_resource1(#resource{specification
		= #resource_spec_ref{id = SpecId}} = Resource) ->
	add_resource2(Resource, cse:find_resource_spec(SpecId)).
%% @hidden
add_resource2(Resource, {ok, #resource_spec{related = Related}}) ->
	add_resource3(Resource, Related);
add_resource2(_Resource, {error, _Reason}) ->
% @todo problem report
	{error, 400}.
%% @hidden
add_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_TABLE_SPEC, rel_type = "based"} | _]) ->
	add_resource_prefix_table(Resource);
add_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_RANGE_TABLE_SPEC, rel_type = "based"} | _]) ->
	add_resource_prefix_table(Resource);
add_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_ROW_SPEC, rel_type = "based"} | _]) ->
	add_resource_prefix_row(Resource);
add_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_RANGE_ROW_SPEC, rel_type = "based"} | _]) ->
	add_resource_range_row(Resource);
add_resource3(Resource, [_ | T]) ->
	add_resource3(Resource, T);
add_resource3(Resource, []) ->
	add_resource_result(cse:add_resource(Resource)).

%% @hidden
add_resource_prefix_table(#resource{name = Name} = Resource) ->
	F = fun F(eof, Acc) ->
				lists:flatten(Acc);
			F(Cont1, Acc) ->
				{Cont2, L} = cse:query_resource(Cont1, {exact, Name},
						{exact, ?PREFIX_TABLE_SPEC}, '_', '_', '_'),
				F(Cont2, [L | Acc])
	end,
	case F(start, []) of
		[] ->
			add_resource_result(cse:add_resource(Resource));
		[#resource{} | _] ->
			{error, 400}
	end.

%% @hidden
add_resource_prefix_row(#resource{related = Related} = Resource) ->
	case maps:find("contained", Related) of
		{ok, #resource_rel{rel_type = "contained",
				resource = #resource_ref{name = Table}}} ->
			add_resource_prefix_row(Table, Resource);
		error ->
			{error, 400}
	end.
%% @hidden
add_resource_prefix_row(Table,
		#resource{characteristic = Chars} = Resource) ->
	{Prefix, Value} = case maps:find("prefix", Chars) of
		{ok, #characteristic{name = "prefix", value = P}} ->
			case maps:find("value", Chars) of
				{ok, #characteristic{name = "value", value = V}} ->
					{P, V};
				error ->
					{error, 400}
			end;
		error ->
			{error, 400}
	end,
	case cse_gtt:insert(Table, Prefix, Value) of
		{ok, #gtt{}} ->
			add_resource_result(cse:add_resource(Resource));
		{error, already_exists} ->
			{error, 409};
		{error, _Reason} ->
			{error, 400}
	end.

%% @hidden
add_resource_range_row(#resource{related = Related} = Resource) ->
	case maps:find("contained", Related) of
		{ok, #resource_rel{rel_type = "contained",
				resource = #resource_ref{name = Table}}} ->
			add_resource_range_row(Table, Resource);
		error ->
			{error, 400}
	end.
%% @hidden
add_resource_range_row(Table,
		#resource{characteristic = Chars} = Resource) ->
	{Start, End, Value} = case maps:find("start", Chars) of
		{ok, #characteristic{name = "start", value = S}} ->
			case maps:find("end", Chars) of
				{ok, #characteristic{name = "end", value = E}} ->
					case maps:find("value", Chars) of
						{ok, #characteristic{name = "value", value = V}} ->
							{S, E, V};
						error ->
							{error, 400}
					end;
				error ->
					{error, 400}
			end;
		error ->
			{error, 400}
	end,
	case cse_gtt:add_range(Table, Start, End, Value) of
		ok ->
			add_resource_result(cse:add_resource(Resource));
		{error, conflict} ->
			{error, 409}
	end.

%% @hidden
add_resource_result({ok, #resource{href = Href, last_modified = LM} = Resource}) ->
	Headers = [{content_type, "application/json"},
			{location, Href}, {etag, cse_rest:etag(LM)}],
	Body = zj:encode(resource(Resource)),
	{ok, Headers, Body};
add_resource_result({error, _Reason}) ->
% @todo problem report
	{error, 400}.

-spec delete_resource(Id, Query) -> Result
   when
      Id :: string(),
		Query :: [{unicode:chardata(), unicode:chardata() | true}],
      Result :: {ok, Headers :: [tuple()], Body :: iolist()}
            | {error, ErrorCode :: integer()} .
%% @doc Respond to `DELETE /resourceInventoryManagement/v4/resource/{id}''
%%    request to remove a table row.
%%
%% 	A `Query' may be used on the Collection path to select the
%% 	resource when `id' is empty.
%%
delete_resource(Id, []) ->
	try
		delete_resource1(cse:find_resource(Id))
	catch
		_Class:_Reason:_Stack ->
			{error, 400}
	end;
delete_resource([], Query) ->
	try
		{Query1, MatchSpecId} = get_param("resourceSpecification.id", Query, '_'),
		{_Query2, Filters} = get_filters(Query1),
		case match_filters("resourceCharacteristic", Filters) of
			{ok, {exact, CharName}, {exact, CharValue}} ->
				MatchChars = [{{exact, CharName}, {exact, CharValue}}],
				delete_resource1(delete_resource_query(start, MatchSpecId, MatchChars));
			{ok, _, _} ->
				throw(400);
			{error, not_found} ->
				throw(404)
		end
	catch
		throw:Reason->
			{error, Reason};
		_Class:_Reason ->
			{error, 400}
	end.
%% @hidden
delete_resource1({ok, #resource{id = Id, specification
		= #resource_spec_ref{id = ?PREFIX_TABLE_SPEC}}}) ->
	delete_resource_result(cse:delete_resource(Id));
delete_resource1({ok, #resource{id = Id, specification
		= #resource_spec_ref{id = ?PREFIX_RANGE_TABLE_SPEC}}}) ->
	delete_resource_result(cse:delete_resource(Id));
delete_resource1({ok, #resource{specification
		= #resource_spec_ref{id = ?PREFIX_ROW_SPEC}} = Resource}) ->
	delete_resource_row(?PREFIX_ROW_SPEC, Resource);
delete_resource1({ok, #resource{specification
		= #resource_spec_ref{id = ?PREFIX_RANGE_ROW_SPEC}} = Resource}) ->
	delete_resource_row(?PREFIX_RANGE_ROW_SPEC, Resource);
delete_resource1({ok, #resource{specification
		= #resource_spec_ref{id = SpecId}} = Resource}) ->
	delete_resource2(Resource, cse:find_resource_spec(SpecId));
delete_resource1({error, not_found}) ->
	{error, 404};
delete_resource1({error, Reason}) ->
	{error, Reason}.
%% @hidden
delete_resource2(Resource, {ok, #resource_spec{related = Related}}) ->
	delete_resource3(Resource, Related);
delete_resource2(_Resource, {error, Reason}) ->
	{error, Reason}.
%%  @hidden
delete_resource3(#resource{id = Id},
		[#resource_spec_rel{id = ?PREFIX_TABLE_SPEC, rel_type = "based"} | _]) ->
	delete_resource_result(cse:delete_resource(Id));
delete_resource3(#resource{id = Id},
		[#resource_spec_rel{id = ?PREFIX_RANGE_TABLE_SPEC, rel_type = "based"} | _]) ->
	delete_resource_result(cse:delete_resource(Id));
delete_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_ROW_SPEC, rel_type = "based"} | _]) ->
	delete_resource_row(?PREFIX_ROW_SPEC, Resource);
delete_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_RANGE_ROW_SPEC, rel_type = "based"} | _]) ->
	delete_resource_row(?PREFIX_RANGE_ROW_SPEC, Resource);
delete_resource3(Resource, [_ | T]) ->
	delete_resource3(Resource, T);
delete_resource3(#resource{id = Id}, []) ->
	delete_resource_result(cse:delete_resource(Id)).

%% @hidden
delete_resource_row(Based,
		#resource{related = #{"contained" := #resource_rel{
		resource = #resource_ref{name = Table}}}} = Resource) ->
	delete_resource_row(Based, Table, Resource);
delete_resource_row(_Based, _Resource) ->
	{error, 400}.
%% @hidden
delete_resource_row(?PREFIX_ROW_SPEC, Table, #resource{id = Id,
		characteristic = #{"prefix" := #characteristic{value = Prefix}}}) ->
	TableName = list_to_existing_atom(Table),
	ok = cse_gtt:delete(TableName, Prefix),
	delete_resource_result(cse:delete_resource(Id));
delete_resource_row(?PREFIX_RANGE_ROW_SPEC, Table, #resource{id = Id,
		characteristic = #{"start" := #characteristic{value = Start},
		"end" := #characteristic{value = End}}}) ->
	TableName = list_to_existing_atom(Table),
	ok = cse_gtt:delete_range(TableName, Start, End),
	delete_resource_result(cse:delete_resource(Id));
delete_resource_row(_Based, _Table, _Resource) ->
	{error, 400}.

%% @hidden
delete_resource_query(Cont, {exact, SpecId} = MatchSpecId, MatchChars)
		when is_list(SpecId), is_list(MatchChars) ->
	case cse:query_resource(Cont, '_', MatchSpecId, '_', '_', MatchChars) of
		{_, [#resource{} = Resource]} ->
			{ok, Resource};
		{eof, []} ->
			{error, 404};
		{error, _Reason} ->
			{error, 500};
		{Cont1, []} ->
			delete_resource_query(Cont1, MatchSpecId, MatchChars)
	end;
delete_resource_query(_Cont, _, _) ->
	{error, 400}.

%% @hidden
delete_resource_result(ok) ->
	{ok, [], []};
delete_resource_result({error, _Reason}) ->
	{error, 400}.

%%----------------------------------------------------------------------
%%  cse_rest_res_resource private API functions
%%----------------------------------------------------------------------

-spec prefix_table_spec_id() -> SpecId
	when
		SpecId :: string().
%% @doc Get the identifier of the prefix table Resource Specification.
%% @private
prefix_table_spec_id() ->
	?PREFIX_TABLE_SPEC.

-spec prefix_row_spec_id() -> SpecId
	when
		SpecId :: string().
%% @doc Get the identifier of the prefix row Resource Specification.
%% @private
prefix_row_spec_id() ->
	?PREFIX_ROW_SPEC.

-spec prefix_range_table_spec_id() -> SpecId
	when
		SpecId :: string().
%% @doc Get the identifier of the prefix range table Resource Specification.
%% @private
prefix_range_table_spec_id() ->
	?PREFIX_RANGE_TABLE_SPEC.

-spec prefix_range_row_spec_id() -> SpecId
	when
		SpecId :: string().
%% @doc Get the identifier of the prefix range row Resource Specification.
%% @private
prefix_range_row_spec_id() ->
	?PREFIX_RANGE_ROW_SPEC.

-spec static_spec(SpecId) -> Specification
	when
		SpecId :: string(),
		Specification :: #resource_spec{}.
%% @doc Get a statically defined Resource Specification.
%% @private
static_spec(?PREFIX_TABLE_SPEC = SpecId) ->
	[TS, N] = string:split(SpecId, "-"),
	LM = {list_to_integer(TS), list_to_integer(N)},
	#resource_spec{id = SpecId,
		href = ?specPath ++ SpecId,
		name = "PrefixTable",
		description = "Prefix table specification",
		version = "1.0",
		last_modified = LM,
		category = "PrefixTable"
	};
static_spec(?PREFIX_ROW_SPEC = SpecId) ->
	[TS, N] = string:split(SpecId, "-"),
	LM = {list_to_integer(TS), list_to_integer(N)},
	#resource_spec{id = SpecId,
		href = ?specPath ++ SpecId,
		name = "PrefixRow",
		description = "Prefix table row specification",
		version = "1.1",
		last_modified = LM,
		category = "PrefixRow",
		related = [#resource_spec_rel{id = ?PREFIX_TABLE_SPEC,
				href = ?specPath ++ ?PREFIX_TABLE_SPEC,
				name = "PrefixTable",
				rel_type = "contained"}],
		characteristic = [#resource_spec_char{name = "prefix",
				description = "Prefix to match",
				value_type = "String"},
			#resource_spec_char{name = "value",
				description = "Value returned from prefix match"}]
	};
static_spec(?PREFIX_RANGE_TABLE_SPEC = SpecId) ->
	[TS, N] = string:split(SpecId, "-"),
	LM = {list_to_integer(TS), list_to_integer(N)},
	#resource_spec{id = SpecId,
		href = ?specPath ++ SpecId,
		name = "PrefixRangeTable",
		description = "Prefix range table specification",
		version = "1.0",
		last_modified = LM,
		category = "PrefixTable",
		related = [#resource_spec_rel{id = ?PREFIX_TABLE_SPEC,
				href = ?specPath ++ ?PREFIX_TABLE_SPEC,
				name = "PrefixTable",
				rel_type = "based"}]
	};
static_spec(?PREFIX_RANGE_ROW_SPEC = SpecId) ->
	[TS, N] = string:split(SpecId, "-"),
	LM = {list_to_integer(TS), list_to_integer(N)},
	#resource_spec{id = SpecId,
		href = ?specPath ++ SpecId,
		name = "PrefixRangeRow",
		description = "Prefix range table row specification",
		version = "1.0",
		last_modified = LM,
		category = "PrefixRow",
		related = [#resource_spec_rel{id = ?PREFIX_ROW_SPEC,
				href = ?specPath ++ ?PREFIX_ROW_SPEC,
				name = "PrefixRow",
				rel_type = "based"},
			#resource_spec_rel{id = ?PREFIX_RANGE_TABLE_SPEC,
				href = ?specPath ++ ?PREFIX_RANGE_TABLE_SPEC,
				name = "PrefixRangeTable",
				rel_type = "contained"}],
		characteristic = [#resource_spec_char{name = "start",
				description = "Start of prefix range",
				value_type = "String"},
			#resource_spec_char{name = "end",
				description = "End of prefix range",
				value_type = "String"},
			#resource_spec_char{name = "value",
				description = "Description of prefix range"}]
	}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec gtt(Table, Gtt) -> Gtt
	when
		Table :: string(),
		Gtt :: {Prefix, Value} | map(),
		Prefix :: string(),
		Value :: term().
%% @doc CODEC for gtt.
%% @private
gtt(Table, {Prefix, Value} = _Gtt) ->
	Id = Table ++ "-" ++ Prefix,
	Specification = ?PREFIX_ROW_SPEC,
	#{"id" => Id, "href" => ?inventoryPath ++ Id,
			"resourceSpecification" => #{"id" => Specification,
					"href" => ?specPath ++ Specification,
					"name" => "PrefixTableRow"},
			"resourceCharacteristic" => [
					#{"name" => "prefix", "value" => Prefix},
					#{"name" => "value", "value" => Value}]}.

-spec resource(Resource) -> Resource
	when
		Resource :: resource() | map().
%% @doc CODEC for `Resource'.
resource(#resource{} = Resource) ->
	resource(record_info(fields, resource), Resource, #{});
resource(#{} = Resource) ->
	resource(record_info(fields, resource), Resource, #resource{}).
%% @hidden
resource([id | T], #resource{id = Id} = R, Acc)
		when is_list(Id) ->
	resource(T, R, Acc#{"id" => Id});
resource([id | T], #{"id" := Id} = M, Acc)
		when is_list(Id) ->
	resource(T, M, Acc#resource{id = Id});
resource([href | T], #resource{href = Href} = R, Acc)
		when is_list(Href) ->
	resource(T, R, Acc#{"href" => Href});
resource([href | T], #{"href" := Href} = M, Acc)
		when is_list(Href) ->
	resource(T, M, Acc#resource{href = Href});
resource([name | T], #resource{name = Name} = R, Acc)
		when is_list(Name) ->
	resource(T, R, Acc#{"name" => Name});
resource([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	resource(T, M, Acc#resource{name = Name});
resource([description | T],
		#resource{description = Description} = R, Acc)
		when is_list(Description) ->
	resource(T, R, Acc#{"description" => Description});
resource([description | T], #{"description" := Description} = M, Acc)
		when is_list(Description) ->
	resource(T, M, Acc#resource{description = Description});
resource([category | T], #resource{category = Category} = R, Acc)
		when is_list(Category) ->
	resource(T, R, Acc#{"category" => Category});
resource([category | T], #{"category" := Category} = M, Acc)
		when is_list(Category) ->
	resource(T, M, Acc#resource{category = Category});
resource([class_type | T], #resource{class_type = Type} = R, Acc)
		when is_list(Type) ->
	resource(T, R, Acc#{"@type" => Type});
resource([class_type | T], #{"@type" := Type} = M, Acc)
		when is_list(Type) ->
	resource(T, M, Acc#resource{class_type = Type});
resource([base_type | T], #resource{base_type = Type} = R, Acc)
		when is_list(Type) ->
	resource(T, R, Acc#{"@baseType" => Type});
resource([base_type | T], #{"@baseType" := Type} = M, Acc)
		when is_list(Type) ->
	resource(T, M, Acc#resource{base_type = Type});
resource([schema | T], #resource{schema = Schema} = R, Acc)
		when is_list(Schema) ->
	resource(T, R, Acc#{"@schemaLocation" => Schema});
resource([schema | T], #{"@schemaLocation" := Schema} = M, Acc)
		when is_list(Schema) ->
	resource(T, M, Acc#resource{schema = Schema});
resource([version | T], #resource{version = Version} = R, Acc)
		when is_list(Version) ->
	resource(T, R, Acc#{"version" => Version});
resource([version | T], #{"version" := Version} = M, Acc)
		when is_list(Version) ->
	resource(T, M, Acc#resource{version = Version});
resource([start_date | T], #resource{start_date = StartDate} = R, Acc)
		when is_integer(StartDate) ->
	ValidFor = #{"startDateTime" => cse_rest:iso8601(StartDate)},
	resource(T, R, Acc#{"validFor" => ValidFor});
resource([start_date | T],
		#{"validFor" := #{"startDateTime" := Start}} = M, Acc)
		when is_list(Start) ->
	resource(T, M, Acc#resource{start_date = cse_rest:iso8601(Start)});
resource([end_date | T], #resource{end_date = End} = R,
		#{"validFor" := ValidFor} = Acc) when is_integer(End) ->
	NewValidFor = ValidFor#{"endDateTime" => cse_rest:iso8601(End)},
	resource(T, R, Acc#{"validFor" := NewValidFor});
resource([end_date | T], #resource{end_date = End} = R, Acc)
		when is_integer(End) ->
	ValidFor = #{"endDateTime" => cse_rest:iso8601(End)},
	resource(T, R, Acc#{"validFor" := ValidFor});
resource([end_date | T],
		#{"validFor" := #{"endDateTime" := End}} = M, Acc)
		when is_list(End) ->
	resource(T, M, Acc#resource{end_date = cse_rest:iso8601(End)});
resource([last_modified | T], #resource{last_modified = {TS, _}} = R, Acc)
		when is_integer(TS) ->
	resource(T, R, Acc#{"lastUpdate" => cse_rest:iso8601(TS)});
resource([last_modified | T], #{"lastUpdate" := DateTime} = M, Acc)
		when is_list(DateTime) ->
	LM = {cse_rest:iso8601(DateTime), erlang:unique_integer([positive])},
	resource(T, M, Acc#resource{last_modified = LM});
resource([admin_state | T], #resource{admin_state = State} = R, Acc)
		when State /= undefined ->
	resource(T, R, Acc#{"administrativeState" => State});
resource([admin_state | T], #{"administrativeState" := State} = M, Acc)
		when is_list(State) ->
	resource(T, M, Acc#resource{admin_state = State});
resource([oper_state | T], #resource{oper_state = State} = R, Acc)
		when State /= undefined ->
	resource(T, R, Acc#{"operationalState" => State});
resource([oper_state | T], #{"operationalState" := State} = M, Acc)
		when is_list(State) ->
	resource(T, M, Acc#resource{oper_state = State});
resource([usage_state | T], #resource{usage_state = State} = R, Acc)
		when State /= undefined ->
	resource(T, R, Acc#{"usageState" => State});
resource([usage_state | T], #{"usageState" := State} = M, Acc)
		when is_list(State) ->
	resource(T, M, Acc#resource{usage_state = State});
resource([related | T], #resource{related = ResRel} = R, Acc)
		when is_map(ResRel), map_size(ResRel) > 0 ->
	resource(T, R, Acc#{"resourceRelationship" => resource_rel(ResRel)});
resource([related | T], #{"resourceRelationship" := ResRel} = M, Acc)
		when is_list(ResRel) ->
	resource(T, M, Acc#resource{related = resource_rel(ResRel)});
resource([specification | T], #resource{specification = SpecRef} = R, Acc)
		when is_record(SpecRef, resource_spec_ref) ->
	resource(T, R, Acc#{"resourceSpecification" => resource_spec_ref(SpecRef)});
resource([specification | T], #{"resourceSpecification" := SpecRef} = M, Acc)
		when is_map(SpecRef) ->
	resource(T, M, Acc#resource{specification = resource_spec_ref(SpecRef)});
resource([characteristic | T], #resource{characteristic = ResChar} = R, Acc)
		when is_map(ResChar), map_size(ResChar) > 0 ->
	resource(T, R, Acc#{"resourceCharacteristic" => characteristic(ResChar)});
resource([characteristic | T], #{"resourceCharacteristic" := ResChar} = M, Acc)
		when is_list(ResChar) ->
	resource(T, M, Acc#resource{characteristic = characteristic(ResChar)});
resource([_ | T], R, Acc) ->
	resource(T, R, Acc);
resource([], _, Acc) ->
	Acc.

-spec resource_rel(ResourceRelationship) -> ResourceRelationship
	when
		ResourceRelationship :: map() | [map()].
%% @doc CODEC for `ResourceRelationship'.
resource_rel(#{} = ResourceRelationship) ->
	Fields = record_info(fields, resource_rel),
	[resource_rel(Fields, R, #{})
			|| R <- maps:values(ResourceRelationship)];
resource_rel([#{} | _] = ResourceRelationship) ->
	Fields = record_info(fields, resource_rel),
	Records = [resource_rel(Fields, M, #resource_rel{})
			|| M <- ResourceRelationship],
	maps:from_list([{R#resource_rel.rel_type, R} || R <- Records]);
resource_rel([]) ->
	#{}.
%% @hidden
resource_rel([rel_type | T], #resource_rel{rel_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_rel(T, R, Acc#{"relationshipType" => Type});
resource_rel([rel_type | T], #{"relationshipType" := Type} = M,
		Acc) when is_list(Type) ->
	resource_rel(T, M, Acc#resource_rel{rel_type = Type});
resource_rel([resource | T], #resource_rel{resource = ResourceRef} = R,
		Acc) when is_record(ResourceRef, resource_ref) ->
	resource_rel(T, R, Acc#{"resource" => resource_ref(ResourceRef)});
resource_rel([resource | T], #{"resource" := ResourceRef} = M,
		Acc) when is_map(ResourceRef) ->
	resource_rel(T, M, Acc#resource_rel{resource = resource_ref(ResourceRef)});
resource_rel([class_type | T], #resource_rel{class_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_rel(T, R, Acc#{"@type" => Type});
resource_rel([class_type | T], #{"@type" := Type} = M,
		Acc) when is_list(Type) ->
	resource_rel(T, M, Acc#resource_rel{class_type = Type});
resource_rel([base_type | T], #resource_rel{base_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_rel(T, R, Acc#{"@baseType" => Type});
resource_rel([base_type | T], #{"@baseType" := Type} = M,
		Acc) when is_list(Type) ->
	resource_rel(T, M, Acc#resource_rel{base_type = Type});
resource_rel([schema | T], #resource_rel{schema = Schema} = R,
		Acc) when is_list(Schema) ->
	resource_rel(T, R, Acc#{"@schemaLocation" => Schema});
resource_rel([schema | T], #{"@schemaLocation" := Schema} = M,
		Acc) when is_list(Schema) ->
	resource_rel(T, M, Acc#resource_rel{schema = Schema});
resource_rel([_ | T], R, Acc) ->
	resource_rel(T, R, Acc);
resource_rel([], _, Acc) ->
	Acc.

-spec resource_ref(ResourceRef) -> ResourceRef
	when
		ResourceRef :: #resource_ref{} | map().
%% @doc CODEC for `ResourceRef'.
resource_ref(#{} = ResourceRef) ->
	Fields = record_info(fields, resource_ref),
	resource_ref(Fields, ResourceRef, #resource_ref{});
resource_ref(#resource_ref{} = ResourceRef) ->
	Fields = record_info(fields, resource_ref),
	resource_ref(Fields, ResourceRef, #{}).
%% @hidden
resource_ref([id | T], #resource_ref{id = Id} = R,
		Acc) when is_list(Id) ->
	resource_ref(T, R, Acc#{"id" => Id});
resource_ref([id | T], #{"id" := Id} = M,
		Acc) when is_list(Id) ->
	resource_ref(T, M, Acc#resource_ref{id = Id});
resource_ref([href | T], #resource_ref{href = Href} = R,
		Acc) when is_list(Href) ->
	resource_ref(T, R, Acc#{"href" => Href});
resource_ref([href | T], #{"href" := Href} = M,
		Acc) when is_list(Href) ->
	resource_ref(T, M, Acc#resource_ref{href = Href});
resource_ref([name | T], #resource_ref{name = Name} = R,
		Acc) when is_list(Name) ->
	resource_ref(T, R, Acc#{"name" => Name});
resource_ref([name | T], #{"name" := Name} = M,
		Acc) when is_list(Name) ->
	resource_ref(T, M, Acc#resource_ref{name = Name});
resource_ref([ref_type | T], #resource_ref{ref_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_ref(T, R, Acc#{"@referredType" => Type});
resource_ref([name | T], #{"@referredType" := Type} = M,
		Acc) when is_list(Type) ->
	resource_ref(T, M, Acc#resource_ref{ref_type = Type});
resource_ref([class_type | T], #resource_ref{class_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_ref(T, R, Acc#{"@type" => Type});
resource_ref([class_type | T], #{"@type" := Type} = M,
		Acc) when is_list(Type) ->
	resource_ref(T, M, Acc#resource_ref{class_type = Type});
resource_ref([base_type | T], #resource_ref{base_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_ref(T, R, Acc#{"@baseType" => Type});
resource_ref([base_type | T], #{"@baseType" := Type} = M,
		Acc) when is_list(Type) ->
	resource_ref(T, M, Acc#resource_ref{base_type = Type});
resource_ref([schema | T], #resource_ref{schema = Schema} = R,
		Acc) when is_list(Schema) ->
	resource_ref(T, R, Acc#{"@schemaLocation" => Schema});
resource_ref([schema | T], #{"@schemaLocation" := Schema} = M,
		Acc) when is_list(Schema) ->
	resource_ref(T, M, Acc#resource_ref{schema = Schema});
resource_ref([_| T], R, Acc) ->
	resource_ref(T, R, Acc);
resource_ref([], _, Acc) ->
	Acc.

-spec characteristic(Characteristics) -> Characteristics
	when
		Characteristics :: characteristics() | [map()].
%% @doc CODEC for `Characteristic'.
characteristic(#{} = Characteristics) ->
	Fields = record_info(fields, characteristic),
	[characteristic(Fields, R, #{})
			|| R <- maps:values(Characteristics)];
characteristic([#{} | _] = Characteristics) ->
	Fields = record_info(fields, characteristic),
	Records = [characteristic(Fields, M, #characteristic{})
			|| M <- Characteristics],
	maps:from_list([{R#characteristic.name, R} || R <- Records]);
characteristic([]) ->
	#{}.
%% @hidden
characteristic([id | T], #characteristic{id = Id} = R, Acc)
		when is_list(Id) ->
	characteristic(T, R, Acc#{"id" => Id});
characteristic([id | T], #{"id" := Id} = R, Acc)
		when is_list(Id) ->
	characteristic(T, R, Acc#characteristic{id = Id});
characteristic([name | T], #characteristic{name = Name} = R, Acc)
		when is_list(Name) ->
	characteristic(T, R, Acc#{"name" => Name});
characteristic([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	characteristic(T, M, Acc#characteristic{name = Name});
characteristic([class_type | T], #characteristic{class_type = Type} = R, Acc)
		when is_list(Type) ->
	characteristic(T, R, Acc#{"@type" => Type});
characteristic([class_type | T], #{"@type" := Type} = M, Acc)
		when is_list(Type) ->
	characteristic(T, M, Acc#characteristic{class_type = Type});
characteristic([base_type | T], #characteristic{base_type = Type} = R, Acc)
		when is_list(Type) ->
	characteristic(T, R, Acc#{"@baseType" => Type});
characteristic([base_type | T], #{"@baseType" := Type} = M, Acc)
		when is_list(Type) ->
	characteristic(T, M, Acc#characteristic{base_type = Type});
characteristic([schema | T], #characteristic{schema = Schema} = R, Acc)
		when is_list(Schema) ->
	characteristic(T, R, Acc#{"@schemaLocation" => Schema});
characteristic([schema | T], #{"@schemaLocation" := Schema} = M, Acc)
		when is_list(Schema) ->
	characteristic(T, M, Acc#characteristic{schema = Schema});
characteristic([value_type | T], #characteristic{value_type = Type} = R, Acc)
		when is_list(Type) ->
	characteristic(T, R, Acc#{"valueType" => Type});
characteristic([base_type | T], #{"valueType" := Type} = M, Acc)
		when is_list(Type) ->
	characteristic(T, M, Acc#characteristic{value_type = Type});
characteristic([value | T], #characteristic{value = Value} = R, Acc) ->
	characteristic(T, R, Acc#{"value" => Value});
characteristic([value | T], #{"value" := Value} = M, Acc) ->
	characteristic(T, M, Acc#characteristic{value = Value});
characteristic([_ | T], R, Acc) ->
	characteristic(T, R, Acc);
characteristic([], _, Acc) ->
	Acc.

-spec resource_spec_ref(ResourceSpecificationRef) -> ResourceSpecificationRef
	when
		ResourceSpecificationRef :: [resource_spec_ref()] | [map()]
				| resource_spec_ref() | map().
%% @doc CODEC for `ResourceSpecificationRef'.
resource_spec_ref(#resource_spec_ref{} = ResourceSpecificationRef) ->
	resource_spec_ref(record_info(fields, resource_spec_ref),
			ResourceSpecificationRef, #{});
resource_spec_ref(#{} = ResourceSpecificationRef) ->
	resource_spec_ref(record_info(fields, resource_spec_ref),
			ResourceSpecificationRef, #resource_spec_ref{}).
%% @hidden
resource_spec_ref([id | T], #resource_spec_ref{id = Id} = R, Acc)
		when is_list(Id) ->
	resource_spec_ref(T, R, Acc#{"id" => Id});
resource_spec_ref([id | T], #{"id" := Id} = M, Acc)
		when is_list(Id) ->
	resource_spec_ref(T, M, Acc#resource_spec_ref{id = Id});
resource_spec_ref([href | T], #resource_spec_ref{href = Href} = R, Acc)
		when is_list(Href) ->
	resource_spec_ref(T, R, Acc#{"href" => Href});
resource_spec_ref([href | T], #{"href" := Href} = M, Acc)
		when is_list(Href) ->
	resource_spec_ref(T, M, Acc#resource_spec_ref{href = Href});
resource_spec_ref([name | T], #resource_spec_ref{name = Name} = R, Acc)
		when is_list(Name) ->
	resource_spec_ref(T, R, Acc#{"name" => Name});
resource_spec_ref([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	resource_spec_ref(T, M, Acc#resource_spec_ref{name = Name});
resource_spec_ref([version | T], #resource_spec_ref{version = Version} = R, Acc)
		when is_list(Version) ->
	resource_spec_ref(T, R, Acc#{"version" => Version});
resource_spec_ref([version | T], #{"version" := Version} = M, Acc)
		when is_list(Version) ->
	resource_spec_ref(T, M, Acc#resource_spec_ref{version = Version});
resource_spec_ref([_ | T], R, Acc) ->
	resource_spec_ref(T, R, Acc);
resource_spec_ref([], _, Acc) ->
	Acc.

-spec resource_spec(ResourceSpecification) -> ResourceSpecification
	when
		ResourceSpecification :: resource_spec() | map().
%% @doc CODEC for `ResourceSpecification'.
resource_spec(#resource_spec{} = ResourceSpecification) ->
	resource_spec(record_info(fields, resource_spec), ResourceSpecification, #{});
resource_spec(#{} = ResourceSpecification) ->
	resource_spec(record_info(fields, resource_spec),
			ResourceSpecification, #resource_spec{}).
%% @hidden
resource_spec([id | T], #resource_spec{id = Id} = R, Acc)
		when is_list(Id) ->
	resource_spec(T, R, Acc#{"id" => Id});
resource_spec([id | T], #{"id" := Id} = M, Acc)
		when is_list(Id) ->
	resource_spec(T, M, Acc#resource_spec{id = Id});
resource_spec([href | T], #resource_spec{href = Href} = R, Acc)
		when is_list(Href) ->
	resource_spec(T, R, Acc#{"href" => Href});
resource_spec([href | T], #{"href" := Href} = M, Acc)
		when is_list(Href) ->
	resource_spec(T, M, Acc#resource_spec{href = Href});
resource_spec([name | T], #resource_spec{name = Name} = R, Acc)
		when is_list(Name) ->
	resource_spec(T, R, Acc#{"name" => Name});
resource_spec([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	resource_spec(T, M, Acc#resource_spec{name = Name});
resource_spec([description | T],
		#resource_spec{description = Description} = R, Acc)
		when is_list(Description) ->
	resource_spec(T, R, Acc#{"description" => Description});
resource_spec([description | T], #{"description" := Description} = M, Acc)
		when is_list(Description) ->
	resource_spec(T, M, Acc#resource_spec{description = Description});
resource_spec([category | T], #resource_spec{category = Category} = R,
		Acc) when is_list(Category) ->
	resource_spec(T, R, Acc#{"category" => Category});
resource_spec([category | T], #{"category" := Category} = M, Acc)
		when is_list(Category) ->
	resource_spec(T, M, Acc#resource_spec{category = Category});
resource_spec([class_type | T], #resource_spec{class_type = Type} = R, Acc)
		when is_list(Type) ->
	resource_spec(T, R, Acc#{"@type" => Type});
resource_spec([class_type | T], #{"@type" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec(T, M, Acc#resource_spec{class_type = Type});
resource_spec([base_type | T], #resource_spec{base_type = Type} = R, Acc)
		when is_list(Type) ->
	resource_spec(T, R, Acc#{"@baseType" => Type});
resource_spec([base_type | T], #{"@baseType" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec(T, M, Acc#resource_spec{base_type = Type});
resource_spec([schema | T], #resource_spec{schema = Schema} = R, Acc)
		when is_list(Schema) ->
	resource_spec(T, R, Acc#{"@schemaLocation" => Schema});
resource_spec([schema | T], #{"@schemaLocation" := Schema} = M, Acc)
		when is_list(Schema) ->
	resource_spec(T, M, Acc#resource_spec{schema = Schema});
resource_spec([version | T], #resource_spec{version = Version} = R, Acc)
		when is_list(Version) ->
	resource_spec(T, R, Acc#{"version" => Version});
resource_spec([version | T], #{"version" := Version} = M, Acc)
		when is_list(Version) ->
	resource_spec(T, M, Acc#resource_spec{version = Version});
resource_spec([start_date | T], #resource_spec{start_date = StartDate} = R, Acc)
		when is_integer(StartDate) ->
	ValidFor = #{"startDateTime" => cse_rest:iso8601(StartDate)},
	resource_spec(T, R, Acc#{"validFor" => ValidFor});
resource_spec([start_date | T],
		#{"validFor" := #{"startDateTime" := Start}} = M, Acc)
		when is_list(Start) ->
	resource_spec(T, M, Acc#resource_spec{start_date = cse_rest:iso8601(Start)});
resource_spec([end_date | T], #resource_spec{end_date = End} = R,
		#{"validFor" := ValidFor} = Acc) when is_integer(End) ->
	NewValidFor = ValidFor#{"endDateTime" => cse_rest:iso8601(End)},
	resource_spec(T, R, Acc#{"validFor" := NewValidFor});
resource_spec([end_date | T], #resource_spec{end_date = End} = R, Acc)
		when is_integer(End) ->
	ValidFor = #{"endDateTime" => cse_rest:iso8601(End)},
	resource_spec(T, R, Acc#{"validFor" := ValidFor});
resource_spec([end_date | T],
		#{"validFor" := #{"endDateTime" := End}} = M, Acc)
		when is_list(End) ->
	resource_spec(T, M, Acc#resource_spec{end_date = cse_rest:iso8601(End)});
resource_spec([last_modified | T], #resource_spec{last_modified = {TS, _}} = R,
		Acc) when is_integer(TS) ->
	resource_spec(T, R, Acc#{"lastUpdate" => cse_rest:iso8601(TS)});
resource_spec([last_modified | T], #{"lastUpdate" := DateTime} = M, Acc)
		when is_list(DateTime) ->
	LM = {cse_rest:iso8601(DateTime), erlang:unique_integer([positive])},
	resource_spec(T, M, Acc#resource_spec{last_modified = LM});
resource_spec([is_bundle | T], #resource_spec{is_bundle = Bundle} = R, Acc)
		when is_boolean(Bundle) ->
	resource_spec(T, R, Acc#{"isBundle" => Bundle});
resource_spec([is_bundle | T], #{"isBundle" := Bundle} = M, Acc)
		when is_boolean(Bundle) ->
	resource_spec(T, M, Acc#resource_spec{is_bundle = Bundle});
resource_spec([party | T], #resource_spec{party = PartyRefs} = R, Acc)
		when is_list(PartyRefs), length(PartyRefs) > 0 ->
	resource_spec(T, R, Acc#{"relatedParty" => party_rel(PartyRefs)});
resource_spec([party | T], #{"relatedParty" := PartyRefs} = M, Acc)
		when is_list(PartyRefs) ->
	resource_spec(T, M,
			Acc#resource_spec{party = party_rel(PartyRefs)});
resource_spec([status | T], #resource_spec{status = Status} = R, Acc)
		when is_list(Status) ->
	resource_spec(T, R, Acc#{"lifecycleStatus" => Status});
resource_spec([status | T], #{"lifecycleStatus" := Status} = M, Acc)
		when is_list(Status) ->
	resource_spec(T, M, Acc#resource_spec{status = Status});
resource_spec([related | T], #resource_spec{related = SpecRels} = R, Acc)
		when is_list(SpecRels), length(SpecRels) > 0->
	resource_spec(T, R,
			Acc#{"resourceSpecRelationship" => resource_spec_rel(SpecRels)});
resource_spec([related | T], #{"resourceSpecRelationship" := SpecRels} = M, Acc)
		when is_list(SpecRels) ->
	resource_spec(T, M,
			Acc#resource_spec{related = resource_spec_rel(SpecRels)});
resource_spec([characteristic | T],
		#resource_spec{characteristic = SpecChars} = R, Acc)
		when is_list(SpecChars), length(SpecChars) > 0->
	resource_spec(T, R,
			Acc#{"resourceSpecCharacteristic" => resource_spec_char(SpecChars)});
resource_spec([characteristic | T],
		#{"resourceSpecCharacteristic" := SpecChars} = M, Acc)
		when is_list(SpecChars) ->
	resource_spec(T, M,
			Acc#resource_spec{characteristic = resource_spec_char(SpecChars)});
resource_spec([target_schema | T], #resource_spec{target_schema = TS} = M, Acc)
		when is_record(TS, target_res_schema) ->
	resource_spec(T, M, Acc#{"targetResourceSchema" => target_res_schema(TS)});
resource_spec([target_schema | T], #{"targetResourceSchema" := TS} = M, Acc)
		when is_map(TS) ->
	resource_spec(T, M,
			Acc#resource_spec{target_schema = target_res_schema(TS)});
resource_spec([_ | T], R, Acc) ->
	resource_spec(T, R, Acc);
resource_spec([], _, Acc) ->
	Acc.

-spec resource_spec_rel(ResourceSpecRelationship) -> ResourceSpecRelationship
	when
		ResourceSpecRelationship :: [resource_spec_rel()] | [map()].
%% @doc CODEC for `ResourceSpecRelationship'.
%% @private
resource_spec_rel([#resource_spec_rel{} | _] = List) ->
	Fields = record_info(fields, resource_spec_rel),
	[resource_spec_rel(Fields, R, #{}) || R <- List];
resource_spec_rel([#{} | _] = List) ->
	Fields = record_info(fields, resource_spec_rel),
	[resource_spec_rel(Fields, M, #resource_spec_rel{}) || M <- List];
resource_spec_rel([]) ->
	[].
%% @hidden
resource_spec_rel([id | T], #resource_spec_rel{id = Id} = M, Acc)
		when is_list(Id) ->
	resource_spec_rel(T, M, Acc#{"id" => Id});
resource_spec_rel([id | T], #{"id" := Id} = M, Acc)
		when is_list(Id) ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{id = Id});
resource_spec_rel([href | T], #resource_spec_rel{href = Href} = R, Acc)
		when is_list(Href) ->
	resource_spec_rel(T, R, Acc#{"href" => Href});
resource_spec_rel([href | T], #{"href" := Href} = M, Acc)
		when is_list(Href) ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{href = Href});
resource_spec_rel([name | T], #resource_spec_rel{name = Name} = R, Acc)
		when is_list(Name) ->
	resource_spec_rel(T, R, Acc#{"name" => Name});
resource_spec_rel([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{name = Name});
resource_spec_rel([start_date | T],
		#resource_spec_rel{start_date = StartDate} = R, Acc)
		when is_integer(StartDate) ->
	ValidFor = #{"startDateTime" => cse_rest:iso8601(StartDate)},
	resource_spec_rel(T, R, Acc#{"validFor" => ValidFor});
resource_spec_rel([start_date | T],
		#{"validFor" := #{"startDateTime" := Start}} = M, Acc)
		when is_list(Start) ->
	resource_spec_rel(T, M,
			Acc#resource_spec_rel{start_date = cse_rest:iso8601(Start)});
resource_spec_rel([end_date | T], #resource_spec_rel{end_date = End} = R,
		#{"validFor" := ValidFor} = Acc) when is_integer(End) ->
	NewValidFor = ValidFor#{"endDateTime" => cse_rest:iso8601(End)},
	resource_spec_rel(T, R, Acc#{"validFor" := NewValidFor});
resource_spec_rel([end_date | T], #resource_spec_rel{end_date = End} = R, Acc)
		when is_integer(End) ->
	ValidFor = #{"endDateTime" => cse_rest:iso8601(End)},
	resource_spec_rel(T, R, Acc#{"validFor" := ValidFor});
resource_spec_rel([end_date | T], #{"validFor" := #{"endDateTime" := End}} = M,
		Acc) when is_list(End) ->
	resource_spec_rel(T, M,
			Acc#resource_spec_rel{end_date = cse_rest:iso8601(End)});
resource_spec_rel([rel_type | T], #resource_spec_rel{rel_type = Type} = R, Acc)
		when is_list(Type) ->
	resource_spec_rel(T, R, Acc#{"relationshipType" => Type});
resource_spec_rel([rel_type | T], #{"relationshipType" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{rel_type = Type});
resource_spec_rel([role | T], #resource_spec_rel{role = Role} = R, Acc)
		when is_list(Role) ->
	resource_spec_rel(T, R, Acc#{"role" => Role});
resource_spec_rel([role | T], #{"role" := Role} = M, Acc)
		when is_list(Role) ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{role = Role});
resource_spec_rel([min | T], #resource_spec_rel{min = Min} = R, Acc)
		when is_integer(Min), Min >= 0 ->
	resource_spec_rel(T, R, Acc#{"minimumQuantity" => Min});
resource_spec_rel([min | T], #{"minimumQuantity" := Min} = M, Acc)
		when is_integer(Min), Min >= 0 ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{min = Min});
resource_spec_rel([max | T], #resource_spec_rel{max = Max} = R, Acc)
		when is_integer(Max), Max >= 0 ->
	resource_spec_rel(T, R, Acc#{"maximumQuantity" => Max});
resource_spec_rel([max | T], #{"maximumQuantity" := Max} = M, Acc)
		when is_integer(Max), Max >= 0 ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{max = Max});
resource_spec_rel([default | T], #{"default" := Default} = M, Acc)
		when is_integer(Default), Default >= 0 ->
	resource_spec_rel(T, M, Acc#resource_spec_rel{default = Default});
resource_spec_rel([default | T], #resource_spec_rel{default = Default} = R, Acc)
		when is_integer(Default), Default >= 0 ->
	resource_spec_rel(T, R, Acc#{"default" => Default});
resource_spec_rel([characteristic | T],
		#{"resourceSpecRelCharacteristic" := Chars} = M, Acc)
		when is_list(Chars), length(Chars) > 0 ->
	resource_spec_rel(T, M,
			Acc#resource_spec_rel{characteristic = resource_spec_char(Chars)});
resource_spec_rel([characteristic | T],
		#resource_spec_rel{characteristic = Chars} = R, Acc)
		when is_list(Chars), length(Chars) > 0 ->
	resource_spec_rel(T, R, Acc#{"resourceSpecRelCharacteristic" => Chars});
resource_spec_rel([_ | T], R, Acc) ->
	resource_spec_rel(T, R, Acc);
resource_spec_rel([], _, Acc) ->
	Acc.

-spec resource_spec_char(ResourceSpecCharacteristic) ->
		ResourceSpecCharacteristic
	when
		ResourceSpecCharacteristic :: [resource_spec_char()] | [map()].
%% @doc CODEC for `ResourceSpecCharacteristic'.
%% @private
resource_spec_char([#resource_spec_char{} | _] = List) ->
	Fields = record_info(fields, resource_spec_char),
	[resource_spec_char(Fields, R, #{}) || R <- List];
resource_spec_char([#{} | _] = List) ->
	Fields = record_info(fields, resource_spec_char),
	[resource_spec_char(Fields, M, #resource_spec_char{}) || M <- List];
resource_spec_char([]) ->
	[].
%% @hidden
resource_spec_char([name | T], #resource_spec_char{name = Name} = R, Acc)
		when is_list(Name) ->
	resource_spec_char(T, R, Acc#{"name" => Name});
resource_spec_char([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	resource_spec_char(T, M, Acc#resource_spec_char{name = Name});
resource_spec_char([description | T],
		#resource_spec_char{description = Description} = R, Acc)
		when is_list(Description) ->
	resource_spec_char(T, R, Acc#{"description" => Description});
resource_spec_char([description | T], #{"description" := Description} = M, Acc)
		when is_list(Description) ->
	resource_spec_char(T, M, Acc#resource_spec_char{description = Description});
resource_spec_char([class_type | T], #resource_spec_char{class_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_spec_char(T, R, Acc#{"@type" => Type});
resource_spec_char([class_type | T], #{"@type" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec_char(T, M, Acc#resource_spec_char{class_type = Type});
resource_spec_char([schema | T], #resource_spec_char{schema = Schema} = R, Acc)
		when is_list(Schema) ->
	resource_spec_char(T, R, Acc#{"@schemaLocation" => Schema});
resource_spec_char([schema | T], #{"@schemaLocation" := Schema} = M, Acc)
		when is_list(Schema) ->
	resource_spec_char(T, M, Acc#resource_spec_char{schema = Schema});
resource_spec_char([start_date | T],
		#resource_spec_char{start_date = StartDate} = R, Acc)
		when is_integer(StartDate) ->
	ValidFor = #{"startDateTime" => im_rest:iso8601(StartDate)},
	resource_spec_char(T, R, Acc#{"validFor" => ValidFor});
resource_spec_char([start_date | T],
		#{"validFor" := #{"startDateTime" := Start}} = M, Acc)
		when is_list(Start) ->
	resource_spec_char(T, M,
			Acc#resource_spec_char{start_date = im_rest:iso8601(Start)});
resource_spec_char([end_date | T], #resource_spec_char{end_date = End} = R,
		#{"validFor" := ValidFor} = Acc) when is_integer(End) ->
	NewValidFor = ValidFor#{"endDateTime" => im_rest:iso8601(End)},
	resource_spec_char(T, R, Acc#{"validFor" := NewValidFor});
resource_spec_char([end_date | T], #resource_spec_char{end_date = End} = R, Acc)
		when is_integer(End) ->
	ValidFor = #{"endDateTime" => im_rest:iso8601(End)},
	resource_spec_char(T, R, Acc#{"validFor" := ValidFor});
resource_spec_char([end_date | T],
		#{"validFor" := #{"endDateTime" := End}} = M, Acc)
		when is_list(End) ->
	resource_spec_char(T, M,
			Acc#resource_spec_char{end_date = im_rest:iso8601(End)});
resource_spec_char([configurable | T],
		#resource_spec_char{configurable = Configurable} = R, Acc)
		when is_boolean(Configurable) ->
	resource_spec_char(T, R, Acc#{"configurable" => Configurable});
resource_spec_char([configurable | T], #{"configurable" := Configurable} = M,
		Acc) when is_boolean(Configurable) ->
	resource_spec_char(T, M,
			Acc#resource_spec_char{configurable = Configurable});
resource_spec_char([extensible | T], #resource_spec_char{extensible = Ext} = R,
		Acc) when is_boolean(Ext) ->
	resource_spec_char(T, R, Acc#{"extensible" => Ext});
resource_spec_char([extensible | T], #{"extensible" := Ext} = M, Acc)
		when is_boolean(Ext) ->
	resource_spec_char(T, M, Acc#resource_spec_char{extensible = Ext});
resource_spec_char([is_unique | T], #resource_spec_char{is_unique = Unique} = R,
		Acc) when is_boolean(Unique) ->
	resource_spec_char(T, R, Acc#{"unique" => Unique});
resource_spec_char([is_unique | T], #{"unique" := Unique} = M, Acc)
		when is_boolean(Unique) ->
	resource_spec_char(T, M, Acc#resource_spec_char{is_unique = Unique});
resource_spec_char([min | T], #resource_spec_char{min = Min} = R, Acc)
		when is_integer(Min) ->
	resource_spec_char(T, R, Acc#{"minCardinality" => Min});
resource_spec_char([min | T], #{"minCardinality" := Min} = M, Acc)
		when is_integer(Min) ->
	resource_spec_char(T, M, Acc#resource_spec_char{min = Min});
resource_spec_char([max | T], #resource_spec_char{max = Max} = R, Acc)
		when is_integer(Max) ->
	resource_spec_char(T, R, Acc#{"maxCardinality" => Max});
resource_spec_char([max | T], #{"maxCardinality" := Max} = M, Acc)
		when is_integer(Max) ->
	resource_spec_char(T, M, Acc#resource_spec_char{max = Max});
resource_spec_char([regex | T], #resource_spec_char{regex = RegEx} = R,
		Acc) when is_list(RegEx) ->
	resource_spec_char(T, R, Acc#{"regex" => RegEx});
resource_spec_char([regex | T], #{"regex" := RegEx} = M, Acc)
		when is_list(RegEx) ->
	resource_spec_char(T, M, Acc#resource_spec_char{regex = RegEx});
resource_spec_char([related | T],
		#resource_spec_char{related = CharRels} = R, Acc)
		when is_list(CharRels), length(CharRels) > 0 ->
	resource_spec_char(T, R, Acc#{"resourceSpecCharRelationship"
			=> resource_spec_char_rel(CharRels)});
resource_spec_char([related | T],
		#{"resourceSpecCharRelationship" := CharRels} = M, Acc)
		when is_list(CharRels), length(CharRels) > 0 ->
	resource_spec_char(T, M,
			Acc#resource_spec_char{related = resource_spec_char_rel(CharRels)});
resource_spec_char([value | T], #resource_spec_char{value = CharVals} = R, Acc)
		when is_list(CharVals), length(CharVals) > 0 ->
	resource_spec_char(T, R, Acc#{"resourceSpecCharacteristicValue"
			=> resource_spec_char_val(CharVals)});
resource_spec_char([value | T],
		#{"resourceSpecCharacteristicValue" := CharVals} = M, Acc)
		when is_list(CharVals), length(CharVals) > 0 ->
	resource_spec_char(T, M,
			Acc#resource_spec_char{value = resource_spec_char_val(CharVals)});
resource_spec_char([value_type | T], #resource_spec_char{value_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_spec_char(T, R, Acc#{"valueType" => Type});
resource_spec_char([value_type | T], #{"valueType" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec_char(T, M, Acc#resource_spec_char{value_type = Type});
resource_spec_char([_ | T], R, Acc) ->
	resource_spec_char(T, R, Acc);
resource_spec_char([], _, Acc) ->
	Acc.

-spec resource_spec_char_rel(ResourceSpecCharRelationship) ->
		ResourceSpecCharRelationship
	when
		ResourceSpecCharRelationship :: [resource_spec_char_rel()] | [map()].
%% @doc CODEC for `ResourceSpecCharRelationship'.
%% @private
resource_spec_char_rel([#resource_spec_char_rel{} | _] = List) ->
	Fields = record_info(fields, resource_spec_char_rel),
	[resource_spec_char_rel(Fields, R, #{}) || R <- List];
resource_spec_char_rel([#{} | _] = List) ->
	Fields = record_info(fields, resource_spec_char_rel),
	[resource_spec_char_rel(Fields, M, #resource_spec_char_rel{}) || M <- List];
resource_spec_char_rel([]) ->
	[].
%% @hidden
resource_spec_char_rel([char_id | T],
		#resource_spec_char_rel{char_id = Id} = M, Acc) when is_list(Id) ->
	resource_spec_char_rel(T, M, Acc#{"characteristicSpecificationId" => Id});
resource_spec_char_rel([char_id | T],
		#{"characteristicSpecificationId" := Id} = M, Acc) when is_list(Id) ->
	resource_spec_char_rel(T, M, Acc#resource_spec_char_rel{char_id = Id});
resource_spec_char_rel([name | T], #resource_spec_char_rel{name = Name} = R,
		Acc) when is_list(Name) ->
	resource_spec_char_rel(T, R, Acc#{"name" => Name});
resource_spec_char_rel([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	resource_spec_char_rel(T, M, Acc#resource_spec_char_rel{name = Name});
resource_spec_char_rel([start_date | T],
		#resource_spec_char_rel{start_date = StartDate} = R, Acc)
		when is_integer(StartDate) ->
	ValidFor = #{"startDateTime" => im_rest:iso8601(StartDate)},
	resource_spec_char_rel(T, R, Acc#{"validFor" => ValidFor});
resource_spec_char_rel([start_date | T],
		#{"validFor" := #{"startDateTime" := Start}} = M, Acc)
		when is_list(Start) ->
	resource_spec_char_rel(T, M,
			Acc#resource_spec_char_rel{start_date = im_rest:iso8601(Start)});
resource_spec_char_rel([end_date | T],
		#resource_spec_char_rel{end_date = End} = R,
		#{"validFor" := ValidFor} = Acc) when is_integer(End) ->
	NewValidFor = ValidFor#{"endDateTime" => im_rest:iso8601(End)},
	resource_spec_char_rel(T, R, Acc#{"validFor" := NewValidFor});
resource_spec_char_rel([end_date | T],
		#resource_spec_char_rel{end_date = End} = R, Acc) when is_integer(End) ->
	ValidFor = #{"endDateTime" => im_rest:iso8601(End)},
	resource_spec_char_rel(T, R, Acc#{"validFor" := ValidFor});
resource_spec_char_rel([end_date | T],
		#{"validFor" := #{"endDateTime" := End}} = M, Acc)
		when is_list(End) ->
	resource_spec_char_rel(T, M,
			Acc#resource_spec_char_rel{end_date = im_rest:iso8601(End)});
resource_spec_char_rel([res_spec_id | T],
		#resource_spec_char_rel{res_spec_id = Id} = R, Acc) when is_list(Id) ->
	resource_spec_char_rel(T, R, Acc#{"resourceSpecificationId" => Id});
resource_spec_char_rel([res_spec_id | T],
		#{"resourceSpecificationId" := Id} = M, Acc) when is_list(Id) ->
	resource_spec_char_rel(T, M, Acc#resource_spec_char_rel{res_spec_id = Id});
resource_spec_char_rel([res_spec_href | T],
		#resource_spec_char_rel{res_spec_href = Href} = R, Acc)
		when is_list(Href) ->
	resource_spec_char_rel(T, R, Acc#{"resourceSpecificationHref" => Href});
resource_spec_char_rel([res_spec_href | T],
		#{"resourceSpecificationHref" := Href} = M, Acc) when is_list(Href) ->
	resource_spec_char_rel(T, M,
			Acc#resource_spec_char_rel{res_spec_href = Href});
resource_spec_char_rel([rel_type | T],
		#resource_spec_char_rel{rel_type = Type} = R, Acc)
		when is_list(Type) ->
	resource_spec_char_rel(T, R, Acc#{"relationshipType" => Type});
resource_spec_char_rel([rel_type | T], #{"relationshipType" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec_char_rel(T, M, Acc#resource_spec_char_rel{rel_type = Type});
resource_spec_char_rel([_ | T], R, Acc) ->
	resource_spec_char_rel(T, R, Acc);
resource_spec_char_rel([], _, Acc) ->
	Acc.

-spec resource_spec_char_val(ResourceSpecCharacteristicValue) ->
		ResourceSpecCharacteristicValue
	when
		ResourceSpecCharacteristicValue :: [resource_spec_char_val()] | [map()].
%% @doc CODEC for `ResourceSpecCharacteristicValue'.
%% @private
resource_spec_char_val([#resource_spec_char_val{} | _] = List) ->
	Fields = record_info(fields, resource_spec_char_val),
	[resource_spec_char_val(Fields, R, #{}) || R <- List];
resource_spec_char_val([#{} | _] = List) ->
	Fields = record_info(fields, resource_spec_char_val),
	[resource_spec_char_val(Fields, M, #resource_spec_char_val{}) || M <- List];
resource_spec_char_val([]) ->
	[].
%% @hidden
resource_spec_char_val([is_default | T],
		#resource_spec_char_val{is_default = Default} = R, Acc)
		when is_boolean(Default) ->
	resource_spec_char_val(T, R, Acc#{"isDefault" => Default});
resource_spec_char_val([is_default | T], #{"isDefault" := Default} = M, Acc)
		when is_boolean(Default) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{is_default = Default});
resource_spec_char_val([range_interval | T],
		#resource_spec_char_val{range_interval = Interval} = R, Acc)
		when Interval /= undefined ->
	resource_spec_char_val(T, R, Acc#{"interval" => atom_to_list(Interval)});
resource_spec_char_val([range_interval | T],
		#{"interval" := "closed"} = M, Acc) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{range_interval = closed});
resource_spec_char_val([range_interval | T],
		#{"interval" := "closed_bottom"} = M, Acc) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{range_interval = closed_bottom});
resource_spec_char_val([range_interval | T],
		#{"interval" := "closed_top"} = M, Acc) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{range_interval = closed_top});
resource_spec_char_val([range_interval | T],
		#{"interval" := "open"} = M, Acc) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{range_interval = open});
resource_spec_char_val([regex | T],
		#resource_spec_char_val{regex = RegEx} = R, Acc) when is_list(RegEx) ->
	resource_spec_char_val(T, R, Acc#{"regex" => RegEx});
resource_spec_char_val([regex | T], #{"regex" := RegEx} = M, Acc)
		when is_list(RegEx) ->
	resource_spec_char_val(T, M, Acc#resource_spec_char_val{regex = RegEx});
resource_spec_char_val([unit | T], #resource_spec_char_val{unit = Unit} = R,
		Acc) when is_list(Unit) ->
	resource_spec_char_val(T, R, Acc#{"unitOfMeasure" => Unit});
resource_spec_char_val([unit | T], #{"unitOfMeasure" := Unit} = M, Acc)
		when is_list(Unit) ->
	resource_spec_char_val(T, M, Acc#resource_spec_char_val{unit = Unit});
resource_spec_char_val([start_date | T],
		#resource_spec_char_val{start_date = StartDate} = R, Acc)
		when is_integer(StartDate) ->
	ValidFor = #{"startDateTime" => im_rest:iso8601(StartDate)},
	resource_spec_char_val(T, R, Acc#{"validFor" => ValidFor});
resource_spec_char_val([start_date | T],
		#{"validFor" := #{"startDateTime" := Start}} = M, Acc)
		when is_list(Start) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{start_date = im_rest:iso8601(Start)});
resource_spec_char_val([end_date | T],
		#resource_spec_char_val{end_date = End} = R,
		#{"validFor" := ValidFor} = Acc) when is_integer(End) ->
	NewValidFor = ValidFor#{"endDateTime" => im_rest:iso8601(End)},
	resource_spec_char_val(T, R, Acc#{"validFor" := NewValidFor});
resource_spec_char_val([end_date | T],
		#resource_spec_char_val{end_date = End} = R, Acc) when is_integer(End) ->
	ValidFor = #{"endDateTime" => im_rest:iso8601(End)},
	resource_spec_char_val(T, R, Acc#{"validFor" := ValidFor});
resource_spec_char_val([end_date | T],
		#{"validFor" := #{"endDateTime" := End}} = M, Acc)
		when is_list(End) ->
	resource_spec_char_val(T, M,
			Acc#resource_spec_char_val{end_date = im_rest:iso8601(End)});
resource_spec_char_val([value | T],
		#resource_spec_char_val{value = Value} = R, Acc)
		when Value /= undefined ->
	resource_spec_char_val(T, R, Acc#{"value" => Value});
resource_spec_char_val([value | T], #{"value" := Value} = M, Acc) ->
	resource_spec_char_val(T, M, Acc#resource_spec_char_val{value = Value});
resource_spec_char_val([value_from | T],
		#resource_spec_char_val{value_from = From} = R, Acc)
		when is_integer(From) ->
	resource_spec_char_val(T, R, Acc#{"valueFrom" => From});
resource_spec_char_val([value_from | T], #{"valueFrom" := From} = M, Acc)
		when is_integer(From) ->
	resource_spec_char_val(T, M, Acc#resource_spec_char_val{value_from = From});
resource_spec_char_val([value_to | T],
		#resource_spec_char_val{value_to = To} = R, Acc) when is_integer(To) ->
	resource_spec_char_val(T, R, Acc#{"valueTo" => To});
resource_spec_char_val([value_to | T], #{"valueTo" := To} = M, Acc)
		when is_integer(To) ->
	resource_spec_char_val(T, M, Acc#resource_spec_char_val{value_to = To});
resource_spec_char_val([value_type | T],
		#resource_spec_char_val{value_type = Type} = R, Acc) when is_list(Type) ->
	resource_spec_char_val(T, R, Acc#{"valueType" => Type});
resource_spec_char_val([value_type | T], #{"valueType" := Type} = M, Acc)
		when is_list(Type) ->
	resource_spec_char_val(T, M, Acc#resource_spec_char_val{value_type = Type});
resource_spec_char_val([_ | T], R, Acc) ->
	resource_spec_char_val(T, R, Acc);
resource_spec_char_val([], _, Acc) ->
	Acc.

-spec target_res_schema(TargetSchemaRef) -> TargetSchemaRef
	when
		TargetSchemaRef :: [target_res_schema()] | [map()]
				| target_res_schema() | map().
%% @doc CODEC for `TargetSchemaRef'.
target_res_schema(#target_res_schema{} = TargetSchemaRef) ->
	target_res_schema(record_info(fields, target_res_schema),
			TargetSchemaRef, #{});
target_res_schema(#{} = TargetSchemaRef) ->
	target_res_schema(record_info(fields, target_res_schema),
			TargetSchemaRef, #target_res_schema{}).
%% @hidden
target_res_schema([location | T], #target_res_schema{location = Location} = R,
		Acc) when is_list(Location) ->
	target_res_schema(T, R, Acc#{"@schemaLocation" => Location});
target_res_schema([location | T], #{"@schemaLocation" := Location} = M, Acc)
		when is_list(Location) ->
	target_res_schema(T, M, Acc#target_res_schema{location = Location});
target_res_schema([type | T], #target_res_schema{type = ClassType} = R, Acc)
		when is_list(ClassType) ->
	target_res_schema(T, R, Acc#{"@type" => ClassType});
target_res_schema([type | T], #{"@type" := ClassType} = M, Acc)
		when is_list(ClassType) ->
	target_res_schema(T, M, Acc#target_res_schema{type = ClassType});
target_res_schema([_ | T], R, Acc) ->
	target_res_schema(T, R, Acc);
target_res_schema([], _, Acc) ->
	Acc.

-spec party_rel(RelatedPartyRef) -> RelatedPartyRef
	when
		RelatedPartyRef :: [party_rel()] | [map()]
				| party_rel() | map().
%% @doc CODEC for `RelatedPartyRef'.
party_rel([#party_rel{} | _] = List) ->
	Fields = record_info(fields, party_rel),
	[party_rel(Fields, RP, #{}) || RP <- List];
party_rel([#{} | _] = List) ->
	Fields = record_info(fields, party_rel),
	[party_rel(Fields, RP, #party_rel{}) || RP <- List].
%% @hidden
party_rel([id | T], #party_rel{id = Id} = R, Acc)
		when is_list(Id) ->
	party_rel(T, R, Acc#{"id" => Id});
party_rel([id | T], #{"id" := Id} = M, Acc)
		when is_list(Id) ->
	party_rel(T, M, Acc#party_rel{id = Id});
party_rel([href | T], #party_rel{href = Href} = R, Acc)
		when is_list(Href) ->
	party_rel(T, R, Acc#{"href" => Href});
party_rel([href | T], #{"href" := Href} = M, Acc)
		when is_list(Href) ->
	party_rel(T, M, Acc#party_rel{href = Href});
party_rel([name | T], #party_rel{name = Name} = R, Acc)
		when is_list(Name) ->
	party_rel(T, R, Acc#{"name" => Name});
party_rel([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	party_rel(T, M, Acc#party_rel{name = Name});
party_rel([role | T], #party_rel{role = Role} = R, Acc)
		when is_list(Role) ->
	party_rel(T, R, Acc#{"role" => Role});
party_rel([role | T], #{"role" := Role} = M, Acc)
		when is_list(Role) ->
	party_rel(T, M, Acc#party_rel{role = Role});
party_rel([ref_type | T], #party_rel{ref_type = Type} = R, Acc)
		when is_list(Type) ->
	party_rel(T, R, Acc#{"@referredType" => Type});
party_rel([ref_type | T], #{"@referredType" := Type} = M, Acc)
		when is_list(Type) ->
	party_rel(T, M, Acc#party_rel{ref_type = Type});
party_rel([_ | T], R, Acc) ->
	party_rel(T, R, Acc);
party_rel([], _, Acc) ->
	Acc.

-spec get_param(Key, Query, Default) -> Result
	when
		Key :: string(),
		Query :: [{Key, Value}],
		Default :: '_' | string() | number() | boolean(),
		Value :: string() | number() | boolean(),
		Result :: {Remaining, Match},
		Remaining :: [{Key, Value}],
		Match :: {Operator, Value} | Default,
		Operator :: exact.
%% @doc Take `Key' from `Query'.
%% @hidden
get_param(Key, Query, Default) ->
	case lists:keytake(Key, 1, Query) of
		{value, {_, Value}, Remaining} ->
			{Remaining, {exact, Value}};
		false ->
			{Query,  Default}
	end.

-spec get_child(Element, Children, Default) -> Result
	when
		Path :: [string()],
		Children :: [{filter, Filter}],
		Filter :: {Operator, Element, Operand},
		Operator :: exact,
		Element :: {'@', Path},
		Path :: [string()],
		Operand :: string() | number() | boolean(),
		Default :: '_' | string() | number() | boolean(),
		Result :: Match,
		Match :: {Operator, Value} | Default,
		Operator :: exact,
		Value :: string() | number() | boolean().
%% @doc Take `Element' from `Children'.
%% @hidden
get_child(Element, [{filter, {exact, Element, Value}} | _] = _Children,
		_Default) ->
	{exact, Value};
get_child(Element, [{filter, {'band', {exact, Element, Value}, _}} | _],
		_Default) ->
	{exact, Value};
get_child(Element, [{filter, {'band', _, {exact, Element, Value}}} | _],
		 _Default) ->
	{exact, Value};
get_child(Element, [_H | T], Default) ->
	get_child(Element, T, Default);
get_child(_Element, [], Default) ->
	Default.

-spec get_filters(Query) -> Result
	when
		Query :: [{Key, Value}],
		Key :: string(),
		Value :: string() | number() | boolean(),
		Result :: {Remaining, [Steps]},
		Remaining :: [{Key, Value}],
		Steps :: list().
%% @doc Find all `filter' attributes and gather the `Step' lists.
%% @hidden
get_filters(Query) ->
	get_filters(Query, [], []).
%% @hidden
get_filters([{"filter", String} | T], Acc1, Acc2) ->
	{ok, Tokens, 1} = cse_rest_query_scanner:string(String),
	{ok, {'$', Steps}} = cse_rest_query_parser:parse(Tokens),
	get_filters(T, Acc1, [Steps | Acc2]);
get_filters([H | T], Acc1, Acc2) ->
	get_filters(T, [H | Acc1], Acc2);
get_filters([], Acc1, Acc2) ->
	{lists:reverse(Acc1), lists:reverse(Acc2)}.

-spec match_filters(AttributeName, Steps) -> Result
	when
		AttributeName :: string(),
		Steps :: [Step],
		Step :: [{'.', Children}],
		Children :: list(),
		Result :: {ok, Match, Match} | {ok, Match} | {error, not_found},
		Match :: {exact, Value} | '_',
		Value :: string().
%% @doc Get specific `Match' from `Steps'.
match_filters("resourceSpecRelationship",
		[[{'.', ["resourceSpecRelationship"]},
		{'.', Children}] | _] = _Steps) ->
	MatchRelId = get_child({'@', ["id"]}, Children, '_'),
	MatchRelType = get_child({'@', ["relationshipType"]}, Children, '_'),
	{ok, MatchRelId, MatchRelType};
match_filters("resourceRelationship",
		[[{'.', ["resourceRelationship"]}, {'.', Children}] | _]) ->
	MatchRelType = get_child({'@', ["relationshipType"]}, Children, '_'),
	MatchRelName = get_child({'@', ["resource", "name"]}, Children, '_'),
	{ok, MatchRelType, MatchRelName};
match_filters("resourceCharacteristic",
		[[{'.', ["resourceCharacteristic"]}, {'.', Children}] | _]) ->
	MatchCharName = get_child({'@', ["name"]}, Children, '_'),
	MatchCharValue = get_child({'@', ["value"]}, Children, '_'),
	{ok, MatchCharName, MatchCharValue};
match_filters([_ | T], Steps) ->
	match_filters(T, Steps);
match_filters([], _Steps) ->
	{error, not_found}.

