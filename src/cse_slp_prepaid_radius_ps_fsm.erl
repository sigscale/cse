%%% cse_slp_prepaid_radius_ps_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% @doc This {@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module implements a Service Logic Processing Program (SLP)
%%% 	for RADIUS authentication and accounting within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This Service Logic Program (SLP) implements a 3GPP Online
%%% 	Charging Function (OCF) interfacing across the <i>Re</i> reference
%%% 	point interafce, using the
%%% 	<a href="https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0">
%%% 	Nrf_Rating</a> API, with a remote <i>Rating Function</i>.
%%%
%%% 	This SLP specifically handles Packet Switched (PS) data
%%% 	service usage with `Service-Context-Id' of `32251@3gpp.org'.
%%%
%%% 	== Message Sequence ==
%%% 	The diagram below depicts the normal sequence of exchanged messages:
%%%
%%% 	<img alt="message sequence chart" src="ocf-nrf-msc.svg" />
%%%
%%% 	== State Transitions ==
%%% 	The following diagram depicts the states, and events which drive state
%%% 	transitions, in the OCF finite state machine (FSM):
%%%
%%% 	<img alt="state machine" src="prepaid-diameter-data.svg" />
%%%
-module(cse_slp_prepaid_radius_ps_fsm).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, authorize_origination_attempt/3,
		collect_information/3, analyse_information/3, active/3]).
%% export the private api
%-export([nrf_start_reply/2, nrf_update_reply/2, nrf_release_reply/2]).

-include_lib("radius/include/radius.hrl").
-include_lib("kernel/include/logger.hrl").
-include("cse.hrl").
-include("cse_codec.hrl").

-define(PS_CONTEXTID, "32251@3gpp.org").
-define(SERVICENAME, "Prepaid Data").
-define(FSM_LOGNAME, prepaid).
-define(NRF_LOGNAME, rating).

-ifdef(OTP_RELEASE).
	-if(?OTP_RELEASE >= 23).
		-define(HMAC(Key, Data), crypto:mac(hmac, md5, Key, Data)).
	-else.
		-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
	-endif.
-else.
	-define(HMAC(Key, Data), crypto:hmac(md5, Key, Data)).
-endif.

-type state() :: null
		| authorize_origination_attempt
		| collect_information | analyse_information | active.

-type statedata() :: #{start := pos_integer(),
		from => pid(),
		nas_client => cse:client(),
		nas_id => string(),
		nas_port => inet:port_number(),
		session_id => binary(),
		sequence => pos_integer(),
		username => string(),
		password => string(),
		nrf_profile => atom(),
		nrf_address => inet:ip_address(),
		nrf_port => non_neg_integer(),
		nrf_uri => string(),
		nrf_http_options => httpc:http_options(),
		nrf_headers => httpc:headers(),
		nrf_location => string(),
		nrf_start => pos_integer(),
		nrf_req_url => string(),
		nrf_http => map(),
		nrf_reqid => reference()}.

%%----------------------------------------------------------------------
%%  The cse_slp_prepaid_radius_ps_fsm gen_statem callbacks
%%----------------------------------------------------------------------

-spec callback_mode() -> Result
	when
		Result :: gen_statem:callback_mode_result().
%% @doc Set the callback mode of the callback module.
%% @see //stdlib/gen_statem:callback_mode/0
%% @private
%%
callback_mode() ->
	[state_functions, state_enter].

-spec init(Args) -> Result
	when
		Args :: [term()],
		Result :: {ok, State, Data} | {ok, State, Data, Actions}
				| ignore | {stop, Reason},
		State :: state(),
		Data :: statedata(),
		Actions :: Action | [Action],
		Action :: gen_statem:action(),
		Reason :: term().
%% @doc Initialize the {@module} finite state machine.
%%
%% 	Initialize a Service Logic Processing Program (SLP) instance.
%%
%% @see //stdlib/gen_statem:init/1
%% @private
init([Client, NasId, Port, UserName, Password | _ExtraArgs]) ->
	{ok, Profile} = application:get_env(cse, nrf_profile),
	{ok, URI} = application:get_env(cse, nrf_uri),
	{ok, HttpOptions} = application:get_env(nrf_http_options),
	{ok, Headers} = application:get_env(nrf_headers),
	Data = #{nrf_profile => Profile, nrf_uri => URI,
			nrf_http_options => HttpOptions, nrf_headers => Headers,
			start => erlang:system_time(millisecond),
			username => UserName, password => Password,
			nas_client => Client, nas_id => NasId,
			nas_port => Port, sequence => 1},
	case httpc:get_options([ip, port], Profile) of
		{ok, Options} ->
			init1(Options, Data);
		{error, Reason} ->
			{stop, Reason}
	end.
