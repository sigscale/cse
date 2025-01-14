%%% cse_radius_acct_server.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2025 SigScale Global Inc.
%%% @author Vance Shipley <vances@sigscale.org> [http://www.sigscale.org]
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
%%% @doc This {@link //radius/radius. radius} callback module
%%% 	handles RADIUS accounting requests in the
%%% 	the {@link //cse. cse} application.
%%%
%%% @reference <a href="https://datatracker.ietf.org/doc/html/rfc2866">
%%% 	RFC2866 Remote Authentication Dial In User Service (RADIUS)</a>
%%%
-module(cse_radius_acct_server).
-copyright('Copyright (c) 2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(radius).

%% export the radius behaviour callbacks
-export([init/2, init/3, request/4, terminate/2]).

-include("cse.hrl").
-include_lib("radius/include/radius.hrl").

-type slp() :: {Module :: atom(),
		Args :: [term()], 
		Opts :: [gen_statem:start_opt()]}.

-record(state,
		{address :: inet:ip_address(),
		port :: inet:port_number(),
		services :: #{ServiceType :: 1..11 | undefined := slp()}}).
-type state() :: #state{}.

-define(LOGNAME, radius_auth).

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 23).
		-define(HMAC(Key, Data), crypto:mac(hmac, md5, Key, Data)).
	-else.
		-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
	-endif.
-else.
	-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
-endif.

%%----------------------------------------------------------------------
%%  The radius callbacks
%%----------------------------------------------------------------------

%% @hidden
init(Address, Port) ->
	init(Address, Port, []).

-spec init(Address, Port, Args) -> Result
	when
		Address :: inet:ip_address(), 
		Port :: pos_integer(),
		Args :: [term()],
		Result :: {ok, State} | {error, Reason},
		State :: state(),
		Reason :: term().
%% @doc This callback function is called when a
%% 	{@link //radius/radius_server. radius_server} behaviour process
%% 	initializes.
init(Address, Port, Args)
		when is_tuple(Address), is_integer(Port), is_list(Args) ->
	Services = proplists:get_value(slp, Args, undefined),
	State = #state{address = Address,
			port = Port, services = Services},
	{ok, State}.

-spec request(Address, Port, Packet, State) -> Result
	when
		Address :: inet:ip_address(), 
		Port :: pos_integer(),
		Packet :: binary(), 
		State :: state(),
		Result :: {ok, Response} | {error, Reason},
		Response :: binary(),
		Reason :: ignore | term().
%% @doc This function is called when a request is received on the port.
%%
request(Address, _Port, Packet, State) ->
	case cse:find_client(Address) of
		{ok, Client} ->
			request1(Client, Packet, State);
		{error, not_found} ->
			{error, ignore}
	end.
%% @hidden
request1(#client{secret = Secret} = Client, Packet, State)
		when is_binary(Secret) ->
	try
		RadiusRequest = radius:codec(Packet),
		#radius{code = ?AccountingRequest, id = ID, authenticator = Authenticator,
				attributes = AttributeData} = RadiusRequest,
		Length = byte_size(AttributeData) + 20,
		CalcAuth = crypto:hash(md5,
				[<<?AccountingRequest, ID, Length:16>>,
				<<0:128>>, AttributeData, Secret]),
		CalcAuth = list_to_binary(Authenticator),
		Attributes = radius_attributes:codec(AttributeData),
		{error, not_found} = radius_attributes:find(?UserPassword, Attributes),
		{error, not_found} = radius_attributes:find(?ChapPassword, Attributes),
		{error, not_found} = radius_attributes:find(?ReplyMessage, Attributes),
		{error, not_found} = radius_attributes:find(?State, Attributes),
		SessionId = radius_attributes:fetch(?AcctSessionId, Attributes),
		UserName = get_username(Attributes),
		NasId1 = get_nasid(Attributes),
		Port = get_port(Attributes),
		maybe_update(Client, NasId1),
		case radius_attributes:find(?AcctStatusType, Attributes) of
			{ok, ?AccountingStart} ->
				request2(Client, RadiusRequest, SessionId, UserName,
						NasId1, Port, Attributes, State);
			_ ->
				request3(Client, RadiusRequest, UserName,
						NasId1, Port, Attributes, State)
		end
	catch
		_:_ ->
			{error, ignore}
	end;
request1(_Client, _Packet, _State) ->
	{error, ignore}.
%% @hidden
request2(Client, RadiusRequest, SessionId, UserName,
		NasId, Port, Attributes, State) -> 
	try cse:find_session(list_to_binary(SessionId)) of
		{ok, SLPI} ->
			request4(SLPI, RadiusRequest, NasId);
		{error, not_found} ->
			request3(Client, RadiusRequest, UserName,
					NasId, Port, Attributes, State);
		{error, Reason} ->
			error_logger:error_report(["Radius Error",
					{module, ?MODULE}, {type, 'Accounting-Request'},
					{nas, NasId}, {session, SessionId},
					{error, Reason}]),
			{error, ignore}
	catch
		_:_ ->
			{error, ignore}
	end.
%% @hidden
request3(Client, RadiusRequest, UserName, NasId, Port, Attributes,
		#state{services = Services} = _State) -> 
	try
		{Module, ExtraArgs, Opts} = case
				radius_attributes:find(?ServiceType, Attributes) of
			{ok, ST} when is_map_key(ST, Services) ->
				maps:get(ST, Services);
			{error, not_found} when is_map_key(undefined, Services) ->
				maps:get(undefined, Services)
		end,
		Args = [Client, NasId, Port, UserName | ExtraArgs],
		supervisor:start_child(cse_slp_sup, [Module, Args, Opts])
	of
		{ok, Child} ->
			request4(Child, RadiusRequest, NasId);
		{error, Reason} ->
			error_logger:error_report(["Radius Error",
					{module, ?MODULE}, {type, 'Accounting-Request'},
					{nas, NasId}, {error, Reason}]),
			{error, ignore}
	catch
		_:_ ->
			{error, ignore}
	end.
%% @hidden
request4(SLPI, RadiusRequest, NasId) -> 
	case catch gen_statem:call(SLPI, RadiusRequest) of
		{'EXIT', Reason} ->
			error_logger:error_report(["Radius Error",
					{module, ?MODULE}, {fsm, SLPI},
					{type, 'Accounting-Request'}, {nas, NasId},
					{error, Reason}]),
			{error, ignore};
		#radius{} = RadiusResponse ->
			{ok, radius:codec(RadiusResponse)}
	end.

-spec terminate(Reason, State) -> ok
	when
		Reason :: term(), 
		State :: state().
%% @doc This callback function is called just before the server exits.
%%
terminate(_Reason, _State) ->
	ok.

%%----------------------------------------------------------------------
%% internal functions
%%----------------------------------------------------------------------

%% @hidden
get_username(Attributes) ->
	get_username1(radius_attributes:find(?UserName, Attributes)).
%% @hidden
get_username1({ok, Username}) ->
	Username;
get_username1({error, not_found}) ->
	undefined.

%% @hidden
get_nasid(Attributes) ->
	get_nasid(Attributes, radius_attributes:find(?NasIdentifier, Attributes)).
%% @hidden
get_nasid(_Attributes, {ok, NasIdentifier}) ->
	NasIdentifier;
get_nasid(Attributes, {error, not_found}) ->
	get_nasid1(radius_attributes:find(?NasIpAddress, Attributes)).
%% @hidden
get_nasid1({ok, NasIpAddress}) ->
	NasIpAddress;
get_nasid1({error, not_found}) ->
	undefined.

%% @hidden
get_port(Attributes) ->
	get_port(Attributes, radius_attributes:find(?NasPort, Attributes)).
%% @hidden
get_port(_Attributes, {ok, NasPort}) ->
	NasPort;
get_port(Attributes, {error, not_found}) ->
	get_port1(radius_attributes:find(?NasPortType, Attributes)).
%% @hidden
get_port1({ok, NasPortType}) ->
	NasPortType;
get_port1({error, not_found}) ->
	undefined.

%% @hidden
maybe_update(#client{identifier = NasId}, NasId) ->
	ok;
maybe_update(Client, NasId) ->
	LM = {erlang:system_time(millisecond),
			erlang:unique_integer([positive])},
	Client1 = Client#client{identifier = NasId, last_modified = LM},
	F = fun() ->
			mnesia:write(cse_client, Client1, write)
	end,
	case mnesia:transaction(F) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			exit(Reason)
	end.

