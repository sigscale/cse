%%% cse_slp_prepaid_diameter_fsm.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2022 SigScale Global Inc.
%%% @author Refath Wadood <refath@sigscale.org> [http://www.sigscale.org]
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
%%% 	for CAMEL Application Part (CAP) within the
%%% 	{@link //cse. cse} application.
%%%
%%% 	This module is not intended to be started directly but rather
%%% 	pushed onto the callback stack of the
%%% 	{@link //cse/cse_slp_cap_fsm. cse_slp_cap_fsm}
%%% 	{@link //stdlib/gen_statem. gen_statem} behaviour callback
%%% 	module which handles initialization, dialog `BEGIN' and the
%%% 	first `Invoke' with `InitialDP'.  The Service Key is used to
%%% 	lookup the SLP implementation module (this) and push it onto
%%% 	the callback stack.
%%%
-module(cse_slp_prepaid_diameter_fsm).
-copyright('Copyright (c) 2021-2022 SigScale Global Inc.').
-author('Refath Wadood <refath@sigscale.org>').

-behaviour(gen_statem).

%% export the callbacks needed for gen_statem behaviour
-export([init/1, handle_event/4, callback_mode/0,
			terminate/3, code_change/4]).
%% export the callbacks for gen_statem states.
-export([null/3, collect_information/3, exception/3]).
%% export the private api
-export([nrf_start_reply/2]).

-include_lib("kernel/include/logger.hrl").
-include_lib("cse/include/cse_codec.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_cc_application_rfc4006.hrl").

-define(RO_APPLICATION_ID, 4).
-define(IANA_PEN_SigScale, 50386).

-type state() :: null | collect_information | exception.

-type statedata() :: #{nrf_profile => atom() | undefined,
		nrf_uri => string() | undefined,
		nrf_location => string() | undefined,
		nrf_reqid => reference() | undefined,
		imsi => integer() | undefined,
		calling => integer() | undefined,
		msisdn => pos_integer() | undefined,
		context => binary() | undefined,
		mscc => [#'3gpp_ro_Multiple-Services-Credit-Control'{}] | undefined,
		reqt => integer() | undefined,
		reqno =>  integer() | undefined,
		session_id => binary() | undefined,
		ohost => binary() | undefined,
		orealm => binary() | undefined}.

-type mscc() :: #{rg => pos_integer() | undefined,
		si => pos_integer() | undefined,
		usu => #{unit() => pos_integer()} | undefined,
		rsu => #{unit() => pos_integer()} | undefined}.

-type unit() :: time | downlinkVolume | uplinkVolume
				| totalVolume | serviceSpecificUnit.

-type service_rating() :: #{serviceContextId => string(),
		serviceId => pos_integer(), ratingGroup => pos_integer(),
		requestSubType => string(), consumedUnit => #{unit() => pos_integer()},
		grantedUnit => #{unit() => pos_integer()}}.

%%----------------------------------------------------------------------
%%  The cse_slp_prepaid_diameter_fsm gen_statem callbacks
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
init(_Args) ->
	{ok, null, #{}}.

-spec null(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>null</em> state.
%% @private
null(enter, null = _EventContent, _Data) ->
	keep_state_and_data;
null({call, From}, #'3gpp_ro_CCR'{} = EventContent, Data) ->
	{ok, Profile} = application:get_env(cse, nrf_profile),
	{ok, URI} = application:get_env(cse, nrf_uri),
	NewData = Data#{from => From, nrf_profile => Profile, nrf_uri => URI},
	Actions = [{next_event, internal, EventContent}],
	{next_state, collect_information, NewData, Actions};
null(enter, _EventContent, _Data) ->
	keep_state_and_data.

-spec collect_information(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>collect_information</em> state.
%% @private
collect_information(enter, null = _EventContent, _Data) ->
	keep_state_and_data;
collect_information(internal, #'3gpp_ro_CCR'{
		'Session-Id' = SessionId, 'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
		'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST',
		'Service-Context-Id' = SvcContextId,
		'CC-Request-Number' = RequestNum,
		'Subscription-Id' = Subscribers,
		'Multiple-Services-Credit-Control' = MSCC,
		'Service-Information' = _ServiceInformation} = _EventContent, Data) ->
	IMSI = subscriber_id(Subscribers, imsi),
	MSISDN = subscriber_id(Subscribers, msisdn),
	NewData = Data#{imsi => IMSI, msisdn => MSISDN,
			calling => MSISDN, context => SvcContextId,
			mscc => MSCC, session_id => SessionId, ohost => OHost,
			orealm => ORealm, reqno => RequestNum,
			reqt => ?'3GPP_CC-REQUEST-TYPE_INITIAL_REQUEST'},
	nrf_start(NewData);
collect_information(cast, {nrf_start,
		{RequestId, {{_Version, 201, _Phrase}, Headers, Body}}},
		#{from := From, nrf_reqid := RequestId, msisdn := MSISDN, calling := MSISDN,
				nrf_profile := Profile, nrf_uri := URI, mscc := MSCC,
				ohost := OHost, orealm := ORealm, reqno := RequestNum,
				session_id := SessionId,
				reqt := RequestType} = Data) ->
	case {zj:decode(Body), lists:keyfind("location", 1, Headers)} of
		{{ok, #{"serviceRating" := ServiceRating}}, {_, Location}}
				when is_list(Location) ->
			try
				NewData = Data#{nrf_location => Location},
				Container = build_container(MSCC),
				{ResultCode, NewMSCC} = build_mscc(ServiceRating, Container),
				Reply = diameter_answer(SessionId, NewMSCC, ResultCode, OHost,
						ORealm, RequestType, RequestNum),
				Actions = [{reply, From, Reply}],
				{next_state, null, NewData, Actions}
			catch
				_:Reason ->
					ResultCode1 = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
					Reply1 = diameter_error(SessionId, ResultCode1, OHost,
							ORealm, RequestType, RequestNum),
					?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
							{profile, Profile}, {uri, URI}, {slpi, self()},
							{origin_host, OHost}, {origin_realm, ORealm},
							{type, start}]),
					Actions1 = [{reply, From, Reply1}],
					{next_state, exception, Data, Actions1}
			end;
		{error, Reason} ->
			ResultCode = ?'DIAMETER_BASE_RESULT-CODE_UNABLE_TO_COMPLY',
			Reply = diameter_error(SessionId, ResultCode, OHost,
					ORealm, RequestType, RequestNum),
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
				{profile, Profile}, {uri, URI}, {slpi, self()},
				{origin_host, OHost}, {origin_realm, ORealm},
				{type, start}]),
			Actions = [{reply, From, Reply}],
			{next_state, exception, Data, Actions}
	end.

-spec exception(EventType, EventContent, Data) -> Result
	when
		EventType :: gen_statem:event_type(),
		EventContent :: term(),
		Data :: statedata(),
		Result :: gen_statem:event_handler_result(state()).
%% @doc Handles events received in the <em>exception</em> state.
%% @private
exception(enter, _EventContent,  _Data)->
	keep_state_and_data;
exception(_EventType, _EventContent, _Data) ->
	keep_state_and_data.

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

-spec nrf_start_reply(ReplyInfo, Fsm) -> ok
	when
		ReplyInfo :: {RequestId, Result} | {RequestId, {error, Reason}},
		RequestId :: reference(),
		Result :: {httpc:status_line(), httpc:headers(), Body},
		Body :: binary(),
		Reason :: term(),
		Fsm :: pid().
%% @doc Handle sending a reply to {@link nrf_start/1}.
%% @private
nrf_start_reply(ReplyInfo, Fsm) ->
	gen_statem:cast(Fsm, {nrf_start, ReplyInfo}).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec nrf_start(Data) -> Result
	when
		Data ::  statedata(),
		Result :: {keep_state, Data} | {next_state, exception, Data}.
%% @doc Start rating a session.
nrf_start(#{msisdn := MSISDN} = Data)
		when is_integer(MSISDN) ->
	nrf_start1(["msisdn-" ++ integer_to_list(MSISDN)], Data);
nrf_start(Data) ->
	nrf_start1([], Data).
%% @hidden
nrf_start1(Subscriber, #{imsi := IMSI} = Data)
		when is_integer(IMSI) ->
	nrf_start2(["imsi-" ++ integer_to_list(IMSI) | Subscriber], Data);
nrf_start1(Subscriber, Data) ->
	nrf_start2(Subscriber, Data).
%% @hidden
nrf_start2(Subscriber, #{mscc := MSCC, context := ServiceContextId} = Data) ->
	ServiceRating = service_rating_inital(mscc(MSCC), ServiceContextId),
	nrf_start3(Subscriber, ServiceRating, service_type(ServiceContextId), Data).
%% @hidden
nrf_start3(Subscriber, ServiceRating, 32251, Data) ->
	Now = erlang:system_time(millisecond),
	Sequence = ets:update_counter(cse_counters, nrf_seq, 1),
	JSON = #{"invocationSequenceNumber" => Sequence,
			"invocationTimeStamp" => cse_log:iso8601(Now),
			"nfConsumerIdentification" => #{"nodeFunctionality" => "OCF"},
			"subscriptionId" => Subscriber,
			"serviceRating" => ServiceRating},
	nrf_start4(JSON, Data).
%% @hidden
nrf_start4(JSON, #{nrf_profile := Profile, nrf_uri := URI} = Data) ->
	MFA = {?MODULE, nrf_start_reply, [self()]},
	Options = [{sync, false}, {receiver, MFA}],
	Headers = [{"accept", "application/json"}],
	Body = zj:encode(JSON),
	Request = {URI ++ "/ratingdata", Headers, "application/json", Body},
	HttpOptions = [{relaxed, true}],
	case httpc:request(post, Request, HttpOptions, Options, Profile) of
		{ok, RequestId} when is_reference(RequestId) ->
			NewData = Data#{nrf_reqid => RequestId},
			{keep_state, NewData};
		{error, {failed_connect, _} = Reason} ->
			?LOG_WARNING([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			{next_state, exception, Data};
		{error, Reason} ->
			?LOG_ERROR([{?MODULE, nrf_start}, {error, Reason},
					{profile, Profile}, {uri, URI}, {slpi, self()}]),
			{next_state, exception, Data}
	end.

-spec mscc(MSCC) -> Result
	when
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		Result :: [mscc()].
%% @doc Convert a list of Diameter MSCCs to a list of equivalent maps.
mscc(MSCC) ->
	mscc(MSCC, []).
%% @hidden
mscc([H | T], Acc) ->
	Amounts = #{rg => rg(H), si => si(H), rsu => rsu(H), usu => usu(H)},
	mscc(T, [Amounts | Acc]);
mscc([], Acc) ->
	lists:reverse(Acc).

%% @hidden
si(#'3gpp_ro_Multiple-Services-Credit-Control'{'Service-Identifier' = [SI]})
		when is_integer(SI) ->
	SI;
si(_) ->
	undefined.

%% @hidden
rg(#'3gpp_ro_Multiple-Services-Credit-Control'{'Rating-Group' = [RG]})
		when is_integer(RG) ->
	RG;
rg(_) ->
	undefined.

%% @hidden
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Time' = [CCTime]}]})
		when is_integer(CCTime), CCTime > 0 ->
	#{time => CCTime};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Total-Octets' = [CCTotalOctets]}]})
		when is_integer(CCTotalOctets), CCTotalOctets > 0 ->
	#{totalVolume => CCTotalOctets};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets],
		'CC-Input-Octets' = [CCInputOctets]}]})
		when is_integer(CCInputOctets), is_integer(CCOutputOctets),
				CCInputOctets > 0, CCOutputOctets > 0 ->
	#{totalVolume => CCInputOctets + CCOutputOctets,
			downlinkVolume => CCOutputOctets, uplinkVolume => CCInputOctets};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]}]})
		when is_integer(CCSpecUnits), CCSpecUnits > 0 ->
	#{serviceSpecificUnit => CCSpecUnits};
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Requested-Service-Unit' = [#'3gpp_ro_Requested-Service-Unit'{}]}) ->
	undefined;