%% @hidden
init1([{ip, Address} | T], Data) ->
	init1(T, Data#{nrf_address => Address});
init1([{port, Port} | T], Data) ->
	init1(T, Data#{nrf_port => Port});
init1([], Data) ->
	{ok, null, Data}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(enter = _EventType, null = _EventContent, _Data) ->
	keep_state_and_data;
null(enter = _EventType, _OldState, _Data) ->
	{stop, shutdown};
null({call, _From}, #radius{}, Data) ->
	{next_state, authorize_origination_attempt, Data, postpone}.

-spec authorize_origination_attempt(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>authorize_origination_attempt</em> state.
%% @private
authorize_origination_attempt(enter, _EventContent, _Data) ->
	keep_state_and_data;
authorize_origination_attempt({call, From},
		#radius{id = ID, authenticator = RequestAuthenticator},
		#{nas_client := #client{secret = Secret}} = Data) ->
	RadiusResponse = reject(ID, RequestAuthenticator, Secret),
	Actions = [{reply, From, RadiusResponse}],
	{next_state, null, Data, Actions}.

-spec collect_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>collect_information</em> state.
%% @private
collect_information(enter, _EventContent, _Data) ->
	keep_state_and_data;
collect_information({call, _From},
		#radius{},  Data) ->
	{next_state, null, Data}.

-spec analyse_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>analyse_information</em> state.
%% @private
analyse_information(enter, _EventContent, _Data) ->
	keep_state_and_data;
analyse_information({call, _From},
		#radius{},  Data) ->
	{next_state, null, Data}.

-spec active(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>active</em> state.
%% @private
active(enter, _EventContent, _Data) ->
	keep_state_and_data;
active({call, _From},
		#radius{},  Data) ->
	{next_state, null, Data}.

-spec handle_event(EventType, EventContent, State, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		State :: state(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(State).
%% @doc Handles events received in any state.
%% @private
%%
handle_event(_EventType, _EventContent, _State, _Data) ->
	keep_state_and_data.

-spec terminate(Reason, State, Data) -> any()
	when
		Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: state(),
		Data ::  statedata().
%% @doc Cleanup and exit.
%% @see //stdlib/gen_statem:terminate/3
%% @private
%%
terminate(_Reason, _State, _Data) ->
	ok.

-spec code_change(OldVsn, OldState, OldData, Extra) -> Result
	when
		OldVsn :: Version | {down, Version},
		Version ::  term(),
		OldState :: state(),
		OldData :: statedata(),
		Extra :: term(),
		Result :: {ok, NewState, NewData} |  Reason,
		NewState :: state(),
		NewData :: statedata(),
		Reason :: term().
%% @doc Update internal state data during a release upgrade&#047;downgrade.
%% @see //stdlib/gen_statem:code_change/3
%% @private
%%
code_change(_OldVsn, OldState, OldData, _Extra) ->
	{ok, OldState, OldData}.

%%----------------------------------------------------------------------
%%  private api
%%----------------------------------------------------------------------


%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
reject(ID, RequestAuthenticator, Secret) ->
	ResponseAttributes = [{?ReplyMessage, "Unable to comply"}],
	AttributeList1 = radius_attributes:add(?MessageAuthenticator,
			<<0:128>>, ResponseAttributes),
	Attributes1 = radius_attributes:codec(AttributeList1),
	Length = size(Attributes1) + 20,
	MessageAuthenticator = ?HMAC(Secret,
			[<<?AccessReject, ID, Length:16>>,
			RequestAuthenticator, Attributes1]),
	AttributeList2 = radius_attributes:store(?MessageAuthenticator,
			MessageAuthenticator, AttributeList1),
	Attributes2 = radius_attributes:codec(AttributeList2),
	ResponseAuthenticator = crypto:hash(md5,
			[<<?AccessReject, ID, Length:16>>,
			RequestAuthenticator, Attributes2, Secret]),
	#radius{code = ?AccessReject, id = ID,
			authenticator = ResponseAuthenticator,
			attributes = Attributes2}.

