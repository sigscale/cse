%%% cse_rest_res_nrf.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2026 SigScale Global Inc.
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
%%% Handles notifications for session update or termination
%%% as a consumer of Nrf, in the prepaid SLPs.
%%%
-module(cse_rest_res_nrf).
-copyright('Copyright (c) 2026 SigScale Global Inc.').

% export cse_rest_res_nrf public API
-export([content_types_accepted/0, content_types_provided/0]).
-export([notification/2]).

%%----------------------------------------------------------------------
%%  cse_rest_res_nrf public API functions
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

-spec notification(NotifyId, RequestBody) -> Result
	when
		NotifyId :: uri_string:uri_string(),
		RequestBody :: list(),
		Result   :: {ok, Headers, Body} | {error, Status, Problem},
		Headers  :: [tuple()],
		Body     :: iolist(),
		Status   :: 400 | 500,
		Problem :: cse_rest:problem().
%% @doc Respond to
%% 	`POST /nrf-rating/v1/notify/{NotifyId}'.
%%
%%    Handle a notification for session update or termination.
%%
notification(NotifyId, RequestBody)
		when is_list(NotifyId) ->
	notification1(ocs_rest:notify_id(NotifyId), RequestBody).
%% @hidden
notification1({ok, SLPI}, RequestBody) ->
	notification2(SLPI, zj:decode(RequestBody));
notification1({error, 400}, _RequestBody) ->
	ProblemDetails = #{cause => "INVALID_MSG_FORMAT",
			status => 400, code => "",
			title => "The NotifyId portion of the URI is not valid",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails};
notification1({error, 404}, _RequestBody) ->
	ProblemDetails = #{cause => "RESOURCE_URI_STRUCTURE_NOT_FOUND",
			status => 404, code => "",
			title => "The NotifyId identifies an SLPI which is not found",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 404, ProblemDetails}.
%% @hidden
notification2(SLPI,
		{ok, #{"notificationType" := NotificationType} = RatingNotifyRequest})
		when is_list(NotificationType) ->
	notification3(SLPI, RatingNotifyRequest);
notification2(_SLPI,
		{ok, #{} = _RatingNotifyRequest}) ->
	ProblemDetails = #{cause => "MANDATORY_IE_MISSING",
			invalidParams => [#{param => "/notificationTye"}],
			status => 400, code => "",
			title => "Missing mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails};
notification2(_SLPI,
		{error, _Partial, _Remaining}) ->
	ProblemDetails = #{cause => "INVALID_MSG_FORMAT",
			status => 400, code => "",
			title => "JSON decode of RatingNotifyRequest failed",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails}.
%% @hidden
notification3(SLPI,
		#{"notificationType" := "ABORT_CHARGING"} = RatingNotifyRequest) ->
	gen_statem:cast(SLPI, {notify, RatingNotifyRequest});
notification3(SLPI,
		#{"notificationType" := "REAUTHORIZATION"} = RatingNotifyRequest) ->
	gen_statem:cast(SLPI, {notify, RatingNotifyRequest});
notification3(_SLPI, _RatingNotifyRequest) ->
	ProblemDetails = #{cause => "MANDATORY_IE_INCORRECT",
			invalidParams => [#{param => "/notificationTye"}],
			status => 400, code => "",
			title => "Incorrect value of mandatory attribute in JSON body",
			type => "https://forge.3gpp.org/rep/all/5G_APIs/-/blob/REL-18/"
					"TS29571_CommonData.yaml#/components/responses/400"},
	{error, 400, ProblemDetails}.

%%----------------------------------------------------------------------
%%  cse_rest_res_nrf private API functions
%%----------------------------------------------------------------------

