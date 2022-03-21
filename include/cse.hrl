%%% cse.hrl
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
%%%

-record(gtt,
		{num :: string() | '_' | '$1',
		value :: term() | undefined | '_' | '$2'}).

-record(resource_spec,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		description :: string() | undefined | '_',
		category :: string() | undefined | '_',
		class_type :: string() | undefined | '_',
		base_type :: string() | undefined | '_',
		schema :: string() | undefined | '_',
		version :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		last_modified :: {TS :: pos_integer(), N :: pos_integer()}
				| undefined | '_',
		is_bundle :: boolean() | undefined | '_',
		party = [] :: [party_rel()] | undefined | '_',
		status :: string() | undefined | '_',
		related = [] :: [resource_spec_rel()] | '_',
		feature = [] :: [] | '_',
		characteristic = [] :: [resource_spec_char()] | '_',
		target_schema :: target_res_schema() | undefined | '_'}).
-type resource_spec() :: #resource_spec{}.

-record(resource_spec_rel,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		rel_type :: string() | undefined | '_',
		role :: string() | undefined | '_',
		min :: non_neg_integer() | undefined | '_',
		max :: non_neg_integer() | undefined | '_',
		default :: non_neg_integer() | undefined | '_',
		characteristic = [] :: [resource_spec_char()] | '_'}).
-type resource_spec_rel() :: #resource_spec_rel{}.

-record(resource,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		description :: string() | undefined | '_',
		class_type :: string() | undefined | '_',
		base_type :: string() | undefined | '_',
		schema :: string() | undefined | '_',
		version :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		last_modified :: {TS :: pos_integer(), N :: pos_integer()}
				| undefined | '_',
		category :: string() | undefined | '_',
		admin_state :: string() | undefined | '_',
		oper_state :: string() | undefined | '_',
		usage_state :: string() | undefined | '_',
		status :: string() | undefined | '_',
		party = [] :: [party_rel()] | undefined | '_',
		feature = [] :: [] | '_',
		related = [] :: [resource_rel()] | '_',
		specification :: resource_spec_ref() | undefined | '_',
		characteristic = [] :: [resource_char()] | '_'}).
-type resource() :: #resource{}.

-record(resource_rel,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		rel_type :: string() | undefined | '_'}).
-type resource_rel() :: #resource_rel{}.

-record(resource_spec_ref,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		version :: string() | undefined | '_'}).
-type resource_spec_ref() :: #resource_spec_ref{}.

-record(resource_spec_char,
		{name :: string() | undefined | '_',
		description :: string() | undefined | '_',
		class_type :: string() | undefined | '_',
		schema :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		configurable :: boolean() | undefined | '_',
		extensible :: boolean() | undefined | '_',
		is_unique :: boolean() | undefined | '_',
		min :: non_neg_integer() | undefined | '_',
		max :: non_neg_integer() | undefined | '_',
		regex :: string() | undefined | '_',
		related = [] :: [resource_spec_char_rel()] | '_',
		value = [] :: [resource_spec_char_val()] | undefined | '_',
		value_type :: string() | undefined | '_'}).
-type resource_spec_char() :: #resource_spec_char{}.

-record(resource_spec_char_rel,
		{char_id :: string() | undefined | '_',
		name :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		res_spec_id :: string() | undefined | '_',
		res_spec_href :: string() | undefined | '_',
		rel_type :: string() | undefined | '_'}).
-type resource_spec_char_rel() :: #resource_spec_char_rel{}.

-record(resource_spec_char_val,
		{is_default :: boolean() | undefined | '_',
		range_interval :: open | closed | closed_bottom
				| closed_top | undefined | '_',
		regex :: string() | undefined | '_',
		unit :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		value :: string() | number() | undefined | '_',
		value_from :: integer() | undefined | '_',
		value_to :: integer() | undefined | '_',
		value_type :: string() | undefined | '_'}).
-type resource_spec_char_val() :: #resource_spec_char_val{}.

-record(resource_char,
		{name :: string() | undefined | '_',
		class_type :: string() | undefined | '_',
		schema :: string() | undefined | '_',
		value :: term() | undefined | '_'}).
-type resource_char() :: #resource_char{}.

-record(target_res_schema,
		{location :: string() | undefined | '_',
		type :: string() | undefined | '_'}).
-type target_res_schema() :: #target_res_schema{}.

-record(party_rel,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		role :: string() | undefined | '_',
		ref_type :: string() | undefined | '_'}).
-type party_rel() :: #party_rel{}.

-record(service,
		{key :: 0..2147483647,
		module :: atom(),
		edp :: #{cse:event_type() => cse:monitor_mode()}}).

