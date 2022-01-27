%% cse_rest_res_resource.erl
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

-export([content_types_accepted/0, content_types_provided/0]).
-export([get_resource_spec/1, get_resource_specs/1]).

-define(specPath, "/resourceCatalogManagement/v4/resourceSpecification/").

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
%%		Retrieve a resource specification.
get_resource_spec("1") ->
	ResourceSpec = prefix_table_spec(),
	Body = zj:encode(ResourceSpec),
	Headers = [{content_type, "application/json"}],
	{ok, Headers, Body};
get_resource_spec("2") ->
	ResourceSpec = prefix_row_spec(),
	Body = zj:encode(ResourceSpec),
	Headers = [{content_type, "application/json"}],
	{ok, Headers, Body};
get_resource_spec(_) ->
	{error, 404}.

-spec get_resource_specs(Query) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		Result	:: {ok, Headers, Body} | {error, Status},
		Headers	:: [tuple()],
		Body		:: iolist(),
		Status	:: 400 | 404 | 500.
%% @doc Respond to `GET /resourceCatalogManagement/v4/resourceSpecification'.
%% 	Retrieve all resource specifications.
get_resource_specs([] = _Query) ->
	Headers = [{content_type, "application/json"}],
	Object = [prefix_table_spec(), prefix_row_spec()],
	Body = zj:encode(Object),
	{ok, Headers, Body};
get_resource_specs(_Query) ->
	{error, 400}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
prefix_table_spec() ->
	#{"id" => "1",
		"href" => ?specPath "1",
		"name" => "PrefixTable",
		"description" => "Prefix table specification",
		"lifecycleStatus" => "Active",
		"version" => "1.0",
		"lastUpdate" => "2022-01-20",
		"category" => "PrefixTable"
	}.

%% @hidden
prefix_row_spec() ->
	#{"id" => "2",
		"href" => ?specPath "2",
		"name" => "PrefixRow",
		"description" => "Prefix table row specification",
		"lifecycleStatus" => "Active",
		"version" => "1.0",
		"lastUpdate" => "2022-01-20",
		"category" => "PrefixRow",
		"resourceSpecCharacteristic" => [
			#{"name" => "prefix",
				"description" => "Prefix of the row",
				"valueType" => "String"},
			#{"name" => "value",
				"description" => "Prefix value"}
		]
	}.

