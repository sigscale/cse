%%% cse_codec.hrl
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

