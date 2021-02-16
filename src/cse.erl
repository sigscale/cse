%%% cse.erl
%%% vim: ts=3
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
%%% @doc This library module implements the public API for the
%%%   {@link //cse. cse} application.
%%%
-module(cse).
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse  public API
-export([start/0, stop/0, start/2, stop/1]).

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

-spec start(Port, Options) -> Result
	when
		Port :: inet:port_number(),
		Options :: [m3ua:option()],
		Result :: {ok, SapSup} | {error, Reason},
		SapSup :: pid(),
		Reason :: term().
%% @doc Start a network service access point (NSAP).
%%
%% 	Returns the {@link //stdlib/supervisor. supervisor} process.
start(Port, Options) when is_integer(Port), is_list(Options) ->
	Children = supervisor:which_children(cse_sup),
	{_, Sup, _, _} = lists:keyfind(cse_sap_sup_sup, 1, Children),
	supervisor:start_child(Sup, [[Port, Options]]).

-spec stop(SapSup) -> Result
	when
		SapSup :: pid(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Stop a network service access point (NSAP).
stop(SapSup) when is_pid(SapSup) ->
	Children = supervisor:which_children(cse_sup),
	{_, Sup, _, _} = lists:keyfind(cse_sap_sup_sup, 1, Children),
	supervisor:terminate_child(Sup, SapSup).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

