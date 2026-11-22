%%% cse_log_codec_bx.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2024-2025 SigScale Global Inc.
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
-copyright('Copyright (c) 2024-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse_log_codec_bx public API
-export([csv/1]).


%%----------------------------------------------------------------------
%%  The cse_log_codec_bx public API
%%----------------------------------------------------------------------

-spec csv(CDR) -> iodata()
	when
		CDR:: map().
%% @doc Bx interface CODEC for comma seperated values (CSV).
%%
% IMS CDRs
csv(#{recordType := RecordType} = CDR) when
		RecordType == <<"aSRecord">>;
		RecordType == <<"pCSCFRecord">>;
		RecordType == <<"iCSCFRecord">>;
		RecordType == <<"mRFCRecord">>;
		RecordType == <<"mGCFRecord">>;
		RecordType == <<"bGCFRecord">>;
		RecordType == <<"iBCFRecord">>;
		RecordType == <<"eCSCFRecord">>;
		RecordType == <<"tRFRecord">>;
		RecordType == <<"tFRecord">>;
		RecordType == <<"aTCFRecord">> ->
	[maps:get(recordType, CDR), $,,
			maps:get('role-of-Node', CDR, []), $,,
			maps:get(nodeAddress, CDR, []), $,,
			maps:get('session-Id', CDR, []), $,,
			maps:get('outgoingSessionId', CDR, []), $,,
			maps:get('sIP-Method', CDR, []), $,,
			maps:get('list-Of-Calling-Party-Address', CDR, []), $,,
			maps:get('called-Party-Address', CDR, []), $,,
			maps:get('list-of-subscription-ID', CDR, []), $,,
			maps:get('serviceRequestTimeStamp', CDR, []), $,,
			maps:get('serviceRequestTimeStampFraction', CDR, []), $,,
			maps:get('serviceDeliveryEndTimeStamp', CDR, []), $,,
			maps:get('serviceDeliveryEndFraction', CDR, []), $,,
			maps:get('recordOpeningTime', CDR, []), $,,
			maps:get('recordClosureTime', CDR, []), $,,
			maps:get('interOperatorIdentifiers', CDR, []), $,,
			maps:get('localRecordSequenceNumber', CDR, []), $,,
			maps:get('recordSequenceNumber', CDR, []), $,,
			maps:get('causeForRecordClosing', CDR, []), $,,
			maps:get('iMS-Charging-Identifier', CDR, []), $,,
			maps:get('serviceContextID', CDR, []), $,,
			maps:get('iMSVisitedNetworkIdentifier', CDR, []), $,,
			maps:get('accessNetworkInformation', CDR, []), $,,
			maps:get('servedIMEI', CDR, [])];
% CS CDRs
csv(#{recordType := RecordType} = CDR) when
		RecordType == <<"moCallRecord">>;
		RecordType == <<"mtCallRecord">>;
		RecordType == <<"roamingRecord">>;
		RecordType == <<"incGatewayRecord">>;
		RecordType == <<"outGatewayRecord">>;
		RecordType == <<"transitRecord">>;
		RecordType == <<"moSMSRecord">>;
		RecordType == <<"mtSMSRecord">>;
		RecordType == <<"moSMSIWRecord">>;
		RecordType == <<"mtSMSGWRecord">>;
		RecordType == <<"ssActionRecord">>;
		RecordType == <<"hlrIntRecord">>;
		RecordType == <<"locUpdateHLRRecord">>;
		RecordType == <<"locUpdateVLRRecord">>;
		RecordType == <<"commonEquipRecord">>;
		RecordType == <<"recTypeExtensions">>;
		RecordType == <<"termCAMELRecord">>;
		RecordType == <<"mtLCSRecord">>;
		RecordType == <<"moLCSRecord">>;
		RecordType == <<"niLCSRecord">>;
		RecordType == <<"mSCsRVCCRecord">>;
		RecordType == <<"mMTRFRecord">>;
		RecordType == <<"iCSRegisterRecord">> ->
	[maps:get(recordType, CDR, [])];
% PS CDRs
csv(#{recordType := RecordType} = CDR) when
		RecordType == <<"sgsnPDPRecord">>;
		RecordType == <<"sgsnMMRecord">>;
		RecordType == <<"sgsnSMORecord">>;
		RecordType == <<"sgsnSMTRecord">>;
		RecordType == <<"sgsnMTLCSRecord">>;
		RecordType == <<"sgsnMOLCSRecord">>;
		RecordType == <<"sgsnNILCSRecord">>;
		RecordType == <<"sgsnMBMSRecord">>;
		RecordType == <<"ggsnMBMSRecord">>;
		RecordType == <<"sGWRecord">>;
		RecordType == <<"pGWRecord">>;
		RecordType == <<"gwMBMSRecord">>;
		RecordType == <<"tDFRecord">>;
		RecordType == <<"iPERecord">>;
		RecordType == <<"ePDGRecord">>;
		RecordType == <<"tWAGRecord">> ->
	[maps:get(recordType, CDR, [])];
% SMS CDR
csv(#{recordType := RecordType} = CDR) when
		RecordType == <<"sCSMORecord">>;
		RecordType == <<"sCSMTRecord">>;
		RecordType == <<"sCDVTT4Record">>;
		RecordType == <<"sCSMOT4Record">>;
		RecordType == <<"iSMSMORecord">>;
		RecordType == <<"iSMSMTRecord">> ->
	[maps:get(recordType, CDR, [])];
% MMS CDRs
csv(#{recordType := RecordType} = CDR) when
		RecordType == <<"mMO1SRecord">>;
		RecordType == <<"mMO4FRqRecord">>;
		RecordType == <<"mMO4FRsRecord">>;
		RecordType == <<"mMO4DRecord">>;
		RecordType == <<"mMO1DRecord">>;
		RecordType == <<"mMO4RRecord">>;
		RecordType == <<"mMO1RRecord">>;
		RecordType == <<"mMOMDRecord">>;
		RecordType == <<"mMR4FRecord">>;
		RecordType == <<"mMR1NRqRecord">>;
		RecordType == <<"mMR1NRsRecord">>;
		RecordType == <<"mMR1RtRqRecord">>;
		RecordType == <<"mMR1ARecord">>;
		RecordType == <<"mMR4DRqRecord">>;
		RecordType == <<"mMR4DRsRecord">>;
		RecordType == <<"mMR1RRRecord">>;
		RecordType == <<"mMR4RRqRecord">>;
		RecordType == <<"mMR4RRsRecord">>;
		RecordType == <<"mMRMDRecord">>;
		RecordType == <<"mMFRecord">>;
		RecordType == <<"mMBx1SRecord">>;
		RecordType == <<"mMBx1VRecord">>;
		RecordType == <<"mMBx1URecord">>;
		RecordType == <<"mMBx1DRecord">>;
		RecordType == <<"mM7SRecord">>;
		RecordType == <<"mM7DRqRecord">>;
		RecordType == <<"mM7DRsRecord">>;
		RecordType == <<"mM7CRecord">>;
		RecordType == <<"mM7RRecord">>;
		RecordType == <<"mM7DRRqRecord">>;
		RecordType == <<"mM7DRRsRecord">>;
		RecordType == <<"mM7RRqRecord">>;
		RecordType == <<"mM7RRsRecord">> ->
	[maps:get(recordType, CDR, [])];
% Other CDRs
csv(#{} = CDR) ->
	[maps:get(recordType, CDR, [])].

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

