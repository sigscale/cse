%%% cse.hrl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2022-2023 SigScale Global Inc.
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
		{id :: binary() | string() | undefined | '_',
		href :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '$1' | '_',
		description :: binary() | string() | undefined | '_',
		category :: binary() | string() | undefined | '_',
		class_type :: binary() | string() | undefined | '_',
		base_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		version :: binary() | string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		last_modified :: {TS :: pos_integer(), N :: pos_integer()}
				| undefined | '_',
		is_bundle :: boolean() | undefined | '_',
		party = [] :: [cse:party_rel()] | undefined | '_',
		status :: binary() | string() | undefined | '_',
		related = [] :: [cse:resource_spec_rel()] | '_',
		feature = [] :: [] | '_',
		characteristic = [] :: [cse:resource_spec_char()] | '_',
		target_schema :: cse:target_res_schema() | undefined | '_'}).

-record(resource_spec_rel,
		{id :: binary() | string() | undefined | '_',
		href :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		rel_type :: binary() | string() | undefined | '$2' | '_',
		role :: binary() | string() | undefined | '_',
		min :: non_neg_integer() | undefined | '_',
		max :: non_neg_integer() | undefined | '_',
		default :: non_neg_integer() | undefined | '_',
		characteristic = [] :: [cse:resource_spec_char()] | '_'}).

-record(resource,
		{id :: binary() | string() | undefined | '_',
		href :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '$1' | '_',
		description :: binary() | string() | undefined | '_',
		version :: binary() | string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		last_modified :: {TS :: pos_integer(), N :: pos_integer()}
				| undefined | '_',
		category :: binary() | string() | undefined | '_',
		admin_state :: binary() | string() | undefined | '_',
		oper_state :: binary() | string() | undefined | '_',
		usage_state :: binary() | string() | undefined | '_',
		status :: binary() | string() | undefined | '_',
		party = [] :: [cse:party_rel()] | undefined | '_',
		feature = [] :: [] | '_',
		specification :: cse:resource_spec_ref() | undefined | '_',
		related = #{} :: cse:related_resources() | '_',
		characteristic = #{} :: cse:characteristics() | '_',
		class_type :: binary() | string() | undefined | '_',
		base_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		attributes :: map() | undefined | '_'}).

-record(resource_ref,
		{id :: binary() | string() | undefined | '_',
		href :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '$3' | '_',
		ref_type :: binary() | string() | undefined | '_',
		class_type :: binary() | string() | undefined | '_',
		base_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		attributes :: map() | undefined | '_'}).

-record(resource_rel,
		{rel_type :: binary() | string() | undefined | '_',
		resource :: cse:resource_ref() | undefined | '_',
		class_type :: binary() | string() | undefined | '_',
		base_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		attributes :: map() | undefined | '_'}).

-record(resource_spec_ref,
		{id :: binary() | string() | undefined | '_',
		href :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '_',
		version :: binary() | string() | undefined | '_'}).

-record(resource_spec_char,
		{name :: binary() | string() | undefined | '_',
		description :: binary() | string() | undefined | '_',
		class_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		configurable :: boolean() | undefined | '_',
		extensible :: boolean() | undefined | '_',
		is_unique :: boolean() | undefined | '_',
		min :: non_neg_integer() | undefined | '_',
		max :: non_neg_integer() | undefined | '_',
		regex :: binary() | string() | undefined | '_',
		related = [] :: [cse:resource_spec_char_rel()] | '_',
		value = [] :: [cse:resource_spec_char_val()] | undefined | '_',
		value_type :: binary() | string() | undefined | '_'}).

-record(resource_spec_char_rel,
		{char_id :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		res_spec_id :: binary() | string() | undefined | '_',
		res_spec_href :: binary() | string() | undefined | '_',
		rel_type :: binary() | string() | undefined | '_'}).

-record(resource_spec_char_val,
		{is_default :: boolean() | undefined | '_',
		range_interval :: open | closed | closed_bottom
				| closed_top | undefined | '_',
		regex :: binary() | string() | undefined | '_',
		unit :: binary() | string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		value :: binary() | string() | number() | undefined | '_',
		value_from :: integer() | undefined | '_',
		value_to :: integer() | undefined | '_',
		value_type :: binary() | string() | undefined | '_'}).

-record(char_rel,
		{id :: binary() | string() | undefined | '_',
		rel_type :: binary() | string() | undefined | '_',
		class_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		base_type :: binary() | string() | undefined | '_',
		attributes :: map() | undefined | '_'}).

-record(characteristic,
		{id :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '_',
		related = [] :: [cse:char_rel()] | '_',
		value_type :: binary() | string() | undefined | '_',
		value :: term() | undefined | '_',
		class_type :: binary() | string() | undefined | '_',
		schema :: binary() | string() | undefined | '_',
		base_type :: binary() | string() | undefined | '_',
		attributes :: map() | undefined | '_'}).

-record(target_res_schema,
		{location :: binary() | string() | undefined | '_',
		type :: binary() | string() | undefined | '_'}).

-record(party_rel,
		{id :: binary() | string() | undefined | '_',
		href :: binary() | string() | undefined | '_',
		name :: binary() | string() | undefined | '_',
		role :: binary() | string() | undefined | '_',
		ref_type :: binary() | string() | undefined | '_'}).

-record(in_service,
		{key :: 0..2147483647,
		module :: atom(),
		data = #{} :: map(),
		opts = [] :: [term()]}).

-record(diameter_context,
		{id :: binary(),
		module :: atom(),
		args  = [] :: [term()],
		opts = [] :: [term()]}).

