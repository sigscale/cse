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
-export([get_resource_spec/1, get_resource_specs/1]).
-export([get_resource/1, get_resource/2, add_resource/1, delete_resource/1]).
% export cse_rest_res_resource private API
-export([prefix_table_spec_id/0, prefix_row_spec_id/0, static_spec/1]).

-include("cse.hrl").

-define(specPath, "/resourceCatalogManagement/v4/resourceSpecification/").
-define(inventoryPath, "/resourceInventoryManagement/v1/resource/").

-define(PREFIX_TABLE_SPEC, "1647577955926-50").
-define(PREFIX_ROW_SPEC,   "1647577957914-66").

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
		Result :: {struct, [tuple()]} | {error, 404}.
%% @doc Respond to `GET /resourceCatalogManagement/v4/resourceSpecification/{id}'.
%%		Retrieve a Resource Specification.
get_resource_spec(ID) ->
	case cse:find_resource_spec(ID) of
		{ok, #resource_spec{} = Specification} ->
			Body = zj:encode(Specification),
			Headers = [{content_type, "application/json"}],
			{ok, Headers, Body};
		{error, not_found} ->
			{error, 404};
		{error, _Reason} ->
			{error, 500}
	end.

-spec get_resource_specs(Query) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		Result	:: {ok, Headers, Body} | {error, Status},
		Headers	:: [tuple()],
		Body		:: iolist(),
		Status	:: 400 | 404 | 500.
%% @doc Respond to `GET /resourceCatalogManagement/v4/resourceSpecification'.
%% 	Retrieve all Resource Specifications.
get_resource_specs([] = _Query) ->
	{error, 500};
