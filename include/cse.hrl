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

-record(resource,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		description :: string() | undefined | '_',
		category :: string() | undefined | '_',
		class_type :: string() | undefined | '_',
		base_type :: string() | undefined | '_',
		schema :: string() | undefined | '_',
		state :: string() | undefined | '_',
		substate :: string() | undefined | '_',
		version :: string() | undefined | '_',
		start_date :: pos_integer() | undefined | '_',
		end_date :: pos_integer() | undefined | '_',
		last_modified :: {TS :: pos_integer(), N :: pos_integer()}
				| undefined | '_',
		related = [] :: [resource_rel()] | '_',
		specification :: specification_ref() | undefined | '_',
		characteristic = [] :: [resource_char()] | '_'}).
-type resource() :: #resource{}.

-record(resource_rel,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		type :: string() | undefined | '_',
		referred_type :: string() | undefined | '_'}).
-type resource_rel() :: #resource_rel{}.

-record(specification_ref,
		{id :: string() | undefined | '_',
		href :: string() | undefined | '_',
		name :: string() | undefined | '_',
		version :: string() | undefined | '_'}).
-type specification_ref() :: #specification_ref{}.

-record(resource_char,
		{name :: string() | undefined | '_',
		class_type :: string() | undefined | '_',
		schema :: string() | undefined | '_',
		value :: term() | undefined | '_'}).
-type resource_char() :: #resource_char{}.

-record(service,
		{key :: 1..4294967295,
		module :: atom(),
		edp :: #{cse:event_type() => cse:monitor_mode()}}).

