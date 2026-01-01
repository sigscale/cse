%%% cse_rest_res_nchf.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2025 SigScale Global Inc.
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
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //cse. cse} application.
%%%
%%% Handles notifications of policy counter status change,
%%% as a consumer of Nchf, in the spending limits interworking
%%% function (IWF) SLP.
%%%
-module(cse_rest_res_nchf).
-copyright('Copyright (c) 2025 SigScale Global Inc.').

% export cse_rest_res_nchf public API
-export([content_types_accepted/0, content_types_provided/0]).
-export([notification/1, termination/1]).

-include_lib("kernel/include/logger.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_sy_application.hrl").

-define(SY_APPLICATION, cse_diameter_3gpp_sy_application).
-define(SY_APPLICATION_ID, 16777302).

%%----------------------------------------------------------------------
%%  cse_rest_res_nchf public API functions
%%----------------------------------------------------------------------

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/problem+json"].

-spec notification(RequestBody) -> Result
	when
		RequestBody :: list(),
		Result   :: {ok, Headers, Body} | {error, Status, Problem},
		Headers  :: [tuple()],
		Body     :: iolist(),
		Status   :: 400 | 500,
		Problem :: cse_rest:problem().
%% @doc Respond to
%% 	`POST /nchf-spendinglimitcontrol/v1/notify'.
%%
%%    Handle a notification of a policy counter status change.
%%
notification(RequestBody) ->
	notification1(zj:decode(RequestBody)).
%% @hidden
notification1({ok, #{"supi" := SUPI} = SpendingLimitStatus})
		when is_list(SUPI) ->
	notification2(list_to_binary(SUPI), SpendingLimitStatus);
notification1({ok, #{} = _SpendingLimitStatus}) ->
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => "/supi"}],
			status => 400, code => "",
			title => "Missing mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails};
notification1({error, _Partial, _Remaining}) ->
	ProblemDetails = #{cause => "INVALID_MSG_FORMAT",
			status => 400, code => "",
			title => "JSON decode of SpendingLimitStatus failed",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails}.
%% @hidden
notification2(SUPI,
		#{"statusInfos" := StatusInfos} = _SpendingLimitStatus)
		when is_map(StatusInfos) ->
	case status_infos(StatusInfos) of
		{ok, PCSR} ->
			notification3(ets:lookup(nchf_session, SUPI), PCSR);
		{error, Status, Problem} ->
			{error, Status, Problem}
	end;
notification2(_SUPI, _SpendingLimitStatus) ->
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => "/statusInfos"}],
			status => 400, code => "",
			title => "Missing mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails}.
%% @hidden
notification3([Object], PCSR) ->
	notify(Object, PCSR);
notification3([], _PCSR) ->
	ProblemDetails = #{cause => "SUBSCRIPTION_NOT_FOUND",
			status => 404, code => "",
			title => "The notification request is rejected because the"
					" subscription is not found in the NF",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/404"},
	{error, 404, ProblemDetails}.

-spec termination(RequestBody) -> Result
	when
		RequestBody :: list(),
		Result   :: {ok, Headers, Body} | {error, Status, Problem},
		Headers  :: [tuple()],
		Body     :: iolist(),
		Status   :: 400 | 500,
		Problem :: cse_rest:problem().
%% @doc Respond to
%% 	`POST /nchf-spendinglimitcontrol/v1/terminate'.
%%
%%    Handle a termination of the subscription of status changes
%% 	for all policy counters for a subscriber.
%%
termination(RequestBody) ->
	termination1(zj:decode(RequestBody)).