get_resource_specs(_Query) ->
	{error, 400}.

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
	try
		string:tokens(Id, "-")
	of
		[Table, Prefix] ->
			LM = {erlang:system_time(millisecond),
					erlang:unique_integer([positive])},
			Headers = [{content_type, "application/json"},
					{etag, cse_rest:etag(LM)}],
			Value = cse_gtt:lookup_first(Table, Prefix),
			Body = zj:encode(gtt(Table, {Prefix, Value})),
			{ok, Headers, Body};
		_ ->
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
			end
	catch
		error:badarg ->
			{error, 404};
		_:_Reason1 ->
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
		case lists:keytake("filter", 1, Query) of
			{value, {_, String}, Query1} ->
				{ok, Tokens, _} = cse_rest_query_scanner:string(String),
				case cse_rest_query_parser:parse(Tokens) of
					{ok, [{array, [{complex, Complex}]}]} ->
						MatchId = match("id", Complex, Query),
						MatchCategory = match("category", Complex, Query),
						{Query1, [MatchId, MatchCategory]}
				end;
			false ->
					MatchId = match("id", [], Query),
					MatchCategory = match("category", [], Query),
					MatchSpecId = match("resourceSpecification.id", [], Query),
					MatchRelName
							= match("resourceRelationship.resource.name", [], Query),
					{Query, [MatchId, MatchCategory, MatchSpecId, MatchRelName]}
		end
	of
		{Query2, [_, _, {exact, ?PREFIX_ROW_SPEC}, {exact, Table}]} ->
			Codec = fun gtt/2,
			query_filter({cse_gtt, list, [list_to_existing_atom(Table)]},
					Codec, Query2, Headers);
		{Query2, Args} ->
			Codec = fun resource/1,
			query_filter({cse, query_resource, Args}, Codec, Query2, Headers)
	catch
		_ ->
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
			query_page(Codec, PageServer, Etag, Query, Filters, RangeStart, RangeEnd);
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
%% 	`POST /resourceInventoryManagement/v1/resource'.
%%    Add a new resource in inventory.
add_resource(RequestBody) ->
	try
		{ok, ResMap} = zj:decode(RequestBody),
		resource(ResMap)
	of
		#resource{} = Resource ->
			add_resource1(Resource)
	catch
		_:_Reason ->
			{error, 400}
	end.
%% @hidden
add_resource1(#resource{specification
		= #resource_spec_ref{id = ?PREFIX_TABLE_SPEC}} = Resource) ->
	add_resource_result(add_resource_prefix_table(Resource));
add_resource1(#resource{specification
		= #resource_spec_ref{id = ?PREFIX_ROW_SPEC}} = Resource) ->
	add_resource_prefix_row(Resource);
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
		[#resource_spec_rel{id = ?PREFIX_ROW_SPEC, rel_type = "based"} | _]) ->
	add_resource_prefix_row(Resource);
add_resource3(Resource,
		[#resource_spec_rel{id = ?PREFIX_TABLE_SPEC, rel_type = "based"} | _]) ->
	add_resource_result(add_resource_prefix_table(Resource));
add_resource3(Resource, [_ | T]) ->
	add_resource3(Resource, T);
add_resource3(Resource, []) ->
	add_resource_result(cse:add_resource(Resource)).

%% @hidden
add_resource_prefix_table(#resource{name = Name} = Resource) ->
	F = fun F(eof, Acc) ->
				lists:flatten(Acc);
			F(Cont1, Acc) ->
				{Cont2, L} = cse:query_resource(Cont1, '_', {exact, Name},
						{exact, ?PREFIX_TABLE_SPEC}, '_'),
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
	case lists:keyfind("contained", #resource_rel.rel_type, Related) of
		#resource_rel{name = Table} ->
			add_resource_prefix_row(Table, Resource);
		false ->
			{error, 400}
	end.
%% @hidden
add_resource_prefix_row(Table,
		#resource{characteristic = Chars} = Resource) ->
	F = fun(CharName) ->
				case lists:keyfind(CharName, #resource_char.name, Chars) of
					#resource_char{value = Value} ->
						Value;
					false ->
						{error, 400}
				end
	end,
	Prefix = F("prefix"),
	{ok, #gtt{}} = cse_gtt:insert(Table, Prefix, F("value")),
	Id = Table ++ "-" ++ Prefix,
	Href = "/resourceInventoryManagement/v4/resource/" ++ Id,
	LM = {erlang:system_time(millisecond), erlang:unique_integer([positive])},
	Resource1 = Resource#resource{id = Id, href = Href, last_modified = LM},
	Headers = [{content_type, "application/json"},
			{location, Href}, {etag, cse_rest:etag(LM)}],
	Body = zj:encode(resource(Resource1)),
	{ok, Headers, Body}.

%% @hidden
add_resource_result({ok, #resource{href = Href, last_modified = LM} = Resource}) ->
	Headers = [{content_type, "application/json"},
			{location, Href}, {etag, cse_rest:etag(LM)}],
	Body = zj:encode(resource(Resource)),
	{ok, Headers, Body};
add_resource_result({error, _Reason}) ->
% @todo problem report
	{error, 400}.

-spec delete_resource(Id) -> Result
   when
      Id :: string(),
      Result :: {ok, Headers :: [tuple()], Body :: iolist()}
            | {error, ErrorCode :: integer()} .
%% @doc Respond to `DELETE /resourceInventoryManagement/v4/resource/{id}''
%%    request to remove a table row.
delete_resource(Id) ->
	try
		case string:tokens(Id, "-") of
			[Table, Prefix] ->
				Name = list_to_existing_atom(Table),
				ok = cse_gtt:delete(Name, Prefix),
				{ok, [], []};
			[Id] ->
				delete_resource1(cse:delete_resource(Id))
		end
	catch
		error:badarg ->
			{error, 404};
		_:_ ->
			{error, 400}
	end.
%% @hidden
delete_resource1(ok) ->
	{ok, [], []};
