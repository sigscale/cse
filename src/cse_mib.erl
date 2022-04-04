%%% cse_mib.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2018 - 2021 SigScale Global Inc.
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
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This library module implements the SNMP MIB for the
%%%     {@link //cse. cse} application.
%%%
-module(cse_mib).
-copyright('Copyright (c) 2018 - 2022 SigScale Global Inc.').

%% export the cse_mib public API
-export([load/0, load/1, unload/0, unload/1]).

%% export the cse_mib snmp agent callbacks
-export([dbp_local_config/2, dbp_local_stats/2, dcca_peer_info/3]).
		

-include("cse.hrl").

%%----------------------------------------------------------------------
%%  The cse_mib public API
%%----------------------------------------------------------------------

-spec load() -> Result
	when
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Loads the SigScale CSE MIBs.
load() ->
	case code:priv_dir(cse) of
		PrivDir when is_list(PrivDir) ->
			MibDir = PrivDir ++ "/mibs/",
			Mibs = [MibDir ++ MIB || MIB <- mibs()],
			snmpa:load_mibs(Mibs);
		{error, Reason} ->
			{error, Reason}
	end.

-spec load(Agent) -> Result
	when
		Agent :: pid() | atom(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Loads the SigScale CSE MIB into an agent.
load(Agent) ->
	case code:priv_dir(cse) of
		PrivDir when is_list(PrivDir) ->
			MibDir = PrivDir ++ "/mibs/",
			Mibs = [MibDir ++ MIB || MIB <- mibs()],
			snmpa:load_mibs(Agent, Mibs);
		{error, Reason} ->
			{error, Reason}
	end.

-spec unload() -> Result
	when
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Unloads the SigScale CSE MIBs.
unload() ->
	snmpa:unload_mibs(mibs()).

-spec unload(Agent) -> Result
	when
		Agent :: pid() | atom(),
		Result :: ok | {error, Reason},
		Reason :: term().
%% @doc Unloads the SigScale CSE MIB from an agent.
unload(Agent) ->
	snmpa:unload_mibs(Agent, mibs()).

%%----------------------------------------------------------------------
%% The cse_mib snmp agent callbacks
%----------------------------------------------------------------------

-spec dbp_local_config(Operation, Item) -> Result
	when
		Operation :: get,
		Item :: 'Origin-Host' | 'Origin-Realm' | 'Product-Name',
		Result :: {value, Value} | genErr,
		Value :: atom() | integer() | string() | [integer()].
% @doc Get local DIAMETER configuration.
% @private
dbp_local_config(get, Item) ->
	case lists:keyfind(cse_diameter_service, 1, diameter:services()) of
		Service when is_tuple(Service) ->
			case diameter:service_info(Service, Item) of
				Info when is_binary(Info) ->
					{value, binary_to_list(Info)};
				Info when is_list(Info) ->
					{value, Info};
				_ ->
					genErr
			end;
		false ->
			{noValue, noSuchInstance}
	end.

-spec dbp_local_stats(Operation, Item) -> Result
	when
		Operation :: get,
		Item :: uptime,
		Result :: {value, Value} | {noValue, noSuchInstance} | genErr,
		Value :: atom() | integer() | string() | [integer()].
%% @doc Handle SNMP requests for `DIAMETER-BASE-PROTOCOL-MIB::dbpLocalStats'.
%% @private
dbp_local_stats(get, uptime) ->
	case catch diameter_stats:uptime() of
		{'EXIT', _Reason} ->
			genErr;
		{Hours, Mins, Secs, MicroSecs} ->
			{value, (Hours * 360000) + (Mins * 6000)
					+ (Secs * 100) + (MicroSecs div 10)}
	end;
dbp_local_stats(get, Item) ->
	case lists:keyfind(cse_diameter_service, 1, diameter:services()) of
		Service when is_tuple(Service) ->
			case catch diameter:service_info(Service, transport) of
				Info when is_list(Info) ->
					case total_packets(Info) of
						{ok, {PacketsIn, _}} when Item == in ->
							{value, PacketsIn};
						{ok, {_, PacketsOut}} when Item == out ->
							{value, PacketsOut};
						{error, not_found} ->
							{noValue, noSuchInstance}
					end;
				_ ->
					genErr
			end;
		false ->
			genErr
	end.

-spec dcca_peer_info(Operation, RowIndex, Columns) -> Result
	when
		Operation :: get | get_next,
		RowIndex :: ObjectId,
		ObjectId :: [integer()],
		Columns :: [Column],
		Column :: integer(),
		Result :: [Element] | {genErr, Column},
		Element :: {value, Value} | {ObjectId, Value},
		Value :: atom() | integer() | string() | [integer()].
%% @doc Handle SNMP requests for the peer info table.
dcca_peer_info(get_next = _Operation, [] = _RowIndex, Columns) ->
	dcca_peer_info_get_next(1, Columns, true);
dcca_peer_info(get_next, [N], Columns) ->
	dcca_peer_info_get_next(N + 1, Columns, true);
dcca_peer_info(get, [N], Columns) ->
	dcca_peer_info_get(N, Columns).
%% @hidden
dcca_peer_info_get_next(Index, Columns, First) ->
	case lists:keyfind(cse_diameter_service, 1, diameter:services()) of
		Service when is_tuple(Service) ->
			case catch diameter:service_info(Service, connections) of
				Info when is_list(Info) ->
					case peer_info(Index, Info) of
						{ok, {PeerId, Rev}} ->
							F1 = fun(0, Acc) ->
										[{[1, Index], Index} | Acc];
									(1, Acc) ->
										[{[1, Index], Index} | Acc];
									(2, Acc) ->
										[{[2, Index], PeerId} | Acc];
									(3, Acc) when Rev == undefined ->
										case dcca_peer_info_get_next(Index + 1, [3], true) of
											[NextResult] ->
												[NextResult | Acc];
											{genError, N} ->
												 throw({genError, N})
										end;
									(3, Acc) ->
										[{[3, Index], Rev} | Acc];
									(4, Acc) ->
										[{[4, Index], volatile} | Acc];
									(5, Acc) ->
										[{[5, Index], active} | Acc];
									(_, Acc) ->
										[endOfTable | Acc]
							end,
							try
								 lists:reverse(lists:foldl(F1, [], Columns))
							catch	
								{genError, N} ->
									{genError, N}
							end;
						{error, not_found} when First == true ->
							F2 = fun(N) ->
									N + 1
							end,
							NextColumns = lists:map(F2, Columns),
							dcca_peer_info_get_next(1, NextColumns, false);
						{error, not_found} ->
							[endOfTable || _ <- Columns]
					end;
				_Info ->
					[endOfTable || _ <- Columns]
			end;
		false ->
			{genErr, 0}
	end.
%% @hidden
dcca_peer_info_get(Index, Columns) ->
	case lists:keyfind(cse_diameter_service, 1, diameter:services()) of
		Service when is_tuple(Service) ->
			case catch diameter:service_info(Service, connections) of
				Info when is_list(Info) ->
					case peer_info(Index, Info) of
						{ok, {PeerId, Rev}} ->
							F1 = fun(0, Acc) ->
										[{value, Index} | Acc];
									(1, Acc) ->
										[{value, Index} | Acc];
									(2, Acc) ->
										[{value, PeerId} | Acc];
									(3, _Acc) when Rev == undefined ->
										[{noValue, noSuchInstance}];
									(3, Acc) ->
										[{value, Rev} | Acc];
									(4, Acc) ->
										[{value, volatile} | Acc];
									(5, Acc) ->
										[{value, active} | Acc];
									(_, _Acc) ->
										{noValue, noSuchInstance}
							end,
							lists:reverse(lists:foldl(F1, [], Columns));
						{error, not_found} ->
							{noValue, noSuchInstance}
					end;
				_Info ->
						{noValue, noSuchInstance}
			end;
		false ->
			{genErr, 0}
	end.

%%----------------------------------------------------------------------
%% internal functions
%----------------------------------------------------------------------

%% @hidden
mibs() ->
	["SIGSCALE-DIAMETER-BASE-PROTOCOL-MIB"].

-spec total_packets(Info) -> Result
	when
		Info :: [tuple()],
		Result :: {ok, {PacketsIn, PacketsOut}} | {error, Reason},
		PacketsIn :: integer(),
		PacketsOut :: integer(),
		Reason :: term().
%% @doc Get packet counts from service info.
total_packets(Info) ->
	total_packets(Info, {0, 0}).
%% @hidden
total_packets([H | T], Acc) ->
	case lists:keyfind(accept, 1, H) of
		{_, L} ->
			case total_packets1(L, Acc) of
				{ok, Acc1} ->
					total_packets(T, Acc1);
				{error, _Reason} ->
					total_packets(T, Acc)
			end;
		false ->
			{error, not_found}
	end;
total_packets([], Acc) ->
	{ok, Acc}.
%% @hidden
total_packets1([H | T], Acc) ->
	case lists:keyfind(port, 1, H) of
		{_, L} ->
			case total_packets2(L, Acc) of
				{ok, Acc1} ->
					total_packets1(T, Acc1);
				{error, Reason} ->
					{error, Reason}
			end;
		false ->
			total_packets1(T, Acc)
	end;
total_packets1([], Acc) ->
	{ok, Acc}.
%% @hidden
total_packets2(L1, Acc) ->
	case lists:keyfind(statistics, 1, L1) of
		{_, L2} ->
			total_packets3(L2, Acc);
		false ->
			{error, not_found}
	end.
%% @hidden
total_packets3(L, {PacketsIn, PacketsOut}) ->
	case lists:keyfind(recv_cnt, 1, L) of
		{_, N} ->
			total_packets4(L, {PacketsIn + N, PacketsOut});
		false ->
			{error, not_found}
	end.
%% @hidden
total_packets4(L, {PacketsIn, PacketsOut}) ->
	case lists:keyfind(send_cnt, 1, L) of
		{_, N} ->
			{ok, {PacketsIn, PacketsOut + N}};
		false ->
			{error, not_found}
	end.

-spec peer_info(Index, Info) -> Result
   when
      Index :: integer(),
      Info :: [tuple()],
      Result :: {ok, {PeerId, Rev}} | {error, Reason},
      PeerId :: string(),
      Rev :: integer() | undefined,
      Reason :: term().
%% @doc Get peer entry table.
%% @hidden
peer_info(Index, Info) ->
	case catch lists:nth(Index, Info) of
		Connection when is_list(Connection) ->
			peer_info(Connection);
		_ ->
			{error, not_found}
	end.
%% @hidden
peer_info(Info) ->
	case lists:keyfind(caps, 1, Info) of
		{_, Caps} ->
			peer_info1(Caps);
		false ->
         {error, not_found}
	end.
%% @hidden
peer_info1(Caps) ->
	case lists:keyfind(origin_host, 1, Caps) of
		{_, {_,PeerId}} ->
			peer_info2(Caps, binary_to_list(PeerId));
		false ->
         {error, not_found}
	end.
%% @hidden
peer_info2(Caps, PeerId) ->
	case lists:keyfind(firmware_revision, 1, Caps) of
		{_, {_, []}} ->
			peer_info3(PeerId, undefined);
		{_, {_, [Rev]}} ->
			peer_info3(PeerId, Rev);
		false ->
         {error, not_found}
	end.
%% @hidden
peer_info3(PeerId, Rev) ->
	{ok, {PeerId, Rev}}.