rsu(#'3gpp_ro_Multiple-Services-Credit-Control'{}) ->
	undefined.

%% @hidden
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Time' = [CCTime]} | _]})
		when is_integer(CCTime), CCTime > 0 ->
	#{time => CCTime};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Total-Octets' = [CCTotalOctets]} | _]})
		when is_integer(CCTotalOctets), CCTotalOctets > 0 ->
	#{totalVolume => CCTotalOctets};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Output-Octets' = [CCOutputOctets],
		'CC-Input-Octets' = [CCInputOctets]} | _]})
		when is_integer(CCInputOctets), is_integer(CCOutputOctets),
				CCInputOctets > 0, CCOutputOctets > 0 ->
	#{totalVolume => CCInputOctets + CCOutputOctets,
			downlinkVolume => CCOutputOctets, uplinkVolume => CCInputOctets};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{
		'Used-Service-Unit' = [#'3gpp_ro_Used-Service-Unit'{
		'CC-Service-Specific-Units' = [CCSpecUnits]} | _]})
		when is_integer(CCSpecUnits), CCSpecUnits > 0 ->
	#{serviceSpecificUnit => CCSpecUnits};
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{'Used-Service-Unit' = []}) ->
	undefined;
usu(#'3gpp_ro_Multiple-Services-Credit-Control'{}) ->
	undefined.

%% @hidden
gsu(#{"time" := CCTime})
		when CCTime > 0 ->
	#'3gpp_ro_Granted-Service-Unit'{'CC-Time' = [CCTime]};
gsu(#{"totalVolume" := CCTotalOctets})
		when CCTotalOctets > 0 ->
	#'3gpp_ro_Granted-Service-Unit'{'CC-Total-Octets' = [CCTotalOctets]};
gsu(#{"serviceSpecificUnit" := CCSpecUnits})
		when CCSpecUnits > 0 ->
	#'3gpp_ro_Granted-Service-Unit'{'CC-Service-Specific-Units' = [CCSpecUnits]};
gsu(_) ->
	[].

-spec service_rating_inital(MSCC, ServiceContextId) -> ServiceRating
	when
		MSCC :: [mscc()],
		ServiceContextId :: binary(),
		ServiceRating :: [service_rating()].
%% @doc Build a intial `serviceRating' object.
%% @hidden
service_rating_inital(MSCC, ServiceContextId) ->
	service_rating_inital(MSCC, ServiceContextId, []).
%% @hidden
service_rating_inital([#{} = H| T], ServiceContextId, Acc) ->
	service_rating_inital(T, ServiceContextId,
			[service_rating_inital1(H, ServiceContextId) | Acc]);
service_rating_inital([], _ServiceContextId, Acc) ->
	lists:reverse(Acc).
%% @hidden
service_rating_inital1(#{rg := undefined} = MSCC, ServiceContextId) ->
	Acc = #{serviceContextId => ServiceContextId},
	service_rating_inital2(MSCC, Acc);
service_rating_inital1(#{rg := RG} = MSCC, ServiceContextId)
		when is_integer(RG) ->
	Acc = #{serviceContextId => ServiceContextId, ratingGroup => RG},
	service_rating_inital2(MSCC, Acc).
%% @hidden
service_rating_inital2(#{si := undefined} = MSCC, Acc) ->
	service_rating_inital3(MSCC, Acc);
service_rating_inital2(#{si := SI} = MSCC, Acc)
		when is_integer(SI) ->
	Acc1 = Acc#{serviceId => SI},
	service_rating_inital3(MSCC, Acc1).
%% @hidden
service_rating_inital3(#{rsu := undefined}, Acc) ->
	Acc#{requestSubType => "RESERVE"};
service_rating_inital3(#{rsu := RSU}, Acc) ->
	Acc#{requestSubType => "RESERVE", requestedUnit => RSU}.

-spec subscriber_id(Subscribers, SubIdType) -> SubscriberId
	when
		Subscribers :: [#'3gpp_ro_Subscription-Id'{}],
		SubIdType :: imsi | msisdn,
		SubscriberId :: integer() | undefined.
%% @doc Get a specific Subscriber Id.
%% @hidden
subscriber_id(Subscribers, SubIdType) ->
	subscriber_id1(Subscribers, id_type(SubIdType)).
%% @hidden
subscriber_id1([#'3gpp_ro_Subscription-Id'{'Subscription-Id-Data' = Id,
		'Subscription-Id-Type' = SubIdType} | _], SubIdType) ->
	binary_to_integer(Id);
subscriber_id1([_H | T], SubIdType) ->
	subscriber_id1(T, SubIdType);
subscriber_id1([], _SubIdType) ->
	undefined.

%% @hidden
id_type(imsi) ->
	?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI';
id_type(msisdn) ->
	?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164'.

-spec build_container(MSCC) -> MSCC
	when
		MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}].
%% @doc Build a container for CCR MSCC.
build_container(MSCC) ->
	build_container(MSCC, []).
%% @hidden
build_container([#'3gpp_ro_Multiple-Services-Credit-Control'
		{'Service-Identifier' = SI, 'Rating-Group' = RG} = _MSCC | T], Acc) ->
	NewMSCC = #'3gpp_ro_Multiple-Services-Credit-Control'
			{'Service-Identifier' = SI, 'Rating-Group' = RG},
	build_container(T, [NewMSCC | Acc]);
build_container([], Acc) ->
	lists:reverse(Acc).

%% @hidden
service_type(Id) ->
	% allow ".3gpp.org" or the proper "@3gpp.org"
	case binary:part(Id, size(Id), -8) of
		<<"3gpp.org">> ->
			ServiceContext = binary:part(Id, byte_size(Id) - 14, 5),
			case catch binary_to_integer(ServiceContext) of
				{'EXIT', _} ->
					undefined;
				SeviceType ->
					SeviceType
			end;
		_ ->
			undefined
	end.

-spec build_mscc(ServiceRatings, Container) -> Result
	when
		ServiceRatings :: [service_rating()],
		Container :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
		Result :: {ResultCode, [#'3gpp_ro_Multiple-Services-Credit-Control'{}]},
		ResultCode :: pos_integer().
%% @doc Build a list of CCA MSCCs
build_mscc(ServiceRatings, Container) ->
	build_mscc(ServiceRatings, Container, undefined).
%% @hidden
build_mscc([H | T], Container, FinalResultCode) ->
	F = fun F(#{"serviceId" := SI, "ratingGroup" := RG, "resultCode" := RC} = ServiceRating,
			[#'3gpp_ro_Multiple-Services-Credit-Control'
					{'Service-Identifier' = [SI], 'Rating-Group' = [RG]} = MSCC1 | T1], Acc) ->
				case gsu(maps:get("grantedUnit", ServiceRating)) of
					[] ->
						RC2 = result_code(RC),
						RC3 = case FinalResultCode of
							undefined ->
								RC2;
							_ ->
								FinalResultCode
						end,
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Result-Code' = [RC2]},
						{RC3, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					#'3gpp_ro_Granted-Service-Unit'{} = GSU ->
						RC2 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Granted-Service-Unit' = [GSU],
								'Result-Code' = [RC2]},
						{RC2, lists:reverse(T1) ++ [MSCC2] ++ Acc}
				end;
		F(#{"serviceId" := SI, "resultCode" := RC} = ServiceRating,
			[#'3gpp_ro_Multiple-Services-Credit-Control'
					{'Service-Identifier' = [SI], 'Rating-Group' = []} = MSCC1 | T1], Acc) ->
				case gsu(maps:get("grantedUnit", ServiceRating)) of
					[] ->
						RC2 = result_code(RC),
						RC3 = case FinalResultCode of
							undefined ->
								RC2;
							_ ->
								FinalResultCode
						end,
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Result-Code' = [RC2]},
						{RC3, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					#'3gpp_ro_Granted-Service-Unit'{} = GSU ->
						RC2 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Granted-Service-Unit' = [GSU],
								'Result-Code' = [RC2]},
						{RC2, lists:reverse(T1) ++ [MSCC2] ++ Acc}
				end;
			F(#{"ratingGroup" := RG, "resultCode" := RC} = ServiceRating,
					[#'3gpp_ro_Multiple-Services-Credit-Control'
							{'Service-Identifier' = [], 'Rating-Group' = [RG]} = MSCC1 | T1], Acc) ->
				case gsu(maps:get("grantedUnit", ServiceRating)) of
					[] ->
						RC2 = result_code(RC),
						RC3 = case FinalResultCode of
							undefined ->
								RC2;
							_ ->
								FinalResultCode
						end,
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Result-Code' = [RC2]},
						{RC3, lists:reverse(T1) ++ [MSCC2] ++ Acc};
					#'3gpp_ro_Granted-Service-Unit'{} = GSU ->
						RC2 = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS',
						MSCC2 = MSCC1#'3gpp_ro_Multiple-Services-Credit-Control'{
								'Granted-Service-Unit' = [GSU],
								'Result-Code' = [RC2]},
						{RC2, lists:reverse(T1) ++ [MSCC2] ++ Acc}
				end;
			F(ServiceRating, [H1 | T1], Acc) ->
				F(ServiceRating, T1, [H1 | Acc])
	end,
	{NewFRC, NewContainer} = F(H, Container, []),
	build_mscc(T, NewContainer, NewFRC);
build_mscc([], NewContainer, FinalResultCode) ->
	{FinalResultCode, lists:reverse(NewContainer)}.

-spec diameter_answer(SessionId, MSCC, ResultCode,
		OriginHost, OriginRealm, RequestType, RequestNum) -> Result
	when
			SessionId :: binary(),
			MSCC :: [#'3gpp_ro_Multiple-Services-Credit-Control'{}],
			ResultCode :: pos_integer(),
			OriginHost :: string(),
			OriginRealm :: string(),
			RequestType :: integer(),
			RequestNum :: integer(),
			Result :: #'3gpp_ro_CCA'{}.
%% @doc Build CCA response.
%% @hidden
diameter_answer(SessionId, MSCC, ResultCode,
		OHost, ORealm, RequestType, RequestNum) ->
	#'3gpp_ro_CCA'{'Session-Id' = SessionId,
			'Multiple-Services-Credit-Control' = MSCC,
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNum,
			'Result-Code' = ResultCode}.

-spec diameter_error(SessionId, ResultCode, OriginHost,
		OriginRealm, RequestType, RequestNum) -> Reply
	when
		SessionId :: binary(),
		ResultCode :: pos_integer(),
		OriginHost :: string(),
		OriginRealm :: string(),
		RequestType :: integer(),
		RequestNum :: integer(),
		Reply :: #'3gpp_ro_CCA'{}.
%% @doc Build CCA response indicating an operation failure.
%% @hidden
diameter_error(SessionId, ResultCode, OHost,
		ORealm, RequestType, RequestNum) ->
	#'3gpp_ro_CCA'{'Session-Id' = SessionId,
			'Origin-Host' = OHost, 'Origin-Realm' = ORealm,
			'Auth-Application-Id' = ?RO_APPLICATION_ID,
			'Result-Code' = ResultCode,
			'CC-Request-Type' = RequestType,
			'CC-Request-Number' = RequestNum}.

-spec result_code(ResultCode) -> Result
	when
		ResultCode :: string(),
		Result :: pos_integer().
%% @doc Convert a Nrf ResultCode to a Diameter ResultCode
%% @hidden
result_code("SUCCESS") ->
	?'DIAMETER_BASE_RESULT-CODE_SUCCESS';
result_code("END_USER_SERVICE_DENIED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_END_USER_SERVICE_DENIED';
result_code("QUOTA_LIMIT_REACHED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_CREDIT_LIMIT_REACHED';
result_code("USER_UNKNOWN") ->
	?'DIAMETER_CC_APP_RESULT-CODE_USER_UNKNOWN';
result_code("RATING_FAILED") ->
	?'DIAMETER_CC_APP_RESULT-CODE_RATING_FAILED'.