delete_resource1({error, _Reason}) ->
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
		version = "1.r",
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
		when is_list(ResRel), length(ResRel) > 0 ->
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
		when is_list(ResChar), length(ResChar) > 0 ->
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
		ResourceRelationship :: [resource_rel()] | [map()].
%% @doc CODEC for `ResourceRelationship'.
%%
%% Internally we condense `ResourceRefOrValue' with one record.
%%
resource_rel([#resource_rel{} | _] = List) ->
	Fields = record_info(fields, resource_rel),
	[resource_rel(Fields, R, #{}) || R <- List];
resource_rel([#{} | _] = List) ->
	Fields = record_info(fields, resource_rel),
	[resource_rel(Fields, M, #resource_rel{}) || M <- List];
resource_rel([]) ->
	[].
%% @hidden
resource_rel([id | T], #resource_rel{id = Id} = R, Acc)
		when is_list(Id) ->
	resource_rel(T, R, Acc#{"resource" => #{"id" => Id}});
resource_rel([id | T], #{"resource" := #{"id" := Id}} = M, Acc)
		when is_list(Id) ->
	resource_rel(T, M, Acc#resource_rel{id = Id});
resource_rel([href | T], #resource_rel{href = Href} = R,
		#{"resource" := Res} = Acc) when is_list(Href) ->
	resource_rel(T, R, Acc#{"resource" => Res#{"href" => Href}});
resource_rel([href | T], #{"resource" := #{"href" := Href}} = M, Acc)
		when is_list(Href) ->
	resource_rel(T, M, Acc#resource_rel{href = Href});
resource_rel([name | T], #resource_rel{name = Name} = R,
		#{"resource" := Res} = Acc) when is_list(Name) ->
	resource_rel(T, R, Acc#{"resource" => Res#{"name" => Name}});
resource_rel([name | T], #{"resource" := #{"name" := Name}} = M, Acc)
		when is_list(Name) ->
	resource_rel(T, M, Acc#resource_rel{name = Name});
resource_rel([rel_type | T], #resource_rel{rel_type = Type} = R,
		Acc) when is_list(Type) ->
	resource_rel(T, R, Acc#{"relationshipType" => Type});
resource_rel([rel_type | T], #{"relationshipType" := Type} = M,
		Acc) when is_list(Type) ->
	resource_rel(T, M, Acc#resource_rel{rel_type = Type});
resource_rel([_ | T], R, Acc) ->
	resource_rel(T, R, Acc);
resource_rel([], _, Acc) ->
	Acc.

-spec characteristic(Characteristic) -> Characteristic
	when
		Characteristic :: [resource_char()] | [map()].
%% @doc CODEC for `Characteristic'.
characteristic([#resource_char{} | _] = List) ->
	Fields = record_info(fields, resource_char),
	[characteristic(Fields, R, #{}) || R <- List];
characteristic([#{} | _] = List) ->
	Fields = record_info(fields, resource_char),
	[characteristic(Fields, M, #resource_char{}) || M <- List];
characteristic([]) ->
	[].
%% @hidden
characteristic([name | T], #resource_char{name = Name} = R, Acc)
		when is_list(Name) ->
	characteristic(T, R, Acc#{"name" => Name});
characteristic([name | T], #{"name" := Name} = M, Acc)
		when is_list(Name) ->
	characteristic(T, M, Acc#resource_char{name = Name});
characteristic([value | T], #resource_char{value = Value} = R, Acc) ->
	characteristic(T, R, Acc#{"value" => Value});
characteristic([value | T], #{"value" := Value} = M, Acc) ->
	characteristic(T, M, Acc#resource_char{value = Value});
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

%% @hidden
match(Key, Complex, Query) ->
	case lists:keyfind(Key, 1, Complex) of
		{_, like, [Value]} ->
			{like, Value};
		{_, exact, [Value]} ->
			{exact, Value};
		false ->
			case lists:keyfind(Key, 1, Query) of
				{_, Value} ->
					{exact, Value};
				false ->
					'_'
			end
	end.

