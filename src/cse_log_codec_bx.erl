%%% cse_log_codec_bx.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2024 SigScale Global Inc.
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
%%% @doc This library module implements CODEC functions for logging
%%% 	on the 3GPP Bx interface of the Charging Gatewway Function (CGF)
%%% 	in the {@link //cse. cse} application.
%%%
-module(cse_log_codec_bx).
-copyright('Copyright (c) 2024 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse_log_codec_bx public API
-export([csv/1]).

-include("diameter_gen_3gpp_rf_application.hrl").
-include_lib("diameter/include/diameter.hrl").

%%----------------------------------------------------------------------
%%  The cse_log_codec_bx public API
%%----------------------------------------------------------------------

-spec csv(ACR) -> iodata()
	when
		ACR :: #'3gpp_rf_ACR'{}.
%% @doc DIAMETER accounting CODEC for comma seperated values (CSV).
csv(#'3gpp_rf_ACR'{}) ->
	[].

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