%% @hidden
termination1({ok, #{"supi" := SUPI} = SubscriptionTerminationInfo})
		when is_list(SUPI) ->
	termination2(list_to_binary(SUPI), SubscriptionTerminationInfo);
termination1({ok, #{} = _SubscriptionTerminationInfo}) ->
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => "/supi"}],
			status => 400, code => "",
			title => "Missing mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails};
termination1({error, _Partial, _Remaining}) ->
	ProblemDetails = #{cause => "INVALID_MSG_FORMAT",
			status => 400, code => "",
			title => "JSON decode of SubscriptionTerminationInfo failed",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails}.
%% @hidden
termination2(SUPI,
		#{"termCause" := "REMOVED_SUBSCRIBER" = Cause}) ->
	termination3(ets:lookup(nchf_session, SUPI), Cause);
termination2(_SUPI,
		#{"termCause" := _Cause}) ->
	ProblemDetails = #{cause => "OPTIONAL_IE_INCORRECT ",
			invalidParams => [#{param => "/termCause"}],
			status => 400, code => "",
			title => "Optional attribute in JSON body with"
					"  semantically incorrect value",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails};
termination2(SUPI, _SubscriptionTerminationInfo) ->
	termination3(ets:lookup(nchf_session, SUPI), []).
%% @hidden
termination3([Object], Cause) ->
	terminate(Object, Cause);
termination3([], _Cause) ->
	ProblemDetails = #{cause => "SUBSCRIPTION_NOT_FOUND",
			status => 404, code => "",
			title => "The termination request is rejected because the"
					" subscription is not found in the NF",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/404"},
	{error, 404, ProblemDetails}.

%%----------------------------------------------------------------------
%%  cse_rest_res_nchf private API functions
%%----------------------------------------------------------------------

%% @hidden
status_infos(StatusInfos) ->
	status_infos(maps:to_list(StatusInfos), []).
%% @hidden
status_infos([{PolicyCounterId,
		#{"policyCounterId" := PolicyCounterId} = PolicyCounterInfo} | T],
		Acc) ->
	case policy_counter_info(PolicyCounterId, PolicyCounterInfo) of
		{ok, PCSR} ->
			status_infos(T, [PCSR | Acc]);
		{error, Status, Problem} ->
			{error, Status, Problem}
	end;
status_infos([{PolicyCounterId, #{} = _PolicyCounterInfo} | _T], _Acc) ->
	Param = "/statusInfos/" ++ PolicyCounterId ++ "/policyCounterId",
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => Param}],
			status => 400, code => "",
			title => "Missing mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails};
status_infos([], Acc) ->
	{ok, lists:reverse(Acc)}.

%% @hidden
policy_counter_info(PolicyCounterId,
		#{"currentStatus" := CurrentStatus} = _PolicyCounterInfo)
		when is_list(CurrentStatus) ->
	PCSR = #'3gpp_sy_Policy-Counter-Status-Report'{
			'Policy-Counter-Identifier' = PolicyCounterId,
			'Policy-Counter-Status' = CurrentStatus},
	{ok, PCSR};
policy_counter_info(PolicyCounterId, _PolicyCounterInfo) ->
	Param = "/statusInfos/" ++ PolicyCounterId ++ "/currentStatus",
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => Param}],
			status => 400, code => "",
			title => "Missing mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails}.

%% @hidden
notify({_SUPI, ServiceName, SessionId, OHost, ORealm, DHost, DRealm},
		PCSR) ->
	SNR = #'3gpp_sy_SNR'{'Session-Id' = SessionId,
			'Auth-Application-Id' = ?SY_APPLICATION_ID,
			'Origin-Host' = OHost,
			'Origin-Realm' = ORealm,
			'Destination-Host' = DHost,
			'Destination-Realm' = DRealm,
			'SN-Request-Type' = [0],
			'Policy-Counter-Status-Report' = PCSR},
	Options = [],
	case diameter:call(ServiceName, ?SY_APPLICATION, SNR, Options) of
		{ok, #'3gpp_sy_SNA'{'Result-Code' = [ResultCode]} = _SNA}
				when ResultCode == ?'DIAMETER_BASE_RESULT-CODE_SUCCESS' ->
			{ok, [], []};
		{ok, #'3gpp_sy_SNA'{'Result-Code' = [ResultCode]} = _SNA} ->
			ProblemDetails = #{cause => "SYSTEM_FAILURE",
					status => 500, code => integer_to_list(ResultCode),
					title => "The request is rejected due to generic error"
							" condition in the NF",
					type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
							"TS29571_CommonData.yaml#/components/responses/500"},
			{error, 500, ProblemDetails};
		{ok, #'diameter_base_answer-message'{'Result-Code' = ResultCode}} ->
			ProblemDetails = #{cause => "SYSTEM_FAILURE",
					status => 500, code => integer_to_list(ResultCode),
					title => "The request is rejected due to generic error"
							" condition in the NF",
					type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
							"TS29571_CommonData.yaml#/components/responses/500"},
			{error, 500, ProblemDetails};
		{error, _Reason} ->
			ProblemDetails = #{cause => "SYSTEM_FAILURE",
					status => 500, code => "",
					title => "The request is rejected due to generic error"
							" condition in the NF",
					type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
							"TS29571_CommonData.yaml#/components/responses/500"},
			{error, 500, ProblemDetails}
	end.

%% @hidden
terminate({_SUPI, ServiceName, SessionId, OHost, ORealm, DHost, DRealm},
		_Cause) ->
	SNR = #'3gpp_sy_SNR'{'Session-Id' = SessionId,
			'Auth-Application-Id' = ?SY_APPLICATION_ID,
			'Origin-Host' = OHost,
			'Origin-Realm' = ORealm,
			'Destination-Host' = DHost,
			'Destination-Realm' = DRealm,
			'SN-Request-Type' = [1]},
	Options = [],
	case diameter:call(ServiceName, ?SY_APPLICATION, SNR, Options) of
		{ok, #'3gpp_sy_SNA'{'Result-Code' = [ResultCode]} = _SNA}
				when ResultCode == ?'DIAMETER_BASE_RESULT-CODE_SUCCESS' ->
			{ok, [], []};
		{ok, #'3gpp_sy_SNA'{'Result-Code' = [ResultCode]} = _SNA} ->
			ProblemDetails = #{cause => "SYSTEM_FAILURE",
					status => 500, code => integer_to_list(ResultCode),
					title => "The request is rejected due to generic error"
							" condition in the NF",
					type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
							"TS29571_CommonData.yaml#/components/responses/500"},
			{error, 500, ProblemDetails};
		{ok, #'diameter_base_answer-message'{'Result-Code' = ResultCode}} ->
			ProblemDetails = #{cause => "SYSTEM_FAILURE",
					status => 500, code => integer_to_list(ResultCode),
					title => "The request is rejected due to generic error"
							" condition in the NF",
					type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
							"TS29571_CommonData.yaml#/components/responses/500"},
			{error, 500, ProblemDetails};
		{error, _Reason} ->
			ProblemDetails = #{cause => "SYSTEM_FAILURE",
					status => 500, code => "",
					title => "The request is rejected due to generic error"
							" condition in the NF",
					type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
							"TS29571_CommonData.yaml#/components/responses/500"},
			{error, 500, ProblemDetails}
	end.

