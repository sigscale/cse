%%% cse_codec.hrl
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
%%%

-define(ST, 15).

%% ITU-T Q.763 ISUP 3.9
-record(called_party,
		{nai :: 1..8 | 112..126,
		inn :: 0..1,
		npi :: 1..6,
		address = [] :: [0..9 | 11..12 | ?ST]}).

%% ITU-T Q.763 ISUP 3.10
-record(calling_party,
		{nai :: 1..4 | 112..126,
		ni :: 0..1,
		npi :: 1..6,
		apri :: 0..3,
		si :: 1 | 3,
		address = [] :: [0..9 | 11..12]}).

%% 3GPP TS 24.00 10.5.4.7
-record(called_party_bcd,
		{ton :: 0..4,
		npi :: 0..1 | 3..4 | 8..9,
		address = [] :: [0..15]}).

%% 3GPP TS 29.02 17.7.8
-record(isdn_address,
		{nai :: 0..7,
		npi :: 0..9,
		address = [] :: [$0..$9]}).

%% ITU-T Q.763 ISUP 3.12
-record(cause,
		{coding = itu :: itu | iso | national | other,
		location :: user | local_private | local_public | transit
				| remote_public | remote_private | international
				| beyond | undefined,
		value = 31 :: 1..127,
		diagnostic :: binary() | undefined}).

%% ITU-T Q.763 ISUP 3.26
-record(generic_number,
		{nqi :: 0..10,
		nai :: 1..4,
		ni :: 0..1,
		npi :: 1 | 3..6,
		apri :: 0..2,
		si :: 0..3,
		address = [] :: [0..9 | 16#b]}).

%% ITU-T Q.763 ISUP 3.24
-record(generic_digits,
		{enc :: 0..3,
		tod :: 0..3,
		digits :: binary()}).

%% 3GPP TS 23.228 4.3
-record(ims_uri,
		{scheme :: sip | sips | tel,
		user = [] :: string(),
		user_params = #{} :: map(),
		host = [] :: string(),
		port :: pos_integer() | undefined,
		uri_params = #{} :: map()}).

