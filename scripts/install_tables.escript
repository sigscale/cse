#!/usr/bin/env escript
%% vim: syntax=erlang

main([]) ->
	Nodes = mnesia:system_info(db_nodes),
	case length(Nodes) of
		N when N > 0 ->
			case mnesia:set_master_nodes(Nodes) of
				ok ->
					ok;
				{error, Reason1} ->
					stopped = mnesia:stop(),
					io:fwrite("error: ~w~n", [Reason1]),
					erlang:halt(1)
			end;
		0 ->
			ok
	end,
	CseTables = case cse_app:install() of
		{ok, Tables1} ->
			Tables1;
		{error, Reason2} ->
			stopped = mnesia:stop(),
			io:fwrite("error: ~w~n", [Reason2]),
			erlang:halt(1)
	end,
	M3uaTables = case m3ua_app:install() of
		{ok, Tables2} ->
			Tables2;
		{error, Reason3} ->
			stopped = mnesia:stop(),
			io:fwrite("error: ~w~n", [Reason3]),
			erlang:halt(1)
	end,
	GttTables = case gtt_app:install() of
		{ok, Tables3} ->
			Tables3;
		{error, Reason4} ->
			stopped = mnesia:stop(),
			io:fwrite("error: ~w~n", [Reason4]),
			erlang:halt(1)
	end,
	case mnesia:stop() of
		stopped ->
			io:fwrite("{ok, ~p}~n", [CseTables ++ M3uaTables ++ GttTables]);
		{error, Reason5} ->
			io:fwrite("error: ~w~n", [Reason5]),
			erlang:halt(1)
	end.

