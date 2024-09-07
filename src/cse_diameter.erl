%%% cse_diameter.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2024 SigScale Global Inc.
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
%%% @doc This library module implements utilities used by diameter
%%% 	callback modules in the {@link //cse. cse} application.
%%%
%%% @reference <a href="https://www.mcc-mnc.com">
%%%   Mobile Country Codes (MCC) and Mobile Network Codes (MNC) </a>
%%%
-module(cse_diameter).
-copyright('Copyright (c) 2016 - 2024 SigScale Global Inc.').

%% export the cse_diameter public API
-export([plmn/1]).

-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include("diameter_gen_ietf.hrl").
-include("diameter_gen_3gpp.hrl").
-include("diameter_gen_3gpp_ro_application.hrl").
-include("diameter_gen_cc_application_rfc4006.hrl").

%%----------------------------------------------------------------------
%%  The cse_diameter public API
%%----------------------------------------------------------------------

-spec plmn(IMSI) -> Result
	when
		IMSI :: binary() | string(),
		Result :: {MCC, MNC, MSN},
		MCC :: [Digit],
		MNC :: [Digit],
		Digit :: 48..57,
		MSN :: string().
%% @doc Extract MCC, MNC and MSN from IMSI.
plmn(IMSI) when is_binary(IMSI) ->
	plmn(binary_to_list(IMSI));
%% Test network
plmn("00101" ++ MSN) ->
	{"001", "01", MSN};
%% Test network
plmn("001001" ++ MSN) ->
	{"001", "001", MSN};
%% Abkhazia, A-Mobile
plmn("28968" ++ MSN) ->
	{"289", "68", MSN};
%% Abkhazia, Aquafon
plmn("28967" ++ MSN) ->
	{"289", "67", MSN};
%% Afghanistan, Afghan Telecom Corp. (AT)
plmn("41288" ++ MSN) ->
	{"412", "88", MSN};
%% Afghanistan, Afghan Telecom Corp. (AT)
plmn("41280" ++ MSN) ->
	{"412", "80", MSN};
%% Afghanistan, Afghan Wireless/AWCC
plmn("41201" ++ MSN) ->
	{"412", "01", MSN};
%% Afghanistan, Areeba/MTN
plmn("41240" ++ MSN) ->
	{"412", "40", MSN};
%% Afghanistan, Etisalat
plmn("41230" ++ MSN) ->
	{"412", "30", MSN};
%% Afghanistan, Etisalat
plmn("41250" ++ MSN) ->
	{"412", "50", MSN};
%% Afghanistan, Roshan/TDCA
plmn("41220" ++ MSN) ->
	{"412", "20", MSN};
%% Afghanistan, WaselTelecom (WT)
plmn("41203" ++ MSN) ->
	{"412", "03", MSN};
%% Albania, AMC/Cosmote
plmn("27601" ++ MSN) ->
	{"276", "01", MSN};
%% Albania, Eagle Mobile
plmn("27603" ++ MSN) ->
	{"276", "03", MSN};
%% Albania, PLUS Communication Sh.a
plmn("27604" ++ MSN) ->
	{"276", "04", MSN};
%% Albania, Vodafone
plmn("27602" ++ MSN) ->
	{"276", "02", MSN};
%% Algeria, ATM Mobils
plmn("60301" ++ MSN) ->
	{"603", "01", MSN};
%% Algeria, Orascom / DJEZZY
plmn("60302" ++ MSN) ->
	{"603", "02", MSN};
%% Algeria, Oreedo/Wataniya / Nedjma
plmn("60303" ++ MSN) ->
	{"603", "03", MSN};
%% American Samoa, Blue Sky Communications
plmn("54411" ++ MSN) ->
	{"544", "11", MSN};
%% Andorra, Mobiland
plmn("21303" ++ MSN) ->
	{"213", "03", MSN};
%% Angola, MoviCel
plmn("63104" ++ MSN) ->
	{"631", "04", MSN};
%% Angola, Unitel
plmn("63102" ++ MSN) ->
	{"631", "02", MSN};
%% Anguilla, Cable and Wireless
plmn("365840" ++ MSN) ->
	{"365", "840", MSN};
%% Anguilla, Digicell / Wireless Vent. Ltd
plmn("36510" ++ MSN) ->
	{"365", "10", MSN};
%% Antigua and Barbuda, APUA PCS
plmn("34430" ++ MSN) ->
	{"344", "30", MSN};
%% Antigua and Barbuda, C & W
plmn("344920" ++ MSN) ->
	{"344", "920", MSN};
%% Antigua and Barbuda, DigiCel/Cing. Wireless
plmn("344930" ++ MSN) ->
	{"344", "930", MSN};
%% Argentina Republic, Claro/ CTI/AMX
plmn("722310" ++ MSN) ->
	{"722", "310", MSN};
%% Argentina Republic, Claro/ CTI/AMX
plmn("722330" ++ MSN) ->
	{"722", "330", MSN};
%% Argentina Republic, Claro/ CTI/AMX
plmn("722320" ++ MSN) ->
	{"722", "320", MSN};
%% Argentina Republic, Compania De Radiocomunicaciones Moviles SA
plmn("72210" ++ MSN) ->
	{"722", "10", MSN};
%% Argentina Republic, Movistar/Telefonica
plmn("72207" ++ MSN) ->
	{"722", "07", MSN};
%% Argentina Republic, Movistar/Telefonica
plmn("72270" ++ MSN) ->
	{"722", "70", MSN};
%% Argentina Republic, Nextel
plmn("72220" ++ MSN) ->
	{"722", "20", MSN};
%% Argentina Republic, Telecom Personal S.A.
plmn("722341" ++ MSN) ->
	{"722", "341", MSN};
%% Argentina Republic, Telecom Personal S.A.
plmn("722340" ++ MSN) ->
	{"722", "340", MSN};
%% Armenia, ArmenTel/Beeline
plmn("28301" ++ MSN) ->
	{"283", "01", MSN};
%% Armenia, Karabakh Telecom
plmn("28304" ++ MSN) ->
	{"283", "04", MSN};
%% Armenia, Orange
plmn("28310" ++ MSN) ->
	{"283", "10", MSN};
%% Armenia, Vivacell
plmn("28305" ++ MSN) ->
	{"283", "05", MSN};
%% Aruba, Digicel
plmn("36320" ++ MSN) ->
	{"363", "20", MSN};
%% Aruba, Digicel
plmn("36302" ++ MSN) ->
	{"363", "02", MSN};
%% Aruba, Setar GSM
plmn("36301" ++ MSN) ->
	{"363", "01", MSN};
%% Australia, AAPT Ltd.
plmn("50514" ++ MSN) ->
	{"505", "14", MSN};
%% Australia, Advanced Comm Tech Pty.
plmn("50524" ++ MSN) ->
	{"505", "24", MSN};
%% Australia, Airnet Commercial Australia Ltd..
plmn("50509" ++ MSN) ->
	{"505", "09", MSN};
%% Australia, Department of Defense
plmn("50504" ++ MSN) ->
	{"505", "04", MSN};
%% Australia, Dialogue Communications Pty Ltd
plmn("50526" ++ MSN) ->
	{"505", "26", MSN};
%% Australia, H3G Ltd.
plmn("50512" ++ MSN) ->
	{"505", "12", MSN};
%% Australia, H3G Ltd.
plmn("50506" ++ MSN) ->
	{"505", "06", MSN};
%% Australia, Pivotel Group Ltd
plmn("50588" ++ MSN) ->
	{"505", "88", MSN};
%% Australia, Lycamobile Pty Ltd
plmn("50519" ++ MSN) ->
	{"505", "19", MSN};
%% Australia, Railcorp/Vodafone
plmn("50508" ++ MSN) ->
	{"505", "08", MSN};
%% Australia, Railcorp/Vodafone
plmn("50599" ++ MSN) ->
	{"505", "99", MSN};
%% Australia, Railcorp/Vodafone
plmn("50513" ++ MSN) ->
	{"505", "13", MSN};
%% Australia, Singtel Optus
plmn("50590" ++ MSN) ->
	{"505", "90", MSN};
%% Australia, Singtel Optus
plmn("50502" ++ MSN) ->
	{"505", "02", MSN};
%% Australia, Telstra Corp. Ltd.
plmn("50572" ++ MSN) ->
	{"505", "72", MSN};
%% Australia, Telstra Corp. Ltd.
plmn("50571" ++ MSN) ->
	{"505", "71", MSN};
%% Australia, Telstra Corp. Ltd.
plmn("50501" ++ MSN) ->
	{"505", "01", MSN};
%% Australia, Telstra Corp. Ltd.
plmn("50511" ++ MSN) ->
	{"505", "11", MSN};
%% Australia, The Ozitel Network Pty.
plmn("50505" ++ MSN) ->
	{"505", "05", MSN};
%% Australia, Victorian Rail Track Corp. (VicTrack)
plmn("50516" ++ MSN) ->
	{"505", "16", MSN};
%% Australia, Vodafone
plmn("50507" ++ MSN) ->
	{"505", "07", MSN};
%% Australia, Vodafone
plmn("50503" ++ MSN) ->
	{"505", "03", MSN};
%% Austria, A1 MobilKom
plmn("23202" ++ MSN) ->
	{"232", "02", MSN};
%% Austria, A1 MobilKom
plmn("23211" ++ MSN) ->
	{"232", "11", MSN};
%% Austria, A1 MobilKom
plmn("23209" ++ MSN) ->
	{"232", "09", MSN};
%% Austria, A1 MobilKom
plmn("23201" ++ MSN) ->
	{"232", "01", MSN};
%% Austria, T-Mobile/Telering
plmn("23215" ++ MSN) ->
	{"232", "15", MSN};
%% Austria, Fix Line
plmn("23200" ++ MSN) ->
	{"232", "00", MSN};
%% Austria, H3G
plmn("23210" ++ MSN) ->
	{"232", "10", MSN};
%% Austria, H3G
plmn("23214" ++ MSN) ->
	{"232", "14", MSN};
%% Austria, Mtel
plmn("23220" ++ MSN) ->
	{"232", "20", MSN};
%% Austria, 3/Orange/One Connect
plmn("23206" ++ MSN) ->
	{"232", "06", MSN};
%% Austria, 3/Orange/One Connect
plmn("23205" ++ MSN) ->
	{"232", "05", MSN};
%% Austria, 3/Orange/One Connect
plmn("23212" ++ MSN) ->
	{"232", "12", MSN};
%% Austria, Spusu/Mass Response
plmn("23217" ++ MSN) ->
	{"232", "17", MSN};
%% Austria, T-Mobile/Telering
plmn("23207" ++ MSN) ->
	{"232", "07", MSN};
%% Austria, T-Mobile/Telering
plmn("23204" ++ MSN) ->
	{"232", "04", MSN};
%% Austria, T-Mobile/Telering
plmn("23203" ++ MSN) ->
	{"232", "03", MSN};
%% Austria, T-Mobile/Telering
plmn("23213" ++ MSN) ->
	{"232", "13", MSN};
%% Austria, Tele2
plmn("23219" ++ MSN) ->
	{"232", "19", MSN};
%% Austria, A1 MobilKom
plmn("23208" ++ MSN) ->
	{"232", "08", MSN};
%% Azerbaijan, Azercell Telekom B.M.
plmn("40001" ++ MSN) ->
	{"400", "01", MSN};
%% Azerbaijan, Azerfon.
plmn("40004" ++ MSN) ->
	{"400", "04", MSN};
%% Azerbaijan, CATEL
plmn("40003" ++ MSN) ->
	{"400", "03", MSN};
%% Azerbaijan, J.V. Bakcell GSM 2000
plmn("40002" ++ MSN) ->
	{"400", "02", MSN};
%% Azerbaijan, Naxtel
plmn("40006" ++ MSN) ->
	{"400", "06", MSN};
%% Bahamas, Aliv/Cable Bahamas
plmn("364490" ++ MSN) ->
	{"364", "490", MSN};
%% Bahamas, Bahamas Telco. Comp.
plmn("364390" ++ MSN) ->
	{"364", "390", MSN};
%% Bahamas, Bahamas Telco. Comp.
plmn("36430" ++ MSN) ->
	{"364", "30", MSN};
%% Bahamas, Bahamas Telco. Comp.
plmn("36439" ++ MSN) ->
	{"364", "39", MSN};
%% Bahamas, Smart Communications
plmn("36403" ++ MSN) ->
	{"364", "03", MSN};
%% Bahrain, Batelco
plmn("42601" ++ MSN) ->
	{"426", "01", MSN};
%% Bahrain, ZAIN/Vodafone
plmn("42602" ++ MSN) ->
	{"426", "02", MSN};
%% Bahrain, VIVA
plmn("42604" ++ MSN) ->
	{"426", "04", MSN};
%% Bangladesh, Robi/Aktel
plmn("47002" ++ MSN) ->
	{"470", "02", MSN};
%% Bangladesh, Citycell
plmn("47006" ++ MSN) ->
	{"470", "06", MSN};
%% Bangladesh, Citycell
plmn("47005" ++ MSN) ->
	{"470", "05", MSN};
%% Bangladesh, GrameenPhone
plmn("47001" ++ MSN) ->
	{"470", "01", MSN};
%% Bangladesh, Orascom/Banglalink
plmn("47003" ++ MSN) ->
	{"470", "03", MSN};
%% Bangladesh, TeleTalk
plmn("47004" ++ MSN) ->
	{"470", "04", MSN};
%% Bangladesh, Airtel/Warid
plmn("47007" ++ MSN) ->
	{"470", "07", MSN};
%% Barbados, LIME
plmn("342600" ++ MSN) ->
	{"342", "600", MSN};
%% Barbados, Cingular Wireless
plmn("342810" ++ MSN) ->
	{"342", "810", MSN};
%% Barbados, Digicel
plmn("342750" ++ MSN) ->
	{"342", "750", MSN};
%% Barbados, Digicel
plmn("34250" ++ MSN) ->
	{"342", "50", MSN};
%% Barbados, Sunbeach
plmn("342820" ++ MSN) ->
	{"342", "820", MSN};
%% Belarus, BelCel JV
plmn("25703" ++ MSN) ->
	{"257", "03", MSN};
%% Belarus, BeST
plmn("25704" ++ MSN) ->
	{"257", "04", MSN};
%% Belarus, MDC/Velcom
plmn("25701" ++ MSN) ->
	{"257", "01", MSN};
%% Belarus, MTS
plmn("25702" ++ MSN) ->
	{"257", "02", MSN};
%% Belgium, Base/KPN
plmn("20620" ++ MSN) ->
	{"206", "20", MSN};
%% Belgium, Belgacom/Proximus
plmn("20601" ++ MSN) ->
	{"206", "01", MSN};
%% Belgium, Lycamobile Belgium
plmn("20606" ++ MSN) ->
	{"206", "06", MSN};
%% Belgium, Mobistar/Orange
plmn("20610" ++ MSN) ->
	{"206", "10", MSN};
%% Belgium, SNCT/NMBS
plmn("20602" ++ MSN) ->
	{"206", "02", MSN};
%% Belgium, Telenet NV
plmn("20605" ++ MSN) ->
	{"206", "05", MSN};
%% Belgium, VOO
plmn("20608" ++ MSN) ->
	{"206", "08", MSN};
%% Belize, DigiCell
plmn("70267" ++ MSN) ->
	{"702", "67", MSN};
%% Belize, International Telco (INTELCO)
plmn("70268" ++ MSN) ->
	{"702", "68", MSN};
%% Benin, Bell Benin/BBCOM
plmn("61604" ++ MSN) ->
	{"616", "04", MSN};
%% Benin, Etisalat/MOOV
plmn("61602" ++ MSN) ->
	{"616", "02", MSN};
%% Benin, GloMobile
plmn("61605" ++ MSN) ->
	{"616", "05", MSN};
%% Benin, Libercom
plmn("61601" ++ MSN) ->
	{"616", "01", MSN};
%% Benin, MTN/Spacetel
plmn("61603" ++ MSN) ->
	{"616", "03", MSN};
%% Bermuda, Bermuda Digital Communications Ltd (BDC)
plmn("35000" ++ MSN) ->
	{"350", "00", MSN};
%% Bermuda, CellOne Ltd
plmn("35099" ++ MSN) ->
	{"350", "99", MSN};
%% Bermuda, DigiCel / Cingular
plmn("35010" ++ MSN) ->
	{"350", "10", MSN};
%% Bermuda, M3 Wireless Ltd
plmn("35002" ++ MSN) ->
	{"350", "02", MSN};
%% Bermuda, Telecommunications (Bermuda & West Indies) Ltd (Digicel Bermuda)
plmn("35001" ++ MSN) ->
	{"350", "01", MSN};
%% Bhutan, B-Mobile
plmn("40211" ++ MSN) ->
	{"402", "11", MSN};
%% Bhutan, Bhutan Telecom Ltd (BTL)
plmn("40217" ++ MSN) ->
	{"402", "17", MSN};
%% Bhutan, TashiCell
plmn("40277" ++ MSN) ->
	{"402", "77", MSN};
%% Bolivia, Entel Pcs
plmn("73602" ++ MSN) ->
	{"736", "02", MSN};
%% Bolivia, Viva/Nuevatel
plmn("73601" ++ MSN) ->
	{"736", "01", MSN};
%% Bolivia, Tigo
plmn("73603" ++ MSN) ->
	{"736", "03", MSN};
%% Bosnia & Herzegov., BH Mobile
plmn("21890" ++ MSN) ->
	{"218", "90", MSN};
%% Bosnia & Herzegov., Eronet Mobile
plmn("21803" ++ MSN) ->
	{"218", "03", MSN};
%% Bosnia & Herzegov., M-Tel
plmn("21805" ++ MSN) ->
	{"218", "05", MSN};
%% Botswana, BeMOBILE
plmn("65204" ++ MSN) ->
	{"652", "04", MSN};
%% Botswana, Mascom Wireless (Pty) Ltd.
plmn("65201" ++ MSN) ->
	{"652", "01", MSN};
%% Botswana, Orange
plmn("65202" ++ MSN) ->
	{"652", "02", MSN};
%% Brazil, AmericaNet
plmn("72426" ++ MSN) ->
	{"724", "26", MSN};
%% Brazil, Claro/Albra/America Movil
plmn("72412" ++ MSN) ->
	{"724", "12", MSN};
%% Brazil, Claro/Albra/America Movil
plmn("72438" ++ MSN) ->
	{"724", "38", MSN};
%% Brazil, Claro/Albra/America Movil
plmn("72405" ++ MSN) ->
	{"724", "05", MSN};
%% Brazil, Vivo S.A./Telemig
plmn("72401" ++ MSN) ->
	{"724", "01", MSN};
%% Brazil, CTBC Celular SA (CTBC)
plmn("72433" ++ MSN) ->
	{"724", "33", MSN};
%% Brazil, CTBC Celular SA (CTBC)
plmn("72432" ++ MSN) ->
	{"724", "32", MSN};
%% Brazil, CTBC Celular SA (CTBC)
plmn("72434" ++ MSN) ->
	{"724", "34", MSN};
%% Brazil, TIM
plmn("72408" ++ MSN) ->
	{"724", "08", MSN};
%% Brazil, Nextel (Telet)
plmn("72439" ++ MSN) ->
	{"724", "39", MSN};
%% Brazil, Nextel (Telet)
plmn("72400" ++ MSN) ->
	{"724", "00", MSN};
%% Brazil, Oi (TNL PCS / Oi)
plmn("72430" ++ MSN) ->
	{"724", "30", MSN};
%% Brazil, Oi (TNL PCS / Oi)
plmn("72431" ++ MSN) ->
	{"724", "31", MSN};
%% Brazil, Brazil Telcom
plmn("72416" ++ MSN) ->
	{"724", "16", MSN};
%% Brazil, Amazonia Celular S/A
plmn("72424" ++ MSN) ->
	{"724", "24", MSN};
%% Brazil, PORTO SEGURO TELECOMUNICACOES
plmn("72454" ++ MSN) ->
	{"724", "54", MSN};
%% Brazil, Sercontel Cel
plmn("72415" ++ MSN) ->
	{"724", "15", MSN};
%% Brazil, CTBC/Triangulo
plmn("72407" ++ MSN) ->
	{"724", "07", MSN};
%% Brazil, Vivo S.A./Telemig
plmn("72419" ++ MSN) ->
	{"724", "19", MSN};
%% Brazil, TIM
plmn("72403" ++ MSN) ->
	{"724", "03", MSN};
%% Brazil, TIM
plmn("72402" ++ MSN) ->
	{"724", "02", MSN};
%% Brazil, TIM
plmn("72404" ++ MSN) ->
	{"724", "04", MSN};
%% Brazil, Unicel do Brasil Telecomunicacoes Ltda
plmn("72437" ++ MSN) ->
	{"724", "37", MSN};
%% Brazil, Vivo S.A./Telemig
plmn("72423" ++ MSN) ->
	{"724", "23", MSN};
%% Brazil, Vivo S.A./Telemig
plmn("72411" ++ MSN) ->
	{"724", "11", MSN};
%% Brazil, Vivo S.A./Telemig
plmn("72410" ++ MSN) ->
	{"724", "10", MSN};
%% Brazil, Vivo S.A./Telemig
plmn("72406" ++ MSN) ->
	{"724", "06", MSN};
%% British Virgin Islands, Caribbean Cellular
plmn("348570" ++ MSN) ->
	{"348", "570", MSN};
%% British Virgin Islands, Digicel
plmn("348770" ++ MSN) ->
	{"348", "770", MSN};
%% British Virgin Islands, LIME
plmn("348170" ++ MSN) ->
	{"348", "170", MSN};
%% Brunei Darussalam, b-mobile
plmn("52802" ++ MSN) ->
	{"528", "02", MSN};
%% Brunei Darussalam, Datastream (DTSCom)
plmn("52811" ++ MSN) ->
	{"528", "11", MSN};
%% Brunei Darussalam, Telekom Brunei Bhd (TelBru)
plmn("52801" ++ MSN) ->
	{"528", "01", MSN};
%% Bulgaria, BTC Mobile EOOD (vivatel)
plmn("28406" ++ MSN) ->
	{"284", "06", MSN};
%% Bulgaria, BTC Mobile EOOD (vivatel)
plmn("28403" ++ MSN) ->
	{"284", "03", MSN};
%% Bulgaria, Telenor/Cosmo/Globul
plmn("28405" ++ MSN) ->
	{"284", "05", MSN};
%% Bulgaria, MobilTel AD
plmn("28401" ++ MSN) ->
	{"284", "01", MSN};
%% Burkina Faso, TeleCel
plmn("61303" ++ MSN) ->
	{"613", "03", MSN};
%% Burkina Faso, TeleMob-OnaTel
plmn("61301" ++ MSN) ->
	{"613", "01", MSN};
%% Burkina Faso, Orange/Airtel
plmn("61302" ++ MSN) ->
	{"613", "02", MSN};
%% Burundi, Africel / Safaris
plmn("64202" ++ MSN) ->
	{"642", "02", MSN};
%% Burundi, Lumitel/Viettel
plmn("64208" ++ MSN) ->
	{"642", "08", MSN};
%% Burundi, Onatel / Telecel
plmn("64203" ++ MSN) ->
	{"642", "03", MSN};
%% Burundi, Smart Mobile / LACELL
plmn("64207" ++ MSN) ->
	{"642", "07", MSN};
%% Burundi, Spacetel / Econet / Leo
plmn("64282" ++ MSN) ->
	{"642", "82", MSN};
%% Burundi, Spacetel / Econet / Leo
plmn("64201" ++ MSN) ->
	{"642", "01", MSN};
%% Cambodia, Cambodia Advance Communications Co. Ltd (CADCOMMS)
plmn("45604" ++ MSN) ->
	{"456", "04", MSN};
%% Cambodia, Smart Mobile
plmn("45602" ++ MSN) ->
	{"456", "02", MSN};
%% Cambodia, Viettel/Metfone
plmn("45608" ++ MSN) ->
	{"456", "08", MSN};
%% Cambodia, Mobitel/Cam GSM
plmn("45618" ++ MSN) ->
	{"456", "18", MSN};
%% Cambodia, Mobitel/Cam GSM
plmn("45601" ++ MSN) ->
	{"456", "01", MSN};
%% Cambodia, QB/Cambodia Adv. Comms.
plmn("45603" ++ MSN) ->
	{"456", "03", MSN};
%% Cambodia, SEATEL
plmn("45611" ++ MSN) ->
	{"456", "11", MSN};
%% Cambodia, Smart Mobile
plmn("45605" ++ MSN) ->
	{"456", "05", MSN};
%% Cambodia, Smart Mobile
plmn("45606" ++ MSN) ->
	{"456", "06", MSN};
%% Cambodia, Sotelco/Beeline
plmn("45609" ++ MSN) ->
	{"456", "09", MSN};
%% Cameroon, MTN
plmn("62401" ++ MSN) ->
	{"624", "01", MSN};
%% Cameroon, Nextel
plmn("62404" ++ MSN) ->
	{"624", "04", MSN};
%% Cameroon, Orange
plmn("62402" ++ MSN) ->
	{"624", "02", MSN};
%% Canada, BC Tel Mobility
plmn("302652" ++ MSN) ->
	{"302", "652", MSN};
%% Canada, Bell Aliant
plmn("302630" ++ MSN) ->
	{"302", "630", MSN};
%% Canada, Bell Mobility
plmn("302651" ++ MSN) ->
	{"302", "651", MSN};
%% Canada, Bell Mobility
plmn("302610" ++ MSN) ->
	{"302", "610", MSN};
%% Canada, CityWest Mobility
plmn("302670" ++ MSN) ->
	{"302", "670", MSN};
%% Canada, Clearnet
plmn("302361" ++ MSN) ->
	{"302", "361", MSN};
%% Canada, Clearnet
plmn("302360" ++ MSN) ->
	{"302", "360", MSN};
%% Canada, DMTS Mobility
plmn("302380" ++ MSN) ->
	{"302", "380", MSN};
%% Canada, Globalstar Canada
plmn("302710" ++ MSN) ->
	{"302", "710", MSN};
%% Canada, Latitude Wireless
plmn("302640" ++ MSN) ->
	{"302", "640", MSN};
%% Canada, FIDO (Rogers AT&T/ Microcell)
plmn("302370" ++ MSN) ->
	{"302", "370", MSN};
%% Canada, mobilicity
plmn("302320" ++ MSN) ->
	{"302", "320", MSN};
%% Canada, MT&T Mobility
plmn("302702" ++ MSN) ->
	{"302", "702", MSN};
%% Canada, MTS Mobility
plmn("302655" ++ MSN) ->
	{"302", "655", MSN};
%% Canada, MTS Mobility
plmn("302660" ++ MSN) ->
	{"302", "660", MSN};
%% Canada, NB Tel Mobility
plmn("302701" ++ MSN) ->
	{"302", "701", MSN};
%% Canada, New Tel Mobility
plmn("302703" ++ MSN) ->
	{"302", "703", MSN};
%% Canada, Public Mobile
plmn("302760" ++ MSN) ->
	{"302", "760", MSN};
%% Canada, Quebectel Mobility
plmn("302657" ++ MSN) ->
	{"302", "657", MSN};
%% Canada, Rogers AT&T Wireless
plmn("302720" ++ MSN) ->
	{"302", "720", MSN};
%% Canada, Sask Tel Mobility
plmn("302654" ++ MSN) ->
	{"302", "654", MSN};
%% Canada, Sask Tel Mobility
plmn("302780" ++ MSN) ->
	{"302", "780", MSN};
%% Canada, Sask Tel Mobility
plmn("302680" ++ MSN) ->
	{"302", "680", MSN};
%% Canada, Tbay Mobility
plmn("302656" ++ MSN) ->
	{"302", "656", MSN};
%% Canada, Telus Mobility
plmn("302653" ++ MSN) ->
	{"302", "653", MSN};
%% Canada, Telus Mobility
plmn("302220" ++ MSN) ->
	{"302", "220", MSN};
%% Canada, Videotron
plmn("302500" ++ MSN) ->
	{"302", "500", MSN};
%% Canada, WIND
plmn("302490" ++ MSN) ->
	{"302", "490", MSN};
%% Cape Verde, CV Movel
plmn("62501" ++ MSN) ->
	{"625", "01", MSN};
%% Cape Verde, T+ Telecom
plmn("62502" ++ MSN) ->
	{"625", "02", MSN};
%% Cayman Islands, Digicel Cayman Ltd
plmn("34650" ++ MSN) ->
	{"346", "50", MSN};
%% Cayman Islands, Digicel Ltd.
plmn("34606" ++ MSN) ->
	{"346", "06", MSN};
%% Cayman Islands, LIME / Cable & Wirel.
plmn("346140" ++ MSN) ->
	{"346", "140", MSN};
%% Central African Rep., Centrafr. Telecom+
plmn("62301" ++ MSN) ->
	{"623", "01", MSN};
%% Central African Rep., Nationlink
plmn("62304" ++ MSN) ->
	{"623", "04", MSN};
%% Central African Rep., Orange/Celca
plmn("62303" ++ MSN) ->
	{"623", "03", MSN};
%% Central African Rep., Telecel Centraf.
plmn("62302" ++ MSN) ->
	{"623", "02", MSN};
%% Chad, Salam/Sotel
plmn("62204" ++ MSN) ->
	{"622", "04", MSN};
%% Chad, Tchad Mobile
plmn("62202" ++ MSN) ->
	{"622", "02", MSN};
%% Chad, Tigo/Milicom/Tchad Mobile
plmn("62203" ++ MSN) ->
	{"622", "03", MSN};
%% Chad, Airtel/ZAIN/Celtel
plmn("62201" ++ MSN) ->
	{"622", "01", MSN};
%% Chile, Blue Two Chile SA
plmn("73006" ++ MSN) ->
	{"730", "06", MSN};
%% Chile, Celupago SA
plmn("73011" ++ MSN) ->
	{"730", "11", MSN};
%% Chile, Cibeles Telecom SA
plmn("73015" ++ MSN) ->
	{"730", "15", MSN};
%% Chile, Claro
plmn("73003" ++ MSN) ->
	{"730", "03", MSN};
%% Chile, Entel Telefonia
plmn("73010" ++ MSN) ->
	{"730", "10", MSN};
%% Chile, Entel Telefonia Mov
plmn("73001" ++ MSN) ->
	{"730", "01", MSN};
%% Chile, Netline Telefonica Movil Ltda
plmn("73014" ++ MSN) ->
	{"730", "14", MSN};
%% Chile, Nextel SA
plmn("73005" ++ MSN) ->
	{"730", "05", MSN};
%% Chile, Nextel SA
plmn("73004" ++ MSN) ->
	{"730", "04", MSN};
%% Chile, Nextel SA
plmn("73009" ++ MSN) ->
	{"730", "09", MSN};
%% Chile, Sociedad Falabella Movil SPA
plmn("73019" ++ MSN) ->
	{"730", "19", MSN};
%% Chile, TELEFONICA
plmn("73002" ++ MSN) ->
	{"730", "02", MSN};
%% Chile, TELEFONICA
plmn("73007" ++ MSN) ->
	{"730", "07", MSN};
%% Chile, Telestar Movil SA
plmn("73012" ++ MSN) ->
	{"730", "12", MSN};
%% Chile, TESAM SA
plmn("73000" ++ MSN) ->
	{"730", "00", MSN};
%% Chile, Tribe Mobile SPA
plmn("73013" ++ MSN) ->
	{"730", "13", MSN};
%% Chile, VTR Banda Ancha SA
plmn("73008" ++ MSN) ->
	{"730", "08", MSN};
%% China, China Mobile GSM
plmn("46000" ++ MSN) ->
	{"460", "00", MSN};
%% China, China Mobile GSM
plmn("46002" ++ MSN) ->
	{"460", "02", MSN};
%% China, China Mobile GSM
plmn("46007" ++ MSN) ->
	{"460", "07", MSN};
%% China, China Space Mobile Satellite Telecommunications Co. Ltd (China Spacecom)
plmn("46004" ++ MSN) ->
	{"460", "04", MSN};
%% China, China Telecom
plmn("46003" ++ MSN) ->
	{"460", "03", MSN};
%% China, China Telecom
plmn("46005" ++ MSN) ->
	{"460", "05", MSN};
%% China, China Unicom
plmn("46006" ++ MSN) ->
	{"460", "06", MSN};
%% China, China Unicom
plmn("46001" ++ MSN) ->
	{"460", "01", MSN};
%% Colombia, Avantel SAS
plmn("732130" ++ MSN) ->
	{"732", "130", MSN};
%% Colombia, Movistar
plmn("732102" ++ MSN) ->
	{"732", "102", MSN};
%% Colombia, TIGO/Colombia Movil
plmn("732103" ++ MSN) ->
	{"732", "103", MSN};
%% Colombia, TIGO/Colombia Movil
plmn("73201" ++ MSN) ->
	{"732", "01", MSN};
%% Colombia, Comcel S.A. Occel S.A./Celcaribe
plmn("732101" ++ MSN) ->
	{"732", "101", MSN};
%% Colombia, Edatel S.A.
plmn("73202" ++ MSN) ->
	{"732", "02", MSN};
%% Colombia, eTb
plmn("732187" ++ MSN) ->
	{"732", "187", MSN};
%% Colombia, Movistar
plmn("732123" ++ MSN) ->
	{"732", "123", MSN};
%% Colombia, TIGO/Colombia Movil
plmn("732111" ++ MSN) ->
	{"732", "111", MSN};
%% Colombia, UNE EPM Telecomunicaciones SA ESP
plmn("732142" ++ MSN) ->
	{"732", "142", MSN};
%% Colombia, UNE EPM Telecomunicaciones SA ESP
plmn("73220" ++ MSN) ->
	{"732", "20", MSN};
%% Colombia, Virgin Mobile Colombia SAS
plmn("732154" ++ MSN) ->
	{"732", "154", MSN};
%% Comoros, HURI - SNPT
plmn("65401" ++ MSN) ->
	{"654", "01", MSN};
%% Comoros, TELMA TELCO SA
plmn("65402" ++ MSN) ->
	{"654", "02", MSN};
%% "Congo,  Dem. Rep.",Africell
plmn("63090" ++ MSN) ->
	{"630", "90", MSN};
%% "Congo,  Dem. Rep.",Orange RDC sarl
plmn("63086" ++ MSN) ->
	{"630", "86", MSN};
%% "Congo,  Dem. Rep.",SuperCell
plmn("63005" ++ MSN) ->
	{"630", "05", MSN};
%% "Congo,  Dem. Rep.",TIGO/Oasis
plmn("63089" ++ MSN) ->
	{"630", "89", MSN};
%% "Congo,  Dem. Rep.",Vodacom
plmn("63001" ++ MSN) ->
	{"630", "01", MSN};
%% "Congo,  Dem. Rep.",Yozma Timeturns sprl (YTT)
plmn("63088" ++ MSN) ->
	{"630", "88", MSN};
%% "Congo,  Dem. Rep.",Airtel/ZAIN
plmn("63002" ++ MSN) ->
	{"630", "02", MSN};
%% "Congo,  Republic",Airtel SA
plmn("62901" ++ MSN) ->
	{"629", "01", MSN};
%% "Congo,  Republic",Azur SA (ETC)
plmn("62902" ++ MSN) ->
	{"629", "02", MSN};
%% "Congo,  Republic",MTN/Libertis
plmn("62910" ++ MSN) ->
	{"629", "10", MSN};
%% "Congo,  Republic",Warid
plmn("62907" ++ MSN) ->
	{"629", "07", MSN};
%% Cook Islands, Telecom Cook Islands
plmn("54801" ++ MSN) ->
	{"548", "01", MSN};
%% Costa Rica, Claro
plmn("71203" ++ MSN) ->
	{"712", "03", MSN};
%% Costa Rica, ICE
plmn("71201" ++ MSN) ->
	{"712", "01", MSN};
%% Costa Rica, ICE
plmn("71202" ++ MSN) ->
	{"712", "02", MSN};
%% Costa Rica, Movistar
plmn("71204" ++ MSN) ->
	{"712", "04", MSN};
%% Costa Rica, Virtualis
plmn("71220" ++ MSN) ->
	{"712", "20", MSN};
%% Croatia, T-Mobile/Cronet
plmn("21901" ++ MSN) ->
	{"219", "01", MSN};
%% Croatia, Tele2
plmn("21902" ++ MSN) ->
	{"219", "02", MSN};
%% Croatia, VIPnet d.o.o.
plmn("21910" ++ MSN) ->
	{"219", "10", MSN};
%% Cuba, CubaCel/C-COM
plmn("36801" ++ MSN) ->
	{"368", "01", MSN};
%% Curacao, Polycom N.V./ Digicel
plmn("36269" ++ MSN) ->
	{"362", "69", MSN};
%% Cyprus, MTN/Areeba
plmn("28010" ++ MSN) ->
	{"280", "10", MSN};
%% Cyprus, PrimeTel PLC
plmn("28020" ++ MSN) ->
	{"280", "20", MSN};
%% Cyprus, Vodafone/CyTa
plmn("28001" ++ MSN) ->
	{"280", "01", MSN};
%% Czech Rep., Compatel s.r.o.
plmn("23008" ++ MSN) ->
	{"230", "08", MSN};
%% Czech Rep., O2
plmn("23002" ++ MSN) ->
	{"230", "02", MSN};
%% Czech Rep., T-Mobile / RadioMobil
plmn("23001" ++ MSN) ->
	{"230", "01", MSN};
%% Czech Rep., Travel Telekommunikation s.r.o.
plmn("23005" ++ MSN) ->
	{"230", "05", MSN};
%% Czech Rep., Ufone
plmn("23004" ++ MSN) ->
	{"230", "04", MSN};
%% Czech Rep., Vodafone
plmn("23099" ++ MSN) ->
	{"230", "99", MSN};
%% Czech Rep., Vodafone
plmn("23003" ++ MSN) ->
	{"230", "03", MSN};
%% Denmark, ApS KBUS
plmn("23805" ++ MSN) ->
	{"238", "05", MSN};
%% Denmark, Banedanmark
plmn("23823" ++ MSN) ->
	{"238", "23", MSN};
%% Denmark, CoolTEL ApS
plmn("23828" ++ MSN) ->
	{"238", "28", MSN};
%% Denmark, H3G
plmn("23806" ++ MSN) ->
	{"238", "06", MSN};
%% Denmark, Lycamobile Ltd
plmn("23812" ++ MSN) ->
	{"238", "12", MSN};
%% Denmark, Mach Connectivity ApS
plmn("23803" ++ MSN) ->
	{"238", "03", MSN};
%% Denmark, Mundio Mobile
plmn("23807" ++ MSN) ->
	{"238", "07", MSN};
%% Denmark, NextGen Mobile Ltd (CardBoardFish)
plmn("23804" ++ MSN) ->
	{"238", "04", MSN};
%% Denmark, TDC Denmark
plmn("23801" ++ MSN) ->
	{"238", "01", MSN};
%% Denmark, TDC Denmark
plmn("23810" ++ MSN) ->
	{"238", "10", MSN};
%% Denmark, Telenor/Sonofon
plmn("23877" ++ MSN) ->
	{"238", "77", MSN};
%% Denmark, Telenor/Sonofon
plmn("23802" ++ MSN) ->
	{"238", "02", MSN};
%% Denmark, Telia
plmn("23820" ++ MSN) ->
	{"238", "20", MSN};
%% Denmark, Telia
plmn("23830" ++ MSN) ->
	{"238", "30", MSN};
%% Djibouti, Djibouti Telecom SA (Evatis)
plmn("63801" ++ MSN) ->
	{"638", "01", MSN};
%% Dominica, C & W
plmn("366110" ++ MSN) ->
	{"366", "110", MSN};
%% Dominica, Cingular Wireless/Digicel
plmn("36620" ++ MSN) ->
	{"366", "20", MSN};
%% Dominica, Wireless Ventures (Dominica) Ltd (Digicel Dominica)
plmn("36650" ++ MSN) ->
	{"366", "50", MSN};
%% Dominican Republic, Claro
plmn("37002" ++ MSN) ->
	{"370", "02", MSN};
%% Dominican Republic, Orange
plmn("37001" ++ MSN) ->
	{"370", "01", MSN};
%% Dominican Republic, TRIcom
plmn("37003" ++ MSN) ->
	{"370", "03", MSN};
%% Dominican Republic, Viva
plmn("37004" ++ MSN) ->
	{"370", "04", MSN};
%% Ecuador, Claro/Porta
plmn("74001" ++ MSN) ->
	{"740", "01", MSN};
%% Ecuador, CNT Mobile
plmn("74002" ++ MSN) ->
	{"740", "02", MSN};
%% Ecuador, MOVISTAR/OteCel/Failed Call(s)
plmn("74000" ++ MSN) ->
	{"740", "00", MSN};
%% Ecuador, Tuenti
plmn("74003" ++ MSN) ->
	{"740", "03", MSN};
%% Egypt, Orange/Mobinil
plmn("60201" ++ MSN) ->
	{"602", "01", MSN};
%% Egypt, ETISALAT
plmn("60203" ++ MSN) ->
	{"602", "03", MSN};
%% Egypt, Vodafone/Mirsfone
plmn("60202" ++ MSN) ->
	{"602", "02", MSN};
%% Egypt, WE/Telecom
plmn("60204" ++ MSN) ->
	{"602", "04", MSN};
%% El Salvador, CLARO/CTE
plmn("70601" ++ MSN) ->
	{"706", "01", MSN};
%% El Salvador, Digicel
plmn("70602" ++ MSN) ->
	{"706", "02", MSN};
%% El Salvador, INTELFON SA de CV
plmn("70605" ++ MSN) ->
	{"706", "05", MSN};
%% El Salvador, Telefonica
plmn("70604" ++ MSN) ->
	{"706", "04", MSN};
%% El Salvador, Telemovil
plmn("70603" ++ MSN) ->
	{"706", "03", MSN};
%% Equatorial Guinea, HiTs-GE
plmn("62703" ++ MSN) ->
	{"627", "03", MSN};
%% Equatorial Guinea, ORANGE/GETESA
plmn("62701" ++ MSN) ->
	{"627", "01", MSN};
%% Eritrea, Eritel
plmn("65701" ++ MSN) ->
	{"657", "01", MSN};
%% Estonia, EMT GSM
plmn("24801" ++ MSN) ->
	{"248", "01", MSN};
%% Estonia, Radiolinja Eesti
plmn("24802" ++ MSN) ->
	{"248", "02", MSN};
%% Estonia, Tele2 Eesti AS
plmn("24803" ++ MSN) ->
	{"248", "03", MSN};
%% Estonia, Top Connect OU
plmn("24804" ++ MSN) ->
	{"248", "04", MSN};
%% Ethiopia, ETH/MTN
plmn("63601" ++ MSN) ->
	{"636", "01", MSN};
%% Falkland Islands (Malvinas), Cable and Wireless South Atlantic Ltd (Falkland Islands
plmn("75001" ++ MSN) ->
	{"750", "01", MSN};
%% Faroe Islands, Edge Mobile Sp/F
plmn("28803" ++ MSN) ->
	{"288", "03", MSN};
%% Faroe Islands, Faroese Telecom
plmn("28801" ++ MSN) ->
	{"288", "01", MSN};
%% Faroe Islands, Kall GSM
plmn("28802" ++ MSN) ->
	{"288", "02", MSN};
%% Fiji, DigiCell
plmn("54202" ++ MSN) ->
	{"542", "02", MSN};
%% Fiji, Vodafone
plmn("54201" ++ MSN) ->
	{"542", "01", MSN};
%% Finland, Alands
plmn("24414" ++ MSN) ->
	{"244", "14", MSN};
%% Finland, Compatel Ltd
plmn("24426" ++ MSN) ->
	{"244", "26", MSN};
%% Finland, DNA/Finnet
plmn("24404" ++ MSN) ->
	{"244", "04", MSN};
%% Finland, DNA/Finnet
plmn("24403" ++ MSN) ->
	{"244", "03", MSN};
%% Finland, DNA/Finnet
plmn("24413" ++ MSN) ->
	{"244", "13", MSN};
%% Finland, DNA/Finnet
plmn("24412" ++ MSN) ->
	{"244", "12", MSN};
%% Finland, Elisa/Saunalahti
plmn("24405" ++ MSN) ->
	{"244", "05", MSN};
%% Finland, Elisa/Saunalahti
plmn("24421" ++ MSN) ->
	{"244", "21", MSN};
%% Finland, ID-Mobile
plmn("24482" ++ MSN) ->
	{"244", "82", MSN};
%% Finland, Mundio Mobile (Finland) Ltd
plmn("24411" ++ MSN) ->
	{"244", "11", MSN};
%% Finland, Nokia Oyj
plmn("24409" ++ MSN) ->
	{"244", "09", MSN};
%% Finland, TDC Oy Finland
plmn("24410" ++ MSN) ->
	{"244", "10", MSN};
%% Finland, TeliaSonera
plmn("24491" ++ MSN) ->
	{"244", "91", MSN};
%% France, AFONE SA
plmn("20827" ++ MSN) ->
	{"208", "27", MSN};
%% France, Association Plate-forme Telecom
plmn("20892" ++ MSN) ->
	{"208", "92", MSN};
%% France, Astrium
plmn("20828" ++ MSN) ->
	{"208", "28", MSN};
%% France, Bouygues Telecom
plmn("20821" ++ MSN) ->
	{"208", "21", MSN};
%% France, Bouygues Telecom
plmn("20820" ++ MSN) ->
	{"208", "20", MSN};
%% France, Bouygues Telecom
plmn("20888" ++ MSN) ->
	{"208", "88", MSN};
%% France, Lliad/FREE Mobile
plmn("20814" ++ MSN) ->
	{"208", "14", MSN};
%% France, GlobalStar
plmn("20807" ++ MSN) ->
	{"208", "07", MSN};
%% France, GlobalStar
plmn("20806" ++ MSN) ->
	{"208", "06", MSN};
%% France, GlobalStar
plmn("20805" ++ MSN) ->
	{"208", "05", MSN};
%% France, Orange
plmn("20829" ++ MSN) ->
	{"208", "29", MSN};
%% France, Legos - Local Exchange Global Operation Services SA
plmn("20817" ++ MSN) ->
	{"208", "17", MSN};
%% France, Lliad/FREE Mobile
plmn("20816" ++ MSN) ->
	{"208", "16", MSN};
%% France, Lliad/FREE Mobile
plmn("20815" ++ MSN) ->
	{"208", "15", MSN};
%% France, Lycamobile SARL
plmn("20825" ++ MSN) ->
	{"208", "25", MSN};
%% France, MobiquiThings
plmn("20824" ++ MSN) ->
	{"208", "24", MSN};
%% France, MobiquiThings
plmn("20803" ++ MSN) ->
	{"208", "03", MSN};
%% France, Mundio Mobile (France) Ltd
plmn("20831" ++ MSN) ->
	{"208", "31", MSN};
%% France, NRJ
plmn("20826" ++ MSN) ->
	{"208", "26", MSN};
%% France, Virgin Mobile/Omer
plmn("20889" ++ MSN) ->
	{"208", "89", MSN};
%% France, Virgin Mobile/Omer
plmn("20823" ++ MSN) ->
	{"208", "23", MSN};
%% France, Orange
plmn("20891" ++ MSN) ->
	{"208", "91", MSN};
%% France, Orange
plmn("20802" ++ MSN) ->
	{"208", "02", MSN};
%% France, Orange
plmn("20801" ++ MSN) ->
	{"208", "01", MSN};
%% France, S.F.R.
plmn("20810" ++ MSN) ->
	{"208", "10", MSN};
%% France, S.F.R.
plmn("20813" ++ MSN) ->
	{"208", "13", MSN};
%% France, S.F.R.
plmn("20809" ++ MSN) ->
	{"208", "09", MSN};
%% France, S.F.R.
plmn("20811" ++ MSN) ->
	{"208", "11", MSN};
%% France, SISTEER
plmn("20804" ++ MSN) ->
	{"208", "04", MSN};
%% France, Tel/Tel
plmn("20800" ++ MSN) ->
	{"208", "00", MSN};
%% France, Transatel SA
plmn("20822" ++ MSN) ->
	{"208", "22", MSN};
%% French Guiana, Bouygues/DigiCel
plmn("34020" ++ MSN) ->
	{"340", "20", MSN};
%% French Guiana, Orange Caribe
plmn("34001" ++ MSN) ->
	{"340", "01", MSN};
%% French Guiana, Outremer Telecom
plmn("34002" ++ MSN) ->
	{"340", "02", MSN};
%% French Guiana, TelCell GSM
plmn("34003" ++ MSN) ->
	{"340", "03", MSN};
%% French Guiana, TelCell GSM
plmn("34011" ++ MSN) ->
	{"340", "11", MSN};
%% French Polynesia, Pacific Mobile Telecom (PMT)
plmn("54715" ++ MSN) ->
	{"547", "15", MSN};
%% French Polynesia, Vini/Tikiphone
plmn("54720" ++ MSN) ->
	{"547", "20", MSN};
%% Gabon, Azur/Usan S.A.
plmn("62804" ++ MSN) ->
	{"628", "04", MSN};
%% Gabon, Libertis S.A.
plmn("62801" ++ MSN) ->
	{"628", "01", MSN};
%% Gabon, MOOV/Telecel
plmn("62802" ++ MSN) ->
	{"628", "02", MSN};
%% Gabon, Airtel/ZAIN/Celtel Gabon S.A.
plmn("62803" ++ MSN) ->
	{"628", "03", MSN};
%% Gambia, Africel
plmn("60702" ++ MSN) ->
	{"607", "02", MSN};
%% Gambia, Comium
plmn("60703" ++ MSN) ->
	{"607", "03", MSN};
%% Gambia, Gamcel
plmn("60701" ++ MSN) ->
	{"607", "01", MSN};
%% Gambia, Q-Cell
plmn("60704" ++ MSN) ->
	{"607", "04", MSN};
%% Georgia, Geocell Ltd.
plmn("28201" ++ MSN) ->
	{"282", "01", MSN};
%% Georgia, Iberiatel Ltd.
plmn("28203" ++ MSN) ->
	{"282", "03", MSN};
%% Georgia, Magti GSM Ltd.
plmn("28202" ++ MSN) ->
	{"282", "02", MSN};
%% Georgia, MobiTel/Beeline
plmn("28204" ++ MSN) ->
	{"282", "04", MSN};
%% Georgia, Silknet
plmn("28205" ++ MSN) ->
	{"282", "05", MSN};
%% Germany, E-Plus
plmn("26217" ++ MSN) ->
	{"262", "17", MSN};
%% Germany, DB Netz AG
plmn("26210" ++ MSN) ->
	{"262", "10", MSN};
%% Germany, E-Plus
plmn("26203" ++ MSN) ->
	{"262", "03", MSN};
%% Germany, E-Plus
plmn("26205" ++ MSN) ->
	{"262", "05", MSN};
%% Germany, E-Plus
plmn("26220" ++ MSN) ->
	{"262", "20", MSN};
%% Germany, E-Plus
plmn("26277" ++ MSN) ->
	{"262", "77", MSN};
%% Germany, E-Plus
plmn("26212" ++ MSN) ->
	{"262", "12", MSN};
%% Germany, Group 3G UMTS
plmn("26214" ++ MSN) ->
	{"262", "14", MSN};
%% Germany, Lycamobile
plmn("26243" ++ MSN) ->
	{"262", "43", MSN};
%% Germany, Mobilcom
plmn("26213" ++ MSN) ->
	{"262", "13", MSN};
%% Germany, O2
plmn("26207" ++ MSN) ->
	{"262", "07", MSN};
%% Germany, O2
plmn("26211" ++ MSN) ->
	{"262", "11", MSN};
%% Germany, O2
plmn("26208" ++ MSN) ->
	{"262", "08", MSN};
%% Germany, Sipgate
plmn("26233" ++ MSN) ->
	{"262", "33", MSN};
%% Germany, Sipgate
plmn("26222" ++ MSN) ->
	{"262", "22", MSN};
%% Germany, T-mobile/Telekom
plmn("26201" ++ MSN) ->
	{"262", "01", MSN};
%% Germany, T-mobile/Telekom
plmn("26206" ++ MSN) ->
	{"262", "06", MSN};
%% Germany, Telogic/ViStream
plmn("26216" ++ MSN) ->
	{"262", "16", MSN};
%% Germany, Vodafone D2
plmn("26209" ++ MSN) ->
	{"262", "09", MSN};
%% Germany, Vodafone D2
plmn("26204" ++ MSN) ->
	{"262", "04", MSN};
%% Germany, Vodafone D2
plmn("26202" ++ MSN) ->
	{"262", "02", MSN};
%% Germany, Vodafone D2
plmn("26242" ++ MSN) ->
	{"262", "42", MSN};
%% Ghana, Airtel/Tigo
plmn("62003" ++ MSN) ->
	{"620", "03", MSN};
%% Ghana, Airtel/Tigo
plmn("62006" ++ MSN) ->
	{"620", "06", MSN};
%% Ghana, Expresso Ghana Ltd
plmn("62004" ++ MSN) ->
	{"620", "04", MSN};
%% Ghana, GloMobile
plmn("62007" ++ MSN) ->
	{"620", "07", MSN};
%% Ghana, MTN
plmn("62001" ++ MSN) ->
	{"620", "01", MSN};
%% Ghana, Vodafone
plmn("62002" ++ MSN) ->
	{"620", "02", MSN};
%% Gibraltar, CTS Mobile
plmn("26606" ++ MSN) ->
	{"266", "06", MSN};
%% Gibraltar, eazi telecom
plmn("26609" ++ MSN) ->
	{"266", "09", MSN};
%% Gibraltar, Gibtel GSM
plmn("26601" ++ MSN) ->
	{"266", "01", MSN};
%% Greece, AMD Telecom SA
plmn("20207" ++ MSN) ->
	{"202", "07", MSN};
%% Greece, Cosmote
plmn("20202" ++ MSN) ->
	{"202", "02", MSN};
%% Greece, Cosmote
plmn("20201" ++ MSN) ->
	{"202", "01", MSN};
%% Greece, CyTa Mobile
plmn("20214" ++ MSN) ->
	{"202", "14", MSN};
%% Greece, Organismos Sidirodromon Ellados (OSE)
plmn("20204" ++ MSN) ->
	{"202", "04", MSN};
%% Greece, OTE Hellenic Telecommunications Organization SA
plmn("20203" ++ MSN) ->
	{"202", "03", MSN};
%% Greece, Tim/Wind
plmn("20210" ++ MSN) ->
	{"202", "10", MSN};
%% Greece, Tim/Wind
plmn("20209" ++ MSN) ->
	{"202", "09", MSN};
%% Greece, Vodafone
plmn("20205" ++ MSN) ->
	{"202", "05", MSN};
%% Greenland, Tele Greenland
plmn("29001" ++ MSN) ->
	{"290", "01", MSN};
%% Grenada, Cable & Wireless
plmn("352110" ++ MSN) ->
	{"352", "110", MSN};
%% Grenada, Digicel
plmn("35230" ++ MSN) ->
	{"352", "30", MSN};
%% Grenada, Digicel
plmn("35250" ++ MSN) ->
	{"352", "50", MSN};
%% Guadeloupe, Dauphin Telecom SU (Guadeloupe Telecom)
plmn("34008" ++ MSN) ->
	{"340", "08", MSN};
%% Guadeloupe,
plmn("34010" ++ MSN) ->
	{"340", "10", MSN};
%% Guam, Docomo
plmn("310370" ++ MSN) ->
	{"310", "370", MSN};
%% Guam, Docomo
plmn("310470" ++ MSN) ->
	{"310", "470", MSN};
%% Guam, GTA Wireless
plmn("310140" ++ MSN) ->
	{"310", "140", MSN};
%% Guam, Guam Teleph. Auth.
plmn("31033" ++ MSN) ->
	{"310", "33", MSN};
%% Guam, IT&E OverSeas
%% United States, Smith Bagley Inc.
plmn("31032" ++ MSN) ->
	{"310", "32", MSN};
%% Guam, Wave Runner LLC
plmn("311250" ++ MSN) ->
	{"311", "250", MSN};
%% Guatemala, Claro
plmn("70401" ++ MSN) ->
	{"704", "01", MSN};
%% Guatemala, Telefonica
plmn("70403" ++ MSN) ->
	{"704", "03", MSN};
%% Guatemala, TIGO/COMCEL
plmn("70402" ++ MSN) ->
	{"704", "02", MSN};
%% Guinea, MTN/Areeba
plmn("61104" ++ MSN) ->
	{"611", "04", MSN};
%% Guinea, Celcom
plmn("61105" ++ MSN) ->
	{"611", "05", MSN};
%% Guinea, Intercel
plmn("61103" ++ MSN) ->
	{"611", "03", MSN};
%% Guinea, Orange/Sonatel/Spacetel
plmn("61101" ++ MSN) ->
	{"611", "01", MSN};
%% Guinea, SotelGui
plmn("61102" ++ MSN) ->
	{"611", "02", MSN};
%% Guinea-Bissau, GuineTel
plmn("63201" ++ MSN) ->
	{"632", "01", MSN};
%% Guinea-Bissau, Orange
plmn("63203" ++ MSN) ->
	{"632", "03", MSN};
%% Guinea-Bissau, SpaceTel
plmn("63202" ++ MSN) ->
	{"632", "02", MSN};
%% Guyana, Cellink Plus
plmn("73802" ++ MSN) ->
	{"738", "02", MSN};
%% Guyana, DigiCel
plmn("73801" ++ MSN) ->
	{"738", "01", MSN};
%% Haiti, Comcel
plmn("37201" ++ MSN) ->
	{"372", "01", MSN};
%% Haiti, Digicel
plmn("37202" ++ MSN) ->
	{"372", "02", MSN};
%% Haiti, National Telecom SA (NatCom)
plmn("37203" ++ MSN) ->
	{"372", "03", MSN};
%% Honduras, Digicel
plmn("70840" ++ MSN) ->
	{"708", "40", MSN};
%% Honduras, HonduTel
plmn("70830" ++ MSN) ->
	{"708", "30", MSN};
%% Honduras, SERCOM/CLARO
plmn("70801" ++ MSN) ->
	{"708", "01", MSN};
%% Honduras, Telefonica/CELTEL
plmn("70802" ++ MSN) ->
	{"708", "02", MSN};
%% "Hongkong,  China",China Mobile/Peoples
plmn("45413" ++ MSN) ->
	{"454", "13", MSN};
%% "Hongkong,  China",China Mobile/Peoples
plmn("45412" ++ MSN) ->
	{"454", "12", MSN};
%% "Hongkong,  China",China Mobile/Peoples
plmn("45428" ++ MSN) ->
	{"454", "28", MSN};
%% "Hongkong,  China",China Motion
plmn("45409" ++ MSN) ->
	{"454", "09", MSN};
%% "Hongkong,  China",China Unicom Ltd
plmn("45407" ++ MSN) ->
	{"454", "07", MSN};
%% "Hongkong,  China",China-HongKong Telecom Ltd (CHKTL)
plmn("45411" ++ MSN) ->
	{"454", "11", MSN};
%% "Hongkong,  China",Citic Telecom Ltd.
plmn("45401" ++ MSN) ->
	{"454", "01", MSN};
%% "Hongkong,  China",CSL Ltd.
plmn("45402" ++ MSN) ->
	{"454", "02", MSN};
%% "Hongkong,  China",CSL Ltd.
plmn("45400" ++ MSN) ->
	{"454", "00", MSN};
%% "Hongkong,  China",CSL Ltd.
plmn("45418" ++ MSN) ->
	{"454", "18", MSN};
%% "Hongkong,  China",CSL/New World PCS Ltd.
plmn("45410" ++ MSN) ->
	{"454", "10", MSN};
%% "Hongkong,  China",CTExcel
plmn("45431" ++ MSN) ->
	{"454", "31", MSN};
%% "Hongkong,  China",H3G/Hutchinson
plmn("45414" ++ MSN) ->
	{"454", "14", MSN};
%% "Hongkong,  China",H3G/Hutchinson
plmn("45405" ++ MSN) ->
	{"454", "05", MSN};
%% "Hongkong,  China",H3G/Hutchinson
plmn("45404" ++ MSN) ->
	{"454", "04", MSN};
%% "Hongkong,  China",H3G/Hutchinson
plmn("45403" ++ MSN) ->
	{"454", "03", MSN};
%% "Hongkong,  China",HKT/PCCW
plmn("45429" ++ MSN) ->
	{"454", "29", MSN};
%% "Hongkong,  China",HKT/PCCW
plmn("45416" ++ MSN) ->
	{"454", "16", MSN};
%% "Hongkong,  China",HKT/PCCW
plmn("45419" ++ MSN) ->
	{"454", "19", MSN};
%% "Hongkong,  China",HKT/PCCW
plmn("45420" ++ MSN) ->
	{"454", "20", MSN};
%% "Hongkong,  China",shared by private TETRA systems
plmn("45447" ++ MSN) ->
	{"454", "47", MSN};
%% "Hongkong,  China",Multibyte Info Technology Ltd
plmn("45424" ++ MSN) ->
	{"454", "24", MSN};
%% "Hongkong,  China",shared by private TETRA systems
plmn("45440" ++ MSN) ->
	{"454", "40", MSN};
%% "Hongkong,  China",Truephone
plmn("45408" ++ MSN) ->
	{"454", "08", MSN};
%% "Hongkong,  China",Vodafone/SmarTone
plmn("45417" ++ MSN) ->
	{"454", "17", MSN};
%% "Hongkong,  China",Vodafone/SmarTone
plmn("45415" ++ MSN) ->
	{"454", "15", MSN};
%% "Hongkong,  China",Vodafone/SmarTone
plmn("45406" ++ MSN) ->
	{"454", "06", MSN};
%% Hungary, DIGI
plmn("21603" ++ MSN) ->
	{"216", "03", MSN};
%% Hungary, Pannon/Telenor
plmn("21601" ++ MSN) ->
	{"216", "01", MSN};
%% Hungary, T-mobile/Magyar
plmn("21630" ++ MSN) ->
	{"216", "30", MSN};
%% Hungary, UPC Magyarorszag Kft.
plmn("21671" ++ MSN) ->
	{"216", "71", MSN};
%% Hungary, Vodafone
plmn("21670" ++ MSN) ->
	{"216", "70", MSN};
%% Iceland, Amitelo
plmn("27409" ++ MSN) ->
	{"274", "09", MSN};
%% Iceland, IceCell
plmn("27407" ++ MSN) ->
	{"274", "07", MSN};
%% Iceland, Siminn
plmn("27408" ++ MSN) ->
	{"274", "08", MSN};
%% Iceland, Siminn
plmn("27401" ++ MSN) ->
	{"274", "01", MSN};
%% Iceland, NOVA
plmn("27411" ++ MSN) ->
	{"274", "11", MSN};
%% Iceland, VIKING/IMC
plmn("27404" ++ MSN) ->
	{"274", "04", MSN};
%% Iceland, Vodafone/Tal hf
plmn("27402" ++ MSN) ->
	{"274", "02", MSN};
%% Iceland, Vodafone/Tal hf
plmn("27405" ++ MSN) ->
	{"274", "05", MSN};
%% Iceland, Vodafone/Tal hf
plmn("27403" ++ MSN) ->
	{"274", "03", MSN};
%% India, Aircel
plmn("40428" ++ MSN) ->
	{"404", "28", MSN};
%% India, Aircel
plmn("40425" ++ MSN) ->
	{"404", "25", MSN};
%% India, Aircel
plmn("40417" ++ MSN) ->
	{"404", "17", MSN};
%% India, Aircel
plmn("40442" ++ MSN) ->
	{"404", "42", MSN};
%% India, Aircel
plmn("40433" ++ MSN) ->
	{"404", "33", MSN};
%% India, Aircel
plmn("40429" ++ MSN) ->
	{"404", "29", MSN};
%% India, Aircel Digilink India
plmn("40415" ++ MSN) ->
	{"404", "15", MSN};
%% India, Aircel Digilink India
plmn("40460" ++ MSN) ->
	{"404", "60", MSN};
%% India, Aircel Digilink India
plmn("40401" ++ MSN) ->
	{"404", "01", MSN};
%% India, AirTel
plmn("40553" ++ MSN) ->
	{"405", "53", MSN};
%% India, Barakhamba Sales & Serv.
plmn("40486" ++ MSN) ->
	{"404", "86", MSN};
%% India, Barakhamba Sales & Serv.
plmn("40413" ++ MSN) ->
	{"404", "13", MSN};
%% India, BSNL
plmn("40471" ++ MSN) ->
	{"404", "71", MSN};
%% India, BSNL
plmn("40476" ++ MSN) ->
	{"404", "76", MSN};
%% India, BSNL
plmn("40462" ++ MSN) ->
	{"404", "62", MSN};
%% India, BSNL
plmn("40453" ++ MSN) ->
	{"404", "53", MSN};
%% India, BSNL
plmn("40459" ++ MSN) ->
	{"404", "59", MSN};
%% India, BSNL
plmn("40475" ++ MSN) ->
	{"404", "75", MSN};
%% India, BSNL
plmn("40451" ++ MSN) ->
	{"404", "51", MSN};
%% India, BSNL
plmn("40458" ++ MSN) ->
	{"404", "58", MSN};
%% India, BSNL
plmn("40481" ++ MSN) ->
	{"404", "81", MSN};
%% India, BSNL
plmn("40474" ++ MSN) ->
	{"404", "74", MSN};
%% India, BSNL
plmn("40438" ++ MSN) ->
	{"404", "38", MSN};
%% India, BSNL
plmn("40457" ++ MSN) ->
	{"404", "57", MSN};
%% India, BSNL
plmn("40480" ++ MSN) ->
	{"404", "80", MSN};
%% India, BSNL
plmn("40473" ++ MSN) ->
	{"404", "73", MSN};
%% India, BSNL
plmn("40434" ++ MSN) ->
	{"404", "34", MSN};
%% India, BSNL
plmn("40466" ++ MSN) ->
	{"404", "66", MSN};
%% India, BSNL
plmn("40455" ++ MSN) ->
	{"404", "55", MSN};
%% India, BSNL
plmn("40472" ++ MSN) ->
	{"404", "72", MSN};
%% India, BSNL
plmn("40477" ++ MSN) ->
	{"404", "77", MSN};
%% India, BSNL
plmn("40464" ++ MSN) ->
	{"404", "64", MSN};
%% India, BSNL
plmn("40454" ++ MSN) ->
	{"404", "54", MSN};
%% India, Bharti Airtel Limited (Delhi)
plmn("40410" ++ MSN) ->
	{"404", "10", MSN};
%% India, Bharti Airtel Limited (Karnataka) (India)
plmn("40445" ++ MSN) ->
	{"404", "45", MSN};
%% India, CellOne A&N
plmn("40479" ++ MSN) ->
	{"404", "79", MSN};
%% India, Escorts Telecom Ltd.
plmn("40489" ++ MSN) ->
	{"404", "89", MSN};
%% India, Escorts Telecom Ltd.
plmn("40488" ++ MSN) ->
	{"404", "88", MSN};
%% India, Escorts Telecom Ltd.
plmn("40487" ++ MSN) ->
	{"404", "87", MSN};
%% India, Escorts Telecom Ltd.
plmn("40482" ++ MSN) ->
	{"404", "82", MSN};
%% India, Escotel Mobile Communications
plmn("40412" ++ MSN) ->
	{"404", "12", MSN};
%% India, Escotel Mobile Communications
plmn("40419" ++ MSN) ->
	{"404", "19", MSN};
%% India, Escotel Mobile Communications
plmn("40456" ++ MSN) ->
	{"404", "56", MSN};
%% India, Fascel Limited
plmn("40505" ++ MSN) ->
	{"405", "05", MSN};
%% India, Fascel
plmn("40405" ++ MSN) ->
	{"404", "05", MSN};
%% India, Fix Line
plmn("404998" ++ MSN) ->
	{"404", "998", MSN};
%% India, Hexacom India
plmn("40470" ++ MSN) ->
	{"404", "70", MSN};
%% India, Hexcom India
plmn("40416" ++ MSN) ->
	{"404", "16", MSN};
%% India, Idea Cellular Ltd.
plmn("40422" ++ MSN) ->
	{"404", "22", MSN};
%% India, Idea Cellular Ltd.
plmn("40478" ++ MSN) ->
	{"404", "78", MSN};
%% India, Idea Cellular Ltd.
plmn("40407" ++ MSN) ->
	{"404", "07", MSN};
%% India, Idea Cellular Ltd.
plmn("40404" ++ MSN) ->
	{"404", "04", MSN};
%% India, Idea Cellular Ltd.
plmn("40424" ++ MSN) ->
	{"404", "24", MSN};
%% India, Mahanagar Telephone Nigam
plmn("40468" ++ MSN) ->
	{"404", "68", MSN};
%% India, Mahanagar Telephone Nigam
plmn("40469" ++ MSN) ->
	{"404", "69", MSN};
%% India, Reliable Internet Services
plmn("40483" ++ MSN) ->
	{"404", "83", MSN};
%% India, Reliance Telecom Private
plmn("40452" ++ MSN) ->
	{"404", "52", MSN};
%% India, Reliance Telecom Private
plmn("40450" ++ MSN) ->
	{"404", "50", MSN};
%% India, Reliance Telecom Private
plmn("40467" ++ MSN) ->
	{"404", "67", MSN};
%% India, Reliance Telecom Private
plmn("40418" ++ MSN) ->
	{"404", "18", MSN};
%% India, Reliance Telecom Private
plmn("40485" ++ MSN) ->
	{"404", "85", MSN};
%% India, Reliance Telecom Private
plmn("40409" ++ MSN) ->
	{"404", "09", MSN};
%% India, Reliance Telecom Private
plmn("40587" ++ MSN) ->
	{"405", "87", MSN};
%% India, Reliance Telecom Private
plmn("40436" ++ MSN) ->
	{"404", "36", MSN};
%% India, RPG Cellular
plmn("40441" ++ MSN) ->
	{"404", "41", MSN};
%% India, Spice
plmn("40444" ++ MSN) ->
	{"404", "44", MSN};
%% India, Spice
plmn("40414" ++ MSN) ->
	{"404", "14", MSN};
%% India, Sterling Cellular Ltd.
plmn("40411" ++ MSN) ->
	{"404", "11", MSN};
%% India, TATA / Karnataka
plmn("40534" ++ MSN) ->
	{"405", "34", MSN};
%% India, Usha Martin Telecom
plmn("40430" ++ MSN) ->
	{"404", "30", MSN};
%% India, Various Networks
plmn("404999" ++ MSN) ->
	{"404", "999", MSN};
%% India, Unknown
plmn("40427" ++ MSN) ->
	{"404", "27", MSN};
%% India, Vodafone/Essar/Hutch
plmn("40443" ++ MSN) ->
	{"404", "43", MSN};
%% India, Unknown
plmn("40420" ++ MSN) ->
	{"404", "20", MSN};
%% Indonesia, Axis/Natrindo
plmn("51008" ++ MSN) ->
	{"510", "08", MSN};
%% Indonesia, Esia (PT Bakrie Telecom) (CDMA)
plmn("51099" ++ MSN) ->
	{"510", "99", MSN};
%% Indonesia, Flexi (PT Telkom) (CDMA)/Telkomsel
plmn("51007" ++ MSN) ->
	{"510", "07", MSN};
%% Indonesia, H3G CP
plmn("51089" ++ MSN) ->
	{"510", "89", MSN};
%% Indonesia, Indosat/Satelindo/M3
plmn("51001" ++ MSN) ->
	{"510", "01", MSN};
%% Indonesia, Indosat/Satelindo/M3
plmn("51021" ++ MSN) ->
	{"510", "21", MSN};
%% Indonesia, PT Pasifik Satelit Nusantara (PSN)
plmn("51000" ++ MSN) ->
	{"510", "00", MSN};
%% Indonesia, PT Sampoerna Telekomunikasi Indonesia (STI)
plmn("51027" ++ MSN) ->
	{"510", "27", MSN};
%% Indonesia, PT Smartfren Telecom Tbk
plmn("51028" ++ MSN) ->
	{"510", "28", MSN};
%% Indonesia, PT Smartfren Telecom Tbk
plmn("51009" ++ MSN) ->
	{"510", "09", MSN};
%% Indonesia, PT. Excelcom
plmn("51011" ++ MSN) ->
	{"510", "11", MSN};
%% Indonesia, Telkomsel
plmn("51010" ++ MSN) ->
	{"510", "10", MSN};
%% International Networks, Antarctica
plmn("90113" ++ MSN) ->
	{"901", "13", MSN};
%% Iran, Mobile Telecommunications Company of Esfahan JV-PJS (MTCE)
plmn("43219" ++ MSN) ->
	{"432", "19", MSN};
%% Iran, MTCE
plmn("43270" ++ MSN) ->
	{"432", "70", MSN};
%% Iran, MTN/IranCell
plmn("43235" ++ MSN) ->
	{"432", "35", MSN};
%% Iran, Rightel
plmn("43220" ++ MSN) ->
	{"432", "20", MSN};
%% Iran, Taliya
plmn("43232" ++ MSN) ->
	{"432", "32", MSN};
%% Iran, MCI/TCI
plmn("43211" ++ MSN) ->
	{"432", "11", MSN};
%% Iran, TKC/KFZO
plmn("43214" ++ MSN) ->
	{"432", "14", MSN};
%% Iraq, Asia Cell
plmn("41805" ++ MSN) ->
	{"418", "05", MSN};
%% Iraq, Fastlink
plmn("41866" ++ MSN) ->
	{"418", "66", MSN};
%% Iraq, Itisaluna and Kalemat
plmn("41892" ++ MSN) ->
	{"418", "92", MSN};
%% Iraq, Korek
plmn("41840" ++ MSN) ->
	{"418", "40", MSN};
%% Iraq, Korek
plmn("41882" ++ MSN) ->
	{"418", "82", MSN};
%% Iraq, Mobitel (Iraq-Kurdistan) and Moutiny
plmn("41845" ++ MSN) ->
	{"418", "45", MSN};
%% Iraq, Orascom Telecom
plmn("41830" ++ MSN) ->
	{"418", "30", MSN};
%% Iraq, ZAIN/Atheer/Orascom
plmn("41820" ++ MSN) ->
	{"418", "20", MSN};
%% Iraq, Sanatel
plmn("41808" ++ MSN) ->
	{"418", "08", MSN};
%% Ireland, Access Telecom Ltd.
plmn("27204" ++ MSN) ->
	{"272", "04", MSN};
%% Ireland, Clever Communications Ltd
plmn("27209" ++ MSN) ->
	{"272", "09", MSN};
%% Ireland, eircom Ltd
plmn("27207" ++ MSN) ->
	{"272", "07", MSN};
%% Ireland, Tesco Mobile/Liffey Telecom
plmn("27211" ++ MSN) ->
	{"272", "11", MSN};
%% Ireland, Lycamobile
plmn("27213" ++ MSN) ->
	{"272", "13", MSN};
%% Ireland, Meteor Mobile Ltd.
plmn("27203" ++ MSN) ->
	{"272", "03", MSN};
%% Ireland, Three
plmn("27205" ++ MSN) ->
	{"272", "05", MSN};
%% Ireland, Three
plmn("27217" ++ MSN) ->
	{"272", "17", MSN};
%% Ireland, Three
plmn("27202" ++ MSN) ->
	{"272", "02", MSN};
%% Ireland, Virgin Mobile
plmn("27215" ++ MSN) ->
	{"272", "15", MSN};
%% Ireland, Vodafone Eircell
plmn("27201" ++ MSN) ->
	{"272", "01", MSN};
%% Israel, Alon Cellular Ltd
plmn("42514" ++ MSN) ->
	{"425", "14", MSN};
%% Israel, Cellcom ltd.
plmn("42502" ++ MSN) ->
	{"425", "02", MSN};
%% Israel, Golan Telekom
plmn("42508" ++ MSN) ->
	{"425", "08", MSN};
%% Israel, Home Cellular Ltd
plmn("42515" ++ MSN) ->
	{"425", "15", MSN};
%% Israel, Hot Mobile/Mirs
plmn("42577" ++ MSN) ->
	{"425", "77", MSN};
%% Israel, Hot Mobile/Mirs
plmn("42507" ++ MSN) ->
	{"425", "07", MSN};
%% Israel, We4G/Marathon 018
plmn("42509" ++ MSN) ->
	{"425", "09", MSN};
%% Israel, Orange/Partner Co. Ltd.
plmn("42501" ++ MSN) ->
	{"425", "01", MSN};
%% Israel, Pelephone
plmn("42512" ++ MSN) ->
	{"425", "12", MSN};
%% Israel, Pelephone
plmn("42503" ++ MSN) ->
	{"425", "03", MSN};
%% Israel, Rami Levy Hashikma Marketing Communications Ltd
plmn("42516" ++ MSN) ->
	{"425", "16", MSN};
%% Israel, Telzar/AZI
plmn("42519" ++ MSN) ->
	{"425", "19", MSN};
%% Italy, BT Italia SpA
plmn("22234" ++ MSN) ->
	{"222", "34", MSN};
%% Italy, Digi Mobil
plmn("22236" ++ MSN) ->
	{"222", "36", MSN};
%% Italy, Elsacom
plmn("22202" ++ MSN) ->
	{"222", "02", MSN};
%% Italy, Fastweb SpA
plmn("22208" ++ MSN) ->
	{"222", "08", MSN};
%% Italy, Fix Line/VOIP Line
plmn("22200" ++ MSN) ->
	{"222", "00", MSN};
%% Italy, Hi3G
plmn("22299" ++ MSN) ->
	{"222", "99", MSN};
%% Italy, Iliad
plmn("22250" ++ MSN) ->
	{"222", "50", MSN};
%% Italy, IPSE 2000
plmn("22277" ++ MSN) ->
	{"222", "77", MSN};
%% Italy, Lycamobile Srl
plmn("22235" ++ MSN) ->
	{"222", "35", MSN};
%% Italy, Noverca Italia Srl
plmn("22207" ++ MSN) ->
	{"222", "07", MSN};
%% Italy, PosteMobile SpA
plmn("22233" ++ MSN) ->
	{"222", "33", MSN};
%% Italy, RFI Rete Ferroviaria Italiana SpA
plmn("22230" ++ MSN) ->
	{"222", "30", MSN};
%% Italy, Telecom Italia Mobile SpA
plmn("22248" ++ MSN) ->
	{"222", "48", MSN};
%% Italy, Telecom Italia Mobile SpA
plmn("22243" ++ MSN) ->
	{"222", "43", MSN};
%% Italy, TIM
plmn("22201" ++ MSN) ->
	{"222", "01", MSN};
%% Italy, Vodafone
plmn("22210" ++ MSN) ->
	{"222", "10", MSN};
%% Italy, Vodafone
plmn("22206" ++ MSN) ->
	{"222", "06", MSN};
%% Italy, WIND (Blu) -
plmn("22244" ++ MSN) ->
	{"222", "44", MSN};
%% Italy, WIND (Blu) -
plmn("22288" ++ MSN) ->
	{"222", "88", MSN};
%% Ivory Coast, Aircomm SA
plmn("61207" ++ MSN) ->
	{"612", "07", MSN};
%% Ivory Coast, Atlantik Tel./Moov
plmn("61202" ++ MSN) ->
	{"612", "02", MSN};
%% Ivory Coast, Comium
plmn("61204" ++ MSN) ->
	{"612", "04", MSN};
%% Ivory Coast, Comstar
plmn("61201" ++ MSN) ->
	{"612", "01", MSN};
%% Ivory Coast, MTN
plmn("61205" ++ MSN) ->
	{"612", "05", MSN};
%% Ivory Coast, Orange
plmn("61203" ++ MSN) ->
	{"612", "03", MSN};
%% Ivory Coast, OriCell
plmn("61206" ++ MSN) ->
	{"612", "06", MSN};
%% Jamaica, Cable & Wireless
plmn("338110" ++ MSN) ->
	{"338", "110", MSN};
%% Jamaica, Cable & Wireless
plmn("33820" ++ MSN) ->
	{"338", "20", MSN};
%% Jamaica, Cable & Wireless
plmn("338180" ++ MSN) ->
	{"338", "180", MSN};
%% Jamaica, DIGICEL/Mossel
plmn("33850" ++ MSN) ->
	{"338", "50", MSN};
%% Japan, Y-Mobile
plmn("44000" ++ MSN) ->
	{"440", "00", MSN};
%% Japan, KDDI Corporation
plmn("44074" ++ MSN) ->
	{"440", "74", MSN};
%% Japan, KDDI Corporation
plmn("44070" ++ MSN) ->
	{"440", "70", MSN};
%% Japan, KDDI Corporation
plmn("44089" ++ MSN) ->
	{"440", "89", MSN};
%% Japan, KDDI Corporation
plmn("44051" ++ MSN) ->
	{"440", "51", MSN};
%% Japan, KDDI Corporation
plmn("44075" ++ MSN) ->
	{"440", "75", MSN};
%% Japan, KDDI Corporation
plmn("44056" ++ MSN) ->
	{"440", "56", MSN};
%% Japan, KDDI Corporation
plmn("44170" ++ MSN) ->
	{"441", "70", MSN};
%% Japan, KDDI Corporation
plmn("44052" ++ MSN) ->
	{"440", "52", MSN};
%% Japan, KDDI Corporation
plmn("44076" ++ MSN) ->
	{"440", "76", MSN};
%% Japan, KDDI Corporation
plmn("44071" ++ MSN) ->
	{"440", "71", MSN};
%% Japan, KDDI Corporation
plmn("44053" ++ MSN) ->
	{"440", "53", MSN};
%% Japan, KDDI Corporation
plmn("44077" ++ MSN) ->
	{"440", "77", MSN};
%% Japan, KDDI Corporation
plmn("44008" ++ MSN) ->
	{"440", "08", MSN};
%% Japan, KDDI Corporation
plmn("44072" ++ MSN) ->
	{"440", "72", MSN};
%% Japan, KDDI Corporation
plmn("44054" ++ MSN) ->
	{"440", "54", MSN};
%% Japan, KDDI Corporation
plmn("44079" ++ MSN) ->
	{"440", "79", MSN};
%% Japan, KDDI Corporation
plmn("44007" ++ MSN) ->
	{"440", "07", MSN};
%% Japan, KDDI Corporation
plmn("44073" ++ MSN) ->
	{"440", "73", MSN};
%% Japan, KDDI Corporation
plmn("44055" ++ MSN) ->
	{"440", "55", MSN};
%% Japan, KDDI Corporation
plmn("44088" ++ MSN) ->
	{"440", "88", MSN};
%% Japan, KDDI Corporation
plmn("44050" ++ MSN) ->
	{"440", "50", MSN};
%% Japan, NTT Docomo
plmn("44021" ++ MSN) ->
	{"440", "21", MSN};
%% Japan, NTT Docomo
plmn("44144" ++ MSN) ->
	{"441", "44", MSN};
%% Japan, NTT Docomo
plmn("44013" ++ MSN) ->
	{"440", "13", MSN};
%% Japan, NTT Docomo
plmn("44001" ++ MSN) ->
	{"440", "01", MSN};
%% Japan, NTT Docomo
plmn("44023" ++ MSN) ->
	{"440", "23", MSN};
%% Japan, NTT Docomo
plmn("44016" ++ MSN) ->
	{"440", "16", MSN};
%% Japan, NTT Docomo
plmn("44199" ++ MSN) ->
	{"441", "99", MSN};
%% Japan, NTT Docomo
plmn("44034" ++ MSN) ->
	{"440", "34", MSN};
%% Japan, NTT Docomo
plmn("44069" ++ MSN) ->
	{"440", "69", MSN};
%% Japan, NTT Docomo
plmn("44064" ++ MSN) ->
	{"440", "64", MSN};
%% Japan, NTT Docomo
plmn("44037" ++ MSN) ->
	{"440", "37", MSN};
%% Japan, NTT Docomo
plmn("44025" ++ MSN) ->
	{"440", "25", MSN};
%% Japan, NTT Docomo
plmn("44022" ++ MSN) ->
	{"440", "22", MSN};
%% Japan, NTT Docomo
plmn("44143" ++ MSN) ->
	{"441", "43", MSN};
%% Japan, NTT Docomo
plmn("44027" ++ MSN) ->
	{"440", "27", MSN};
%% Japan, NTT Docomo
plmn("44002" ++ MSN) ->
	{"440", "02", MSN};
%% Japan, NTT Docomo
plmn("44017" ++ MSN) ->
	{"440", "17", MSN};
%% Japan, NTT Docomo
plmn("44031" ++ MSN) ->
	{"440", "31", MSN};
%% Japan, NTT Docomo
plmn("44087" ++ MSN) ->
	{"440", "87", MSN};
%% Japan, NTT Docomo
plmn("44065" ++ MSN) ->
	{"440", "65", MSN};
%% Japan, NTT Docomo
plmn("44036" ++ MSN) ->
	{"440", "36", MSN};
%% Japan, NTT Docomo
plmn("44192" ++ MSN) ->
	{"441", "92", MSN};
%% Japan, NTT Docomo
plmn("44012" ++ MSN) ->
	{"440", "12", MSN};
%% Japan, NTT Docomo
plmn("44058" ++ MSN) ->
	{"440", "58", MSN};
%% Japan, NTT Docomo
plmn("44028" ++ MSN) ->
	{"440", "28", MSN};
%% Japan, NTT Docomo
plmn("44003" ++ MSN) ->
	{"440", "03", MSN};
%% Japan, NTT Docomo
plmn("44018" ++ MSN) ->
	{"440", "18", MSN};
%% Japan, NTT Docomo
plmn("44191" ++ MSN) ->
	{"441", "91", MSN};
%% Japan, NTT Docomo
plmn("44032" ++ MSN) ->
	{"440", "32", MSN};
%% Japan, NTT Docomo
plmn("44061" ++ MSN) ->
	{"440", "61", MSN};
%% Japan, NTT Docomo
plmn("44035" ++ MSN) ->
	{"440", "35", MSN};
%% Japan, NTT Docomo
plmn("44193" ++ MSN) ->
	{"441", "93", MSN};
%% Japan, NTT Docomo
plmn("44140" ++ MSN) ->
	{"441", "40", MSN};
%% Japan, NTT Docomo
plmn("44066" ++ MSN) ->
	{"440", "66", MSN};
%% Japan, NTT Docomo
plmn("44049" ++ MSN) ->
	{"440", "49", MSN};
%% Japan, NTT Docomo
plmn("44029" ++ MSN) ->
	{"440", "29", MSN};
%% Japan, NTT Docomo
plmn("44009" ++ MSN) ->
	{"440", "09", MSN};
%% Japan, NTT Docomo
plmn("44019" ++ MSN) ->
	{"440", "19", MSN};
%% Japan, NTT Docomo
plmn("44190" ++ MSN) ->
	{"441", "90", MSN};
%% Japan, NTT Docomo
plmn("44033" ++ MSN) ->
	{"440", "33", MSN};
%% Japan, NTT Docomo
plmn("44060" ++ MSN) ->
	{"440", "60", MSN};
%% Japan, NTT Docomo
plmn("44014" ++ MSN) ->
	{"440", "14", MSN};
%% Japan, NTT Docomo
plmn("44194" ++ MSN) ->
	{"441", "94", MSN};
%% Japan, NTT Docomo
plmn("44141" ++ MSN) ->
	{"441", "41", MSN};
%% Japan, NTT Docomo
plmn("44067" ++ MSN) ->
	{"440", "67", MSN};
%% Japan, NTT Docomo
plmn("44062" ++ MSN) ->
	{"440", "62", MSN};
%% Japan, NTT Docomo
plmn("44039" ++ MSN) ->
	{"440", "39", MSN};
%% Japan, NTT Docomo
plmn("44030" ++ MSN) ->
	{"440", "30", MSN};
%% Japan, NTT Docomo
plmn("44010" ++ MSN) ->
	{"440", "10", MSN};
%% Japan, NTT Docomo
plmn("44145" ++ MSN) ->
	{"441", "45", MSN};
%% Japan, NTT Docomo
plmn("44024" ++ MSN) ->
	{"440", "24", MSN};
%% Japan, NTT Docomo
plmn("44015" ++ MSN) ->
	{"440", "15", MSN};
%% Japan, NTT Docomo
plmn("44198" ++ MSN) ->
	{"441", "98", MSN};
%% Japan, NTT Docomo
plmn("44142" ++ MSN) ->
	{"441", "42", MSN};
%% Japan, NTT Docomo
plmn("44068" ++ MSN) ->
	{"440", "68", MSN};
%% Japan, NTT Docomo
plmn("44063" ++ MSN) ->
	{"440", "63", MSN};
%% Japan, NTT Docomo
plmn("44038" ++ MSN) ->
	{"440", "38", MSN};
%% Japan, NTT Docomo
plmn("44026" ++ MSN) ->
	{"440", "26", MSN};
%% Japan, NTT Docomo
plmn("44011" ++ MSN) ->
	{"440", "11", MSN};
%% Japan, NTT Docomo
plmn("44099" ++ MSN) ->
	{"440", "99", MSN};
%% Japan, Okinawa Cellular Telephone
plmn("44078" ++ MSN) ->
	{"440", "78", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44047" ++ MSN) ->
	{"440", "47", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44095" ++ MSN) ->
	{"440", "95", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44041" ++ MSN) ->
	{"440", "41", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44164" ++ MSN) ->
	{"441", "64", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44046" ++ MSN) ->
	{"440", "46", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44097" ++ MSN) ->
	{"440", "97", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44042" ++ MSN) ->
	{"440", "42", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44165" ++ MSN) ->
	{"441", "65", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44090" ++ MSN) ->
	{"440", "90", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44092" ++ MSN) ->
	{"440", "92", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44098" ++ MSN) ->
	{"440", "98", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44043" ++ MSN) ->
	{"440", "43", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44093" ++ MSN) ->
	{"440", "93", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44048" ++ MSN) ->
	{"440", "48", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44006" ++ MSN) ->
	{"440", "06", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44161" ++ MSN) ->
	{"441", "61", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44044" ++ MSN) ->
	{"440", "44", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44094" ++ MSN) ->
	{"440", "94", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44004" ++ MSN) ->
	{"440", "04", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44162" ++ MSN) ->
	{"441", "62", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44045" ++ MSN) ->
	{"440", "45", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44020" ++ MSN) ->
	{"440", "20", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44096" ++ MSN) ->
	{"440", "96", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44040" ++ MSN) ->
	{"440", "40", MSN};
%% Japan, SoftBank Mobile Corp
plmn("44163" ++ MSN) ->
	{"441", "63", MSN};
%% Japan, KDDI Corporation
plmn("44083" ++ MSN) ->
	{"440", "83", MSN};
%% Japan, KDDI Corporation
plmn("44085" ++ MSN) ->
	{"440", "85", MSN};
%% Japan, KDDI Corporation
plmn("44081" ++ MSN) ->
	{"440", "81", MSN};
%% Japan, KDDI Corporation
plmn("44080" ++ MSN) ->
	{"440", "80", MSN};
%% Japan, KDDI Corporation
plmn("44086" ++ MSN) ->
	{"440", "86", MSN};
%% Japan, KDDI Corporation
plmn("44084" ++ MSN) ->
	{"440", "84", MSN};
%% Japan, KDDI Corporation
plmn("44082" ++ MSN) ->
	{"440", "82", MSN};
%% Jordan, Orange/Petra
plmn("41677" ++ MSN) ->
	{"416", "77", MSN};
%% Jordan, Umniah Mobile Co.
plmn("41603" ++ MSN) ->
	{"416", "03", MSN};
%% Jordan, Xpress
plmn("41602" ++ MSN) ->
	{"416", "02", MSN};
%% Jordan, ZAIN /J.M.T.S
plmn("41601" ++ MSN) ->
	{"416", "01", MSN};
%% Kazakhstan, Beeline/KaR-Tel LLP
plmn("40101" ++ MSN) ->
	{"401", "01", MSN};
%% Kazakhstan, Dalacom/Altel
plmn("40107" ++ MSN) ->
	{"401", "07", MSN};
%% Kazakhstan, K-Cell
plmn("40102" ++ MSN) ->
	{"401", "02", MSN};
%% Kazakhstan, Tele2/NEO/MTS
plmn("40177" ++ MSN) ->
	{"401", "77", MSN};
%% Kenya, Econet Wireless
plmn("63905" ++ MSN) ->
	{"639", "05", MSN};
%% Kenya, Safaricom Ltd.
plmn("63902" ++ MSN) ->
	{"639", "02", MSN};
%% Kenya, Telkom fka. Orange
plmn("63907" ++ MSN) ->
	{"639", "07", MSN};
%% Kenya, Airtel/Zain/Celtel Ltd.
plmn("63903" ++ MSN) ->
	{"639", "03", MSN};
%% Kiribati, Kiribati Frigate
plmn("54509" ++ MSN) ->
	{"545", "09", MSN};
%% "Korea N.,  Dem. People's Rep.",Sun Net
plmn("467193" ++ MSN) ->
	{"467", "193", MSN};
%% "Korea S,  Republic of",KT Freetel Co. Ltd.
plmn("45004" ++ MSN) ->
	{"450", "04", MSN};
%% "Korea S,  Republic of",KT Freetel Co. Ltd.
plmn("45008" ++ MSN) ->
	{"450", "08", MSN};
%% "Korea S,  Republic of",KT Freetel Co. Ltd.
plmn("45002" ++ MSN) ->
	{"450", "02", MSN};
%% "Korea S,  Republic of",LG Telecom
plmn("45006" ++ MSN) ->
	{"450", "06", MSN};
%% "Korea S,  Republic of",SK Telecom
plmn("45003" ++ MSN) ->
	{"450", "03", MSN};
%% "Korea S,  Republic of",SK Telecom Co. Ltd
plmn("45005" ++ MSN) ->
	{"450", "05", MSN};
%% Kosovo, Dardafon.Net LLC
plmn("22106" ++ MSN) ->
	{"221", "06", MSN};
%% Kosovo, IPKO
plmn("22102" ++ MSN) ->
	{"221", "02", MSN};
%% Kosovo, MTS DOO
plmn("22103" ++ MSN) ->
	{"221", "03", MSN};
%% Kosovo, Vala
plmn("22101" ++ MSN) ->
	{"221", "01", MSN};
%% Kuwait, Zain
plmn("41902" ++ MSN) ->
	{"419", "02", MSN};
%% Kuwait, Viva
plmn("41904" ++ MSN) ->
	{"419", "04", MSN};
%% Kuwait, Ooredoo
plmn("41903" ++ MSN) ->
	{"419", "03", MSN};
%% Kyrgyzstan, AkTel LLC
plmn("43703" ++ MSN) ->
	{"437", "03", MSN};
%% Kyrgyzstan, Beeline/Bitel
plmn("43701" ++ MSN) ->
	{"437", "01", MSN};
%% Kyrgyzstan, MEGACOM
plmn("43705" ++ MSN) ->
	{"437", "05", MSN};
%% Kyrgyzstan, O!/NUR Telecom
plmn("43709" ++ MSN) ->
	{"437", "09", MSN};
%% Laos P.D.R., ETL Mobile
plmn("45702" ++ MSN) ->
	{"457", "02", MSN};
%% Laos P.D.R., Lao Tel
plmn("45701" ++ MSN) ->
	{"457", "01", MSN};
%% Laos P.D.R., Beeline/Tigo/Millicom
plmn("45708" ++ MSN) ->
	{"457", "08", MSN};
%% Laos P.D.R., UNITEL/LAT
plmn("45703" ++ MSN) ->
	{"457", "03", MSN};
%% Laos P.D.R., Best
plmn("45707" ++ MSN) ->
	{"457", "07", MSN};
%% Latvia, Bite
plmn("24705" ++ MSN) ->
	{"247", "05", MSN};
%% Latvia, Latvian Mobile Phone
plmn("24701" ++ MSN) ->
	{"247", "01", MSN};
%% Latvia, SIA Camel Mobile
plmn("24709" ++ MSN) ->
	{"247", "09", MSN};
%% Latvia, SIA IZZI
plmn("24708" ++ MSN) ->
	{"247", "08", MSN};
%% Latvia, SIA Master Telecom
plmn("24707" ++ MSN) ->
	{"247", "07", MSN};
%% Latvia, SIA Rigatta
plmn("24706" ++ MSN) ->
	{"247", "06", MSN};
%% Latvia, Tele2
plmn("24702" ++ MSN) ->
	{"247", "02", MSN};
%% Latvia, TRIATEL/Telekom Baltija
plmn("24703" ++ MSN) ->
	{"247", "03", MSN};
%% Lebanon, Cellis
plmn("41535" ++ MSN) ->
	{"415", "35", MSN};
%% Lebanon, Cellis
plmn("41533" ++ MSN) ->
	{"415", "33", MSN};
%% Lebanon, Cellis
plmn("41532" ++ MSN) ->
	{"415", "32", MSN};
%% Lebanon, FTML Cellis
plmn("41534" ++ MSN) ->
	{"415", "34", MSN};
%% Lebanon, MIC2/LibanCell/MTC
plmn("41537" ++ MSN) ->
	{"415", "37", MSN};
%% Lebanon, MIC2/LibanCell/MTC
plmn("41539" ++ MSN) ->
	{"415", "39", MSN};
%% Lebanon, MIC2/LibanCell/MTC
plmn("41538" ++ MSN) ->
	{"415", "38", MSN};
%% Lebanon, MIC1 (Alfa)
plmn("41501" ++ MSN) ->
	{"415", "01", MSN};
%% Lebanon, MIC2/LibanCell/MTC
plmn("41503" ++ MSN) ->
	{"415", "03", MSN};
%% Lebanon, MIC2/LibanCell/MTC
plmn("41536" ++ MSN) ->
	{"415", "36", MSN};
%% Lesotho, Econet/Ezi-cel
plmn("65102" ++ MSN) ->
	{"651", "02", MSN};
%% Lesotho, Vodacom Lesotho
plmn("65101" ++ MSN) ->
	{"651", "01", MSN};
%% Liberia, Comium BVI
plmn("61804" ++ MSN) ->
	{"618", "04", MSN};
%% Liberia, Libercell
plmn("61802" ++ MSN) ->
	{"618", "02", MSN};
%% Liberia, LibTelco
plmn("61820" ++ MSN) ->
	{"618", "20", MSN};
%% Liberia, Lonestar
plmn("61801" ++ MSN) ->
	{"618", "01", MSN};
%% Liberia, Orange
plmn("61807" ++ MSN) ->
	{"618", "07", MSN};
%% Libya, Al-Madar
plmn("60602" ++ MSN) ->
	{"606", "02", MSN};
%% Libya, Al-Madar
plmn("60601" ++ MSN) ->
	{"606", "01", MSN};
%% Libya, Hatef
plmn("60606" ++ MSN) ->
	{"606", "06", MSN};
%% Libya, Libyana
plmn("60600" ++ MSN) ->
	{"606", "00", MSN};
%% Libya, Libyana
plmn("60603" ++ MSN) ->
	{"606", "03", MSN};
%% Liechtenstein, CUBIC (Liechtenstein
plmn("29506" ++ MSN) ->
	{"295", "06", MSN};
%% Liechtenstein, First Mobile AG
plmn("29507" ++ MSN) ->
	{"295", "07", MSN};
%% Liechtenstein, Orange
plmn("29502" ++ MSN) ->
	{"295", "02", MSN};
%% Liechtenstein, Swisscom FL AG
plmn("29501" ++ MSN) ->
	{"295", "01", MSN};
%% Liechtenstein, Alpmobile/Tele2
plmn("29577" ++ MSN) ->
	{"295", "77", MSN};
%% Liechtenstein, Telecom FL1 AG
plmn("29505" ++ MSN) ->
	{"295", "05", MSN};
%% Lithuania, Bite
plmn("24602" ++ MSN) ->
	{"246", "02", MSN};
%% Lithuania, Omnitel
plmn("24601" ++ MSN) ->
	{"246", "01", MSN};
%% Lithuania, Tele2
plmn("24603" ++ MSN) ->
	{"246", "03", MSN};
%% Luxembourg, Millicom Tango GSM
plmn("27077" ++ MSN) ->
	{"270", "77", MSN};
%% Luxembourg, P+T/Post LUXGSM
plmn("27001" ++ MSN) ->
	{"270", "01", MSN};
%% Luxembourg, Orange/VOXmobile S.A.
plmn("27099" ++ MSN) ->
	{"270", "99", MSN};
%% "Macao,  China",C.T.M. TELEMOVEL+
plmn("45501" ++ MSN) ->
	{"455", "01", MSN};
%% "Macao,  China",C.T.M. TELEMOVEL+
plmn("45504" ++ MSN) ->
	{"455", "04", MSN};
%% "Macao,  China",China Telecom
plmn("45502" ++ MSN) ->
	{"455", "02", MSN};
%% "Macao,  China",Hutchison Telephone Co. Ltd
plmn("45503" ++ MSN) ->
	{"455", "03", MSN};
%% "Macao,  China",Hutchison Telephone Co. Ltd
plmn("45505" ++ MSN) ->
	{"455", "05", MSN};
%% "Macao,  China",Smartone Mobile
plmn("45506" ++ MSN) ->
	{"455", "06", MSN};
%% "Macao,  China",Smartone Mobile
plmn("45500" ++ MSN) ->
	{"455", "00", MSN};
%% Macedonia, ONE/Cosmofone
plmn("29475" ++ MSN) ->
	{"294", "75", MSN};
%% Macedonia, Lycamobile
plmn("29404" ++ MSN) ->
	{"294", "04", MSN};
%% Macedonia, ONE/Cosmofone
plmn("29402" ++ MSN) ->
	{"294", "02", MSN};
%% Macedonia, T-Mobile/Mobimak
plmn("29401" ++ MSN) ->
	{"294", "01", MSN};
%% Macedonia, VIP Mobile
plmn("29403" ++ MSN) ->
	{"294", "03", MSN};
%% Madagascar, Airtel/MADACOM
plmn("64601" ++ MSN) ->
	{"646", "01", MSN};
%% Madagascar, Orange/Soci
plmn("64602" ++ MSN) ->
	{"646", "02", MSN};
%% Madagascar, Sacel
plmn("64603" ++ MSN) ->
	{"646", "03", MSN};
%% Madagascar, Telma
plmn("64604" ++ MSN) ->
	{"646", "04", MSN};
%% Malawi, TNM/Telekom Network Ltd.
plmn("65001" ++ MSN) ->
	{"650", "01", MSN};
%% Malawi, Airtel/Zain/Celtel ltd.
plmn("65010" ++ MSN) ->
	{"650", "10", MSN};
%% Malaysia, Art900
plmn("50201" ++ MSN) ->
	{"502", "01", MSN};
%% Malaysia, Baraka Telecom Sdn Bhd
plmn("502151" ++ MSN) ->
	{"502", "151", MSN};
%% Malaysia, CelCom
plmn("502198" ++ MSN) ->
	{"502", "198", MSN};
%% Malaysia, CelCom/XOX Com Sdn Bhd
plmn("50219" ++ MSN) ->
	{"502", "19", MSN};
%% Malaysia, CelCom
plmn("50213" ++ MSN) ->
	{"502", "13", MSN};
%% Malaysia, Digi Telecommunications
plmn("50210" ++ MSN) ->
	{"502", "10", MSN};
%% Malaysia, Digi Telecommunications
plmn("50216" ++ MSN) ->
	{"502", "16", MSN};
%% Malaysia, Electcoms Wireless Sdn Bhd
plmn("50220" ++ MSN) ->
	{"502", "20", MSN};
%% Malaysia, Maxis
plmn("50212" ++ MSN) ->
	{"502", "12", MSN};
%% Malaysia, Maxis
plmn("50217" ++ MSN) ->
	{"502", "17", MSN};
%% Malaysia, MTX Utara
plmn("50211" ++ MSN) ->
	{"502", "11", MSN};
%% Malaysia, Webe/Packet One Networks (Malaysia) Sdn Bhd
plmn("502153" ++ MSN) ->
	{"502", "153", MSN};
%% Malaysia, Samata Communications Sdn Bhd
plmn("502155" ++ MSN) ->
	{"502", "155", MSN};
%% Malaysia, Tron/Talk Focus Sdn Bhd
plmn("502154" ++ MSN) ->
	{"502", "154", MSN};
%% Malaysia, TuneTalk
plmn("502150" ++ MSN) ->
	{"502", "150", MSN};
%% Malaysia, U Mobile
plmn("50218" ++ MSN) ->
	{"502", "18", MSN};
%% Malaysia, YES
plmn("502152" ++ MSN) ->
	{"502", "152", MSN};
%% Maldives, Dhiraagu/C&W
plmn("47201" ++ MSN) ->
	{"472", "01", MSN};
%% Maldives, Ooredo/Wataniya
plmn("47202" ++ MSN) ->
	{"472", "02", MSN};
%% Mali, ATEL SA
plmn("61003" ++ MSN) ->
	{"610", "03", MSN};
%% Mali, Malitel
plmn("61001" ++ MSN) ->
	{"610", "01", MSN};
%% Mali, Orange/IKATEL
plmn("61002" ++ MSN) ->
	{"610", "02", MSN};
%% Malta, GO Mobile
plmn("27821" ++ MSN) ->
	{"278", "21", MSN};
%% Malta, Melita
plmn("27877" ++ MSN) ->
	{"278", "77", MSN};
%% Malta, Vodafone
plmn("27801" ++ MSN) ->
	{"278", "01", MSN};
%% Martinique (French Department of), UTS Caraibe
plmn("34012" ++ MSN) ->
	{"340", "12", MSN};
%% Mauritania, Chinguitel SA
plmn("60902" ++ MSN) ->
	{"609", "02", MSN};
%% Mauritania, Mattel
plmn("60901" ++ MSN) ->
	{"609", "01", MSN};
%% Mauritania, Mauritel
plmn("60910" ++ MSN) ->
	{"609", "10", MSN};
%% Mauritius, Emtel Ltd
plmn("61710" ++ MSN) ->
	{"617", "10", MSN};
%% Mauritius, CHILI/MTML
plmn("61703" ++ MSN) ->
	{"617", "03", MSN};
%% Mauritius, CHILI/MTML
plmn("61702" ++ MSN) ->
	{"617", "02", MSN};
%% Mauritius, Orange/Cellplus
plmn("61701" ++ MSN) ->
	{"617", "01", MSN};
%% Mexico, AT&T/IUSACell
plmn("33404" ++ MSN) ->
	{"334", "04", MSN};
%% Mexico, AT&T/IUSACell
plmn("33405" ++ MSN) ->
	{"334", "05", MSN};
%% Mexico, AT&T/IUSACell
plmn("33450" ++ MSN) ->
	{"334", "50", MSN};
%% Mexico, AT&T/IUSACell
plmn("33440" ++ MSN) ->
	{"334", "40", MSN};
%% Mexico, Movistar/Pegaso
plmn("33403" ++ MSN) ->
	{"334", "03", MSN};
%% Mexico, Movistar/Pegaso
plmn("33430" ++ MSN) ->
	{"334", "30", MSN};
%% Mexico, NEXTEL
plmn("33490" ++ MSN) ->
	{"334", "90", MSN};
%% Mexico, NEXTEL
plmn("33410" ++ MSN) ->
	{"334", "10", MSN};
%% Mexico, NEXTEL
plmn("33409" ++ MSN) ->
	{"334", "09", MSN};
%% Mexico, NEXTEL
plmn("33401" ++ MSN) ->
	{"334", "01", MSN};
%% Mexico, Operadora Unefon SA de CV
plmn("33480" ++ MSN) ->
	{"334", "80", MSN};
%% Mexico, Operadora Unefon SA de CV
plmn("33470" ++ MSN) ->
	{"334", "70", MSN};
%% Mexico, SAI PCS
plmn("33460" ++ MSN) ->
	{"334", "60", MSN};
%% Mexico, TelCel/America Movil
plmn("33420" ++ MSN) ->
	{"334", "20", MSN};
%% Mexico, TelCel/America Movil
plmn("33402" ++ MSN) ->
	{"334", "02", MSN};
%% Micronesia, FSM Telecom
plmn("55001" ++ MSN) ->
	{"550", "01", MSN};
%% Moldova, Eventis Mobile
plmn("25904" ++ MSN) ->
	{"259", "04", MSN};
%% Moldova, IDC/Unite
plmn("25905" ++ MSN) ->
	{"259", "05", MSN};
%% Moldova, IDC/Unite
plmn("25903" ++ MSN) ->
	{"259", "03", MSN};
%% Moldova, IDC/Unite
plmn("25999" ++ MSN) ->
	{"259", "99", MSN};
%% Moldova, Moldcell
plmn("25902" ++ MSN) ->
	{"259", "02", MSN};
%% Moldova, Orange/Voxtel
plmn("25901" ++ MSN) ->
	{"259", "01", MSN};
%% Monaco, Monaco Telecom
plmn("21210" ++ MSN) ->
	{"212", "10", MSN};
%% Monaco, Monaco Telecom
plmn("21201" ++ MSN) ->
	{"212", "01", MSN};
%% Mongolia, G-Mobile Corporation Ltd
plmn("42898" ++ MSN) ->
	{"428", "98", MSN};
%% Mongolia, Mobicom
plmn("42899" ++ MSN) ->
	{"428", "99", MSN};
%% Mongolia, Skytel Co. Ltd
plmn("42800" ++ MSN) ->
	{"428", "00", MSN};
%% Mongolia, Skytel Co. Ltd
plmn("42891" ++ MSN) ->
	{"428", "91", MSN};
%% Mongolia, Unitel
plmn("42888" ++ MSN) ->
	{"428", "88", MSN};
%% Mongolia, Ondo / IN Mobile
plmn("42833" ++ MSN) ->
	{"428", "33", MSN};
%% Montenegro, Monet/T-mobile
plmn("29702" ++ MSN) ->
	{"297", "02", MSN};
%% Montenegro, Mtel
plmn("29703" ++ MSN) ->
	{"297", "03", MSN};
%% Montenegro, Telenor/Promonte GSM
plmn("29701" ++ MSN) ->
	{"297", "01", MSN};
%% Montserrat, Cable & Wireless
plmn("354860" ++ MSN) ->
	{"354", "860", MSN};
%% Morocco, Al Houria Telecom
plmn("60404" ++ MSN) ->
	{"604", "04", MSN};
%% Morocco, Al Houria Telecom
plmn("60499" ++ MSN) ->
	{"604", "99", MSN};
%% Morocco, IAM/Itissallat
plmn("60406" ++ MSN) ->
	{"604", "06", MSN};
%% Morocco, IAM/Itissallat
plmn("60401" ++ MSN) ->
	{"604", "01", MSN};
%% Morocco, INWI/WANA
plmn("60405" ++ MSN) ->
	{"604", "05", MSN};
%% Morocco, INWI/WANA
plmn("60402" ++ MSN) ->
	{"604", "02", MSN};
%% Morocco, Orange/Medi Telecom
plmn("60400" ++ MSN) ->
	{"604", "00", MSN};
%% Mozambique, mCel
plmn("64301" ++ MSN) ->
	{"643", "01", MSN};
%% Mozambique, Movitel
plmn("64303" ++ MSN) ->
	{"643", "03", MSN};
%% Mozambique, Vodacom
plmn("64304" ++ MSN) ->
	{"643", "04", MSN};
%% Myanmar (Burma), Myanmar Post & Teleco.
plmn("41401" ++ MSN) ->
	{"414", "01", MSN};
%% Myanmar (Burma), Mytel (Myanmar
plmn("41409" ++ MSN) ->
	{"414", "09", MSN};
%% Myanmar (Burma), Oreedoo
plmn("41405" ++ MSN) ->
	{"414", "05", MSN};
%% Myanmar (Burma), Telenor
plmn("41406" ++ MSN) ->
	{"414", "06", MSN};
%% Namibia, TN Mobile
plmn("64903" ++ MSN) ->
	{"649", "03", MSN};
%% Namibia, MTC
plmn("64901" ++ MSN) ->
	{"649", "01", MSN};
%% Namibia, Switch/Nam. Telec.
plmn("64902" ++ MSN) ->
	{"649", "02", MSN};
%% Nepal, Ncell
plmn("42902" ++ MSN) ->
	{"429", "02", MSN};
%% Nepal, NT Mobile / Namaste
plmn("42901" ++ MSN) ->
	{"429", "01", MSN};
%% Nepal, Smart Cell
plmn("42904" ++ MSN) ->
	{"429", "04", MSN};
%% Netherlands, 6GMOBILE BV
plmn("20414" ++ MSN) ->
	{"204", "14", MSN};
%% Netherlands, Aspider Solutions
plmn("20423" ++ MSN) ->
	{"204", "23", MSN};
%% Netherlands, Elephant Talk Communications Premium Rate Services Netherlands BV
plmn("20405" ++ MSN) ->
	{"204", "05", MSN};
%% Netherlands, Intercity Mobile Communications BV
plmn("20417" ++ MSN) ->
	{"204", "17", MSN};
%% Netherlands, KPN Telecom B.V.
plmn("20410" ++ MSN) ->
	{"204", "10", MSN};
%% Netherlands, KPN Telecom B.V.
plmn("20408" ++ MSN) ->
	{"204", "08", MSN};
%% Netherlands, KPN Telecom B.V.
plmn("20469" ++ MSN) ->
	{"204", "69", MSN};
%% Netherlands, KPN/Telfort
plmn("20412" ++ MSN) ->
	{"204", "12", MSN};
%% Netherlands, Lancelot BV
plmn("20428" ++ MSN) ->
	{"204", "28", MSN};
%% Netherlands, Lycamobile Ltd
plmn("20409" ++ MSN) ->
	{"204", "09", MSN};
%% Netherlands, Mundio/Vectone Mobile
plmn("20406" ++ MSN) ->
	{"204", "06", MSN};
%% Netherlands, NS Railinfrabeheer B.V.
plmn("20421" ++ MSN) ->
	{"204", "21", MSN};
%% Netherlands, Private Mobility Nederland BV
plmn("20424" ++ MSN) ->
	{"204", "24", MSN};
%% Netherlands, T-Mobile B.V.
plmn("20498" ++ MSN) ->
	{"204", "98", MSN};
%% Netherlands, T-Mobile B.V.
plmn("20416" ++ MSN) ->
	{"204", "16", MSN};
%% Netherlands, T-mobile/former Orange
plmn("20420" ++ MSN) ->
	{"204", "20", MSN};
%% Netherlands, Tele2
plmn("20402" ++ MSN) ->
	{"204", "02", MSN};
%% Netherlands, Teleena Holding BV
plmn("20407" ++ MSN) ->
	{"204", "07", MSN};
%% Netherlands, Unify Mobile
plmn("20468" ++ MSN) ->
	{"204", "68", MSN};
%% Netherlands, UPC Nederland BV
plmn("20418" ++ MSN) ->
	{"204", "18", MSN};
%% Netherlands, Vodafone Libertel
plmn("20404" ++ MSN) ->
	{"204", "04", MSN};
%% Netherlands, Voiceworks Mobile BV
plmn("20403" ++ MSN) ->
	{"204", "03", MSN};
%% Netherlands, Ziggo BV
plmn("20415" ++ MSN) ->
	{"204", "15", MSN};
%% Netherlands Antilles, Cingular Wireless
plmn("362630" ++ MSN) ->
	{"362", "630", MSN};
%% Netherlands Antilles, TELCELL GSM
plmn("36251" ++ MSN) ->
	{"362", "51", MSN};
%% Netherlands Antilles, SETEL GSM
plmn("36291" ++ MSN) ->
	{"362", "91", MSN};
%% Netherlands Antilles, UTS Wireless
%% Curacao, EOCG Wireless NV
plmn("362951" ++ MSN) ->
	{"362", "951", MSN};
%% New Caledonia, OPT Mobilis
plmn("54601" ++ MSN) ->
	{"546", "01", MSN};
%% New Zealand, 2degrees
plmn("53028" ++ MSN) ->
	{"530", "28", MSN};
%% New Zealand, Spark/NZ Telecom
plmn("53005" ++ MSN) ->
	{"530", "05", MSN};
%% New Zealand, Spark/NZ Telecom
plmn("53002" ++ MSN) ->
	{"530", "02", MSN};
%% New Zealand, Telstra
plmn("53004" ++ MSN) ->
	{"530", "04", MSN};
%% New Zealand, Two Degrees Mobile Ltd
plmn("53024" ++ MSN) ->
	{"530", "24", MSN};
%% New Zealand, Vodafone
plmn("53001" ++ MSN) ->
	{"530", "01", MSN};
%% New Zealand, Walker Wireless Ltd.
plmn("53003" ++ MSN) ->
	{"530", "03", MSN};
%% Nicaragua, Empresa Nicaraguense de Telecomunicaciones SA (ENITEL)
plmn("71021" ++ MSN) ->
	{"710", "21", MSN};
%% Nicaragua, Movistar
plmn("71030" ++ MSN) ->
	{"710", "30", MSN};
%% Nicaragua, Claro
plmn("71073" ++ MSN) ->
	{"710", "73", MSN};
%% Niger, MOOV/TeleCel
plmn("61403" ++ MSN) ->
	{"614", "03", MSN};
%% Niger, Orange
plmn("61404" ++ MSN) ->
	{"614", "04", MSN};
%% Niger, Sahelcom
plmn("61401" ++ MSN) ->
	{"614", "01", MSN};
%% Niger, Airtel/Zain/CelTel
plmn("61402" ++ MSN) ->
	{"614", "02", MSN};
%% Nigeria, Airtel/ZAIN/Econet
plmn("62120" ++ MSN) ->
	{"621", "20", MSN};
%% Nigeria, ETISALAT
plmn("62160" ++ MSN) ->
	{"621", "60", MSN};
%% Nigeria, Glo Mobile
plmn("62150" ++ MSN) ->
	{"621", "50", MSN};
%% Nigeria, M-Tel/Nigeria Telecom. Ltd.
plmn("62140" ++ MSN) ->
	{"621", "40", MSN};
%% Nigeria, MTN
plmn("62130" ++ MSN) ->
	{"621", "30", MSN};
%% Nigeria, Starcomms
plmn("62199" ++ MSN) ->
	{"621", "99", MSN};
%% Nigeria, Visafone
plmn("62125" ++ MSN) ->
	{"621", "25", MSN};
%% Nigeria, Visafone
plmn("62101" ++ MSN) ->
	{"621", "01", MSN};
%% Niue, Niue Telecom
plmn("55501" ++ MSN) ->
	{"555", "01", MSN};
%% Norway, Com4 AS
plmn("24209" ++ MSN) ->
	{"242", "09", MSN};
%% Norway, ICE Nordisk Mobiltelefon AS
plmn("24214" ++ MSN) ->
	{"242", "14", MSN};
%% Norway, Jernbaneverket (GSM-R)
plmn("24221" ++ MSN) ->
	{"242", "21", MSN};
%% Norway, Jernbaneverket (GSM-R)
plmn("24220" ++ MSN) ->
	{"242", "20", MSN};
%% Norway, Lycamobile Ltd
plmn("24223" ++ MSN) ->
	{"242", "23", MSN};
%% Norway, Telia/Netcom
plmn("24202" ++ MSN) ->
	{"242", "02", MSN};
%% Norway, Telia/Network Norway AS
plmn("24205" ++ MSN) ->
	{"242", "05", MSN};
%% Norway, Telia/Network Norway AS
plmn("24222" ++ MSN) ->
	{"242", "22", MSN};
%% Norway, ICE Nordisk Mobiltelefon AS
plmn("24206" ++ MSN) ->
	{"242", "06", MSN};
%% Norway, TDC Mobil A/S
plmn("24208" ++ MSN) ->
	{"242", "08", MSN};
%% Norway, Tele2
plmn("24204" ++ MSN) ->
	{"242", "04", MSN};
%% Norway, Telenor
plmn("24212" ++ MSN) ->
	{"242", "12", MSN};
%% Norway, Telenor
plmn("24201" ++ MSN) ->
	{"242", "01", MSN};
%% Norway, Teletopia
plmn("24203" ++ MSN) ->
	{"242", "03", MSN};
%% Norway, Ventelo AS
plmn("24217" ++ MSN) ->
	{"242", "17", MSN};
%% Norway, Ventelo AS
plmn("24207" ++ MSN) ->
	{"242", "07", MSN};
%% Oman, Nawras
plmn("42203" ++ MSN) ->
	{"422", "03", MSN};
%% Oman, Oman Mobile/GTO
plmn("42202" ++ MSN) ->
	{"422", "02", MSN};
%% Pakistan, Instaphone
plmn("41008" ++ MSN) ->
	{"410", "08", MSN};
%% Pakistan, Mobilink
plmn("41001" ++ MSN) ->
	{"410", "01", MSN};
%% Pakistan, Telenor
plmn("41006" ++ MSN) ->
	{"410", "06", MSN};
%% Pakistan, UFONE/PAKTel
plmn("41003" ++ MSN) ->
	{"410", "03", MSN};
%% Pakistan, Warid Telecom
plmn("41007" ++ MSN) ->
	{"410", "07", MSN};
%% Pakistan, ZONG/CMPak
plmn("41004" ++ MSN) ->
	{"410", "04", MSN};
%% Palau (Republic of), Palau Mobile Corp. (PMC) (Palau
plmn("55280" ++ MSN) ->
	{"552", "80", MSN};
%% Palau (Republic of), Palau National Communications Corp. (PNCC) (Palau
plmn("55201" ++ MSN) ->
	{"552", "01", MSN};
%% Palau (Republic of), PECI/PalauTel (Palau
plmn("55202" ++ MSN) ->
	{"552", "02", MSN};
%% Palestinian Territory, Jawwal
plmn("42505" ++ MSN) ->
	{"425", "05", MSN};
%% Palestinian Territory, Wataniya Mobile
plmn("42506" ++ MSN) ->
	{"425", "06", MSN};
%% Panama, Cable & W./Mas Movil
plmn("71401" ++ MSN) ->
	{"714", "01", MSN};
%% Panama, Claro
plmn("71403" ++ MSN) ->
	{"714", "03", MSN};
%% Panama, Digicel
plmn("71404" ++ MSN) ->
	{"714", "04", MSN};
%% Panama, Movistar
plmn("71420" ++ MSN) ->
	{"714", "20", MSN};
%% Panama, Movistar
plmn("71402" ++ MSN) ->
	{"714", "02", MSN};
%% Papua New Guinea, Digicel
plmn("53703" ++ MSN) ->
	{"537", "03", MSN};
%% Papua New Guinea, GreenCom PNG Ltd
plmn("53702" ++ MSN) ->
	{"537", "02", MSN};
%% Papua New Guinea, Pacific Mobile
plmn("53701" ++ MSN) ->
	{"537", "01", MSN};
%% Paraguay, Claro/Hutchison
plmn("74402" ++ MSN) ->
	{"744", "02", MSN};
%% Paraguay, Compa
plmn("74403" ++ MSN) ->
	{"744", "03", MSN};
%% Paraguay, Hola/VOX
plmn("74401" ++ MSN) ->
	{"744", "01", MSN};
%% Paraguay, TIM/Nucleo/Personal
plmn("74405" ++ MSN) ->
	{"744", "05", MSN};
%% Paraguay, Tigo/Telecel
plmn("74404" ++ MSN) ->
	{"744", "04", MSN};
%% Peru, Claro /Amer.Mov./TIM
plmn("71620" ++ MSN) ->
	{"716", "20", MSN};
%% Peru, Claro /Amer.Mov./TIM
plmn("71610" ++ MSN) ->
	{"716", "10", MSN};
%% Peru, GlobalStar
plmn("71602" ++ MSN) ->
	{"716", "02", MSN};
%% Peru, GlobalStar
plmn("71601" ++ MSN) ->
	{"716", "01", MSN};
%% Peru, Movistar
plmn("71606" ++ MSN) ->
	{"716", "06", MSN};
%% Peru, Nextel
plmn("71617" ++ MSN) ->
	{"716", "17", MSN};
%% Peru, Nextel
plmn("71607" ++ MSN) ->
	{"716", "07", MSN};
%% Peru, Viettel Mobile
plmn("71615" ++ MSN) ->
	{"716", "15", MSN};
%% Philippines, Fix Line
plmn("51500" ++ MSN) ->
	{"515", "00", MSN};
%% Philippines, Globe Telecom
plmn("51502" ++ MSN) ->
	{"515", "02", MSN};
%% Philippines, Globe Telecom
plmn("51501" ++ MSN) ->
	{"515", "01", MSN};
%% Philippines, Next Mobile
plmn("51588" ++ MSN) ->
	{"515", "88", MSN};
%% Philippines, RED Mobile/Cure
plmn("51518" ++ MSN) ->
	{"515", "18", MSN};
%% Philippines, Smart
plmn("51503" ++ MSN) ->
	{"515", "03", MSN};
%% Philippines, SUN/Digitel
plmn("51505" ++ MSN) ->
	{"515", "05", MSN};
%% Poland, Aero2 SP.
plmn("26017" ++ MSN) ->
	{"260", "17", MSN};
%% Poland, AMD Telecom.
plmn("26018" ++ MSN) ->
	{"260", "18", MSN};
%% Poland, CallFreedom Sp. z o.o.
plmn("26038" ++ MSN) ->
	{"260", "38", MSN};
%% Poland, Cyfrowy POLSAT S.A.
plmn("26012" ++ MSN) ->
	{"260", "12", MSN};
%% Poland, e-Telko
plmn("26008" ++ MSN) ->
	{"260", "08", MSN};
%% Poland, Lycamobile
plmn("26009" ++ MSN) ->
	{"260", "09", MSN};
%% Poland, Mobyland
plmn("26016" ++ MSN) ->
	{"260", "16", MSN};
%% Poland, Mundio Mobile Sp. z o.o.
plmn("26036" ++ MSN) ->
	{"260", "36", MSN};
%% Poland, Play/P4
plmn("26007" ++ MSN) ->
	{"260", "07", MSN};
%% Poland, NORDISK Polska
plmn("26011" ++ MSN) ->
	{"260", "11", MSN};
%% Poland, Orange/IDEA/Centertel
plmn("26005" ++ MSN) ->
	{"260", "05", MSN};
%% Poland, Orange/IDEA/Centertel
plmn("26003" ++ MSN) ->
	{"260", "03", MSN};
%% Poland, PKP Polskie Linie Kolejowe S.A.
plmn("26035" ++ MSN) ->
	{"260", "35", MSN};
%% Poland, Play/P4
plmn("26098" ++ MSN) ->
	{"260", "98", MSN};
%% Poland, Play/P4
plmn("26006" ++ MSN) ->
	{"260", "06", MSN};
%% Poland, Polkomtel/Plus
plmn("26001" ++ MSN) ->
	{"260", "01", MSN};
%% Poland, Sferia
plmn("26013" ++ MSN) ->
	{"260", "13", MSN};
%% Poland, Sferia
plmn("26010" ++ MSN) ->
	{"260", "10", MSN};
%% Poland, Sferia
plmn("26014" ++ MSN) ->
	{"260", "14", MSN};
%% Poland, T-Mobile/ERA
plmn("26034" ++ MSN) ->
	{"260", "34", MSN};
%% Poland, T-Mobile/ERA
plmn("26002" ++ MSN) ->
	{"260", "02", MSN};
%% Poland, Aero2
plmn("26015" ++ MSN) ->
	{"260", "15", MSN};
%% Poland, Aero2
plmn("26004" ++ MSN) ->
	{"260", "04", MSN};
%% Poland, Virgin Mobile
plmn("26045" ++ MSN) ->
	{"260", "45", MSN};
%% Portugal, Lycamobile
plmn("26804" ++ MSN) ->
	{"268", "04", MSN};
%% Portugal, NOS/Optimus
plmn("26803" ++ MSN) ->
	{"268", "03", MSN};
%% Portugal, NOS/Optimus
plmn("26807" ++ MSN) ->
	{"268", "07", MSN};
%% Portugal, MEO/TMN
plmn("26806" ++ MSN) ->
	{"268", "06", MSN};
%% Portugal, Vodafone
plmn("26801" ++ MSN) ->
	{"268", "01", MSN};
%% Puerto Rico, Puerto Rico Telephone Company Inc. (PRTC)
plmn("330110" ++ MSN) ->
	{"330", "110", MSN};
%% Qatar, Ooredoo/Qtel
plmn("42701" ++ MSN) ->
	{"427", "01", MSN};
%% Qatar, Vodafone
plmn("42702" ++ MSN) ->
	{"427", "02", MSN};
%% Reunion, Orange
plmn("64700" ++ MSN) ->
	{"647", "00", MSN};
%% Reunion, Outremer Telecom
plmn("64702" ++ MSN) ->
	{"647", "02", MSN};
%% Reunion, SFR
plmn("64710" ++ MSN) ->
	{"647", "10", MSN};
%% Romania, Telekom Romania
plmn("22603" ++ MSN) ->
	{"226", "03", MSN};
%% Romania, Enigma Systems
plmn("22611" ++ MSN) ->
	{"226", "11", MSN};
%% Romania, Lycamobile
plmn("22616" ++ MSN) ->
	{"226", "16", MSN};
%% Romania, Orange
plmn("22610" ++ MSN) ->
	{"226", "10", MSN};
%% Romania, RCS&RDS Digi Mobile
plmn("22605" ++ MSN) ->
	{"226", "05", MSN};
%% Romania, Romtelecom SA
plmn("22602" ++ MSN) ->
	{"226", "02", MSN};
%% Romania, Telekom Romania
plmn("22606" ++ MSN) ->
	{"226", "06", MSN};
%% Romania, Vodafone
plmn("22601" ++ MSN) ->
	{"226", "01", MSN};
%% Romania, Telekom Romania
plmn("22604" ++ MSN) ->
	{"226", "04", MSN};
%% Russian Federation, Baykal Westcom
plmn("25012" ++ MSN) ->
	{"250", "12", MSN};
%% Russian Federation, BeeLine/VimpelCom
plmn("25099" ++ MSN) ->
	{"250", "99", MSN};
%% Russian Federation, BeeLine/VimpelCom
plmn("25028" ++ MSN) ->
	{"250", "28", MSN};
%% Russian Federation, DTC/Don Telecom
plmn("25010" ++ MSN) ->
	{"250", "10", MSN};
%% Russian Federation, Kuban GSM
plmn("25013" ++ MSN) ->
	{"250", "13", MSN};
%% Russian Federation, MOTIV/LLC Ekaterinburg-2000
plmn("25035" ++ MSN) ->
	{"250", "35", MSN};
%% Russian Federation, Megafon
plmn("25002" ++ MSN) ->
	{"250", "02", MSN};
%% Russian Federation, MTS
plmn("25001" ++ MSN) ->
	{"250", "01", MSN};
%% Russian Federation, NCC
plmn("25003" ++ MSN) ->
	{"250", "03", MSN};
%% Russian Federation, NTC
plmn("25016" ++ MSN) ->
	{"250", "16", MSN};
%% Russian Federation, OJSC Altaysvyaz
plmn("25019" ++ MSN) ->
	{"250", "19", MSN};
%% Russian Federation, Orensot
plmn("25011" ++ MSN) ->
	{"250", "11", MSN};
%% Russian Federation, Printelefone
plmn("25092" ++ MSN) ->
	{"250", "92", MSN};
%% Russian Federation, Sibchallenge
plmn("25004" ++ MSN) ->
	{"250", "04", MSN};
%% Russian Federation, StavTelesot
plmn("25044" ++ MSN) ->
	{"250", "44", MSN};
%% Russian Federation, Tele2/ECC/Volgogr.
plmn("25020" ++ MSN) ->
	{"250", "20", MSN};
%% Russian Federation, Telecom XXL
plmn("25093" ++ MSN) ->
	{"250", "93", MSN};
%% Russian Federation, UralTel
plmn("25039" ++ MSN) ->
	{"250", "39", MSN};
%% Russian Federation, UralTel
plmn("25017" ++ MSN) ->
	{"250", "17", MSN};
%% Russian Federation, Tele2/ECC/Volgogr.
plmn("25005" ++ MSN) ->
	{"250", "05", MSN};
%% Russian Federation, ZAO SMARTS
plmn("25015" ++ MSN) ->
	{"250", "15", MSN};
%% Russian Federation, ZAO SMARTS
plmn("25007" ++ MSN) ->
	{"250", "07", MSN};
%% Rwanda, Airtel
plmn("63514" ++ MSN) ->
	{"635", "14", MSN};
%% Rwanda, MTN/Rwandacell
plmn("63510" ++ MSN) ->
	{"635", "10", MSN};
%% Rwanda, TIGO
plmn("63513" ++ MSN) ->
	{"635", "13", MSN};
%% Saint Kitts and Nevis, Cable & Wireless
plmn("356110" ++ MSN) ->
	{"356", "110", MSN};
%% Saint Kitts and Nevis, Digicel
plmn("35650" ++ MSN) ->
	{"356", "50", MSN};
%% Saint Kitts and Nevis, UTS Cariglobe
plmn("35670" ++ MSN) ->
	{"356", "70", MSN};
%% Saint Lucia, Cable & Wireless
plmn("358110" ++ MSN) ->
	{"358", "110", MSN};
%% Saint Lucia, Cingular Wireless
plmn("35830" ++ MSN) ->
	{"358", "30", MSN};
%% Saint Lucia, Digicel (St Lucia) Limited
plmn("35850" ++ MSN) ->
	{"358", "50", MSN};
%% Samoa, Samoatel Mobile
plmn("54927" ++ MSN) ->
	{"549", "27", MSN};
%% Samoa, Telecom Samoa Cellular Ltd.
plmn("54901" ++ MSN) ->
	{"549", "01", MSN};
%% San Marino, Prima Telecom
plmn("29201" ++ MSN) ->
	{"292", "01", MSN};
%% Sao Tome & Principe, CSTmovel
plmn("62601" ++ MSN) ->
	{"626", "01", MSN};
%% Satellite Networks, AeroMobile
plmn("90114" ++ MSN) ->
	{"901", "14", MSN};
%% Satellite Networks, InMarSAT
plmn("90111" ++ MSN) ->
	{"901", "11", MSN};
%% Satellite Networks, Maritime Communications Partner AS
plmn("90112" ++ MSN) ->
	{"901", "12", MSN};
%% Satellite Networks, Thuraya Satellite
plmn("90105" ++ MSN) ->
	{"901", "05", MSN};
%% Saudi Arabia, Zain
plmn("42007" ++ MSN) ->
	{"420", "07", MSN};
%% Saudi Arabia, Etihad/Etisalat/Mobily
plmn("42003" ++ MSN) ->
	{"420", "03", MSN};
%% Saudi Arabia, Lebara Mobile
plmn("42006" ++ MSN) ->
	{"420", "06", MSN};
%% Saudi Arabia, STC/Al Jawal
plmn("42001" ++ MSN) ->
	{"420", "01", MSN};
%% Saudi Arabia, Virgin Mobile
plmn("42005" ++ MSN) ->
	{"420", "05", MSN};
%% Saudi Arabia, Zain
plmn("42004" ++ MSN) ->
	{"420", "04", MSN};
%% Senegal, Expresso/Sudatel
plmn("60803" ++ MSN) ->
	{"608", "03", MSN};
%% Senegal, Orange/Sonatel
plmn("60801" ++ MSN) ->
	{"608", "01", MSN};
%% Senegal, TIGO/Sentel GSM
plmn("60802" ++ MSN) ->
	{"608", "02", MSN};
%% Serbia, MTS/Telekom Srbija
plmn("22003" ++ MSN) ->
	{"220", "03", MSN};
%% Serbia, Telenor/Mobtel
plmn("22001" ++ MSN) ->
	{"220", "01", MSN};
%% Serbia, Telenor/Mobtel
plmn("22002" ++ MSN) ->
	{"220", "02", MSN};
%% Serbia, VIP Mobile
plmn("22005" ++ MSN) ->
	{"220", "05", MSN};
%% Seychelles, Airtel
plmn("63310" ++ MSN) ->
	{"633", "10", MSN};
%% Seychelles, C&W
plmn("63301" ++ MSN) ->
	{"633", "01", MSN};
%% Seychelles, Smartcom
plmn("63302" ++ MSN) ->
	{"633", "02", MSN};
%% Sierra Leone, Africel
plmn("61903" ++ MSN) ->
	{"619", "03", MSN};
%% Sierra Leone, Orange
plmn("61901" ++ MSN) ->
	{"619", "01", MSN};
%% Sierra Leone, Comium
plmn("61904" ++ MSN) ->
	{"619", "04", MSN};
%% Sierra Leone, Africel
plmn("61905" ++ MSN) ->
	{"619", "05", MSN};
%% Sierra Leone, Tigo/Millicom
plmn("61902" ++ MSN) ->
	{"619", "02", MSN};
%% Sierra Leone, Mobitel
plmn("61925" ++ MSN) ->
	{"619", "25", MSN};
%% Sierra Leone, Qcell
plmn("61907" ++ MSN) ->
	{"619", "07", MSN};
%% Singapore, GRID Communications Pte Ltd
plmn("52512" ++ MSN) ->
	{"525", "12", MSN};
%% Singapore, MobileOne Ltd
plmn("52503" ++ MSN) ->
	{"525", "03", MSN};
%% Singapore, Singtel
plmn("52501" ++ MSN) ->
	{"525", "01", MSN};
%% Singapore, Singtel
plmn("52507" ++ MSN) ->
	{"525", "07", MSN};
%% Singapore, Singtel
plmn("52502" ++ MSN) ->
	{"525", "02", MSN};
%% Singapore, Starhub
plmn("52506" ++ MSN) ->
	{"525", "06", MSN};
%% Singapore, Starhub
plmn("52505" ++ MSN) ->
	{"525", "05", MSN};
%% Slovakia, Swan/4Ka
plmn("23103" ++ MSN) ->
	{"231", "03", MSN};
%% Slovakia, O2
plmn("23106" ++ MSN) ->
	{"231", "06", MSN};
%% Slovakia, Orange
plmn("23101" ++ MSN) ->
	{"231", "01", MSN};
%% Slovakia, Orange
plmn("23105" ++ MSN) ->
	{"231", "05", MSN};
%% Slovakia, Orange
plmn("23115" ++ MSN) ->
	{"231", "15", MSN};
%% Slovakia, T-Mobile
plmn("23102" ++ MSN) ->
	{"231", "02", MSN};
%% Slovakia, T-Mobile
plmn("23104" ++ MSN) ->
	{"231", "04", MSN};
%% Slovakia, Zeleznice Slovenskej republiky (ZSR)
plmn("23199" ++ MSN) ->
	{"231", "99", MSN};
%% Slovenia, Mobitel
plmn("29341" ++ MSN) ->
	{"293", "41", MSN};
%% Slovenia, SI.Mobil
plmn("29340" ++ MSN) ->
	{"293", "40", MSN};
%% Slovenia, Slovenske zeleznice d.o.o.
plmn("29310" ++ MSN) ->
	{"293", "10", MSN};
%% Slovenia, T-2 d.o.o.
plmn("29364" ++ MSN) ->
	{"293", "64", MSN};
%% Slovenia, Telemach/TusMobil/VEGA
plmn("29370" ++ MSN) ->
	{"293", "70", MSN};
%% Solomon Islands, bemobile
plmn("54002" ++ MSN) ->
	{"540", "02", MSN};
%% Solomon Islands, BREEZE
plmn("54010" ++ MSN) ->
	{"540", "10", MSN};
%% Solomon Islands, BREEZE
plmn("54001" ++ MSN) ->
	{"540", "01", MSN};
%% Somalia, Golis
plmn("63730" ++ MSN) ->
	{"637", "30", MSN};
%% Somalia, Hormuud
plmn("63750" ++ MSN) ->
	{"637", "50", MSN};
%% Somalia, HorTel
plmn("63719" ++ MSN) ->
	{"637", "19", MSN};
%% Somalia, Nationlink
plmn("63760" ++ MSN) ->
	{"637", "60", MSN};
%% Somalia, Nationlink
plmn("63710" ++ MSN) ->
	{"637", "10", MSN};
%% Somalia, Somafone
plmn("63704" ++ MSN) ->
	{"637", "04", MSN};
%% Somalia, Somtel
plmn("63782" ++ MSN) ->
	{"637", "82", MSN};
%% Somalia, Somtel
plmn("63771" ++ MSN) ->
	{"637", "71", MSN};
%% Somalia, Telesom
plmn("63701" ++ MSN) ->
	{"637", "01", MSN};
%% South Africa, Telkom/8.ta
plmn("65502" ++ MSN) ->
	{"655", "02", MSN};
%% South Africa, Cape Town Metropolitan
plmn("65521" ++ MSN) ->
	{"655", "21", MSN};
%% South Africa, Cell C
plmn("65507" ++ MSN) ->
	{"655", "07", MSN};
%% South Africa, MTN
plmn("65512" ++ MSN) ->
	{"655", "12", MSN};
%% South Africa, MTN
plmn("65510" ++ MSN) ->
	{"655", "10", MSN};
%% South Africa, Sentech
plmn("65506" ++ MSN) ->
	{"655", "06", MSN};
%% South Africa, Vodacom
plmn("65501" ++ MSN) ->
	{"655", "01", MSN};
%% South Africa, Wireless Business Solutions (Pty) Ltd
plmn("65519" ++ MSN) ->
	{"655", "19", MSN};
%% South Sudan (Republic of), Gemtel Ltd (South Sudan
plmn("65903" ++ MSN) ->
	{"659", "03", MSN};
%% South Sudan (Republic of), MTN South Sudan (South Sudan
plmn("65902" ++ MSN) ->
	{"659", "02", MSN};
%% South Sudan (Republic of), Network of The World Ltd (NOW) (South Sudan
plmn("65904" ++ MSN) ->
	{"659", "04", MSN};
%% South Sudan (Republic of), Zain South Sudan (South Sudan
plmn("65906" ++ MSN) ->
	{"659", "06", MSN};
%% Spain, Lycamobile SL
plmn("21423" ++ MSN) ->
	{"214", "23", MSN};
%% Spain, Digi Spain Telecom SL
plmn("21422" ++ MSN) ->
	{"214", "22", MSN};
%% Spain, BT Espana SAU
plmn("21415" ++ MSN) ->
	{"214", "15", MSN};
%% Spain, Cableuropa SAU (ONO)
plmn("21418" ++ MSN) ->
	{"214", "18", MSN};
%% Spain, Euskaltel SA
plmn("21408" ++ MSN) ->
	{"214", "08", MSN};
%% Spain, fonYou Wireless SL
plmn("21420" ++ MSN) ->
	{"214", "20", MSN};
%% Spain, ION Mobile
plmn("21432" ++ MSN) ->
	{"214", "32", MSN};
%% Spain, Jazz Telecom SAU
plmn("21421" ++ MSN) ->
	{"214", "21", MSN};
%% Spain, Lleida
plmn("21426" ++ MSN) ->
	{"214", "26", MSN};
%% Spain, Lycamobile SL
plmn("21425" ++ MSN) ->
	{"214", "25", MSN};
%% Spain, Movistar
plmn("21407" ++ MSN) ->
	{"214", "07", MSN};
%% Spain, Movistar
plmn("21405" ++ MSN) ->
	{"214", "05", MSN};
%% Spain, Orange
plmn("21403" ++ MSN) ->
	{"214", "03", MSN};
%% Spain, Orange
plmn("21409" ++ MSN) ->
	{"214", "09", MSN};
%% Spain, Orange
plmn("21411" ++ MSN) ->
	{"214", "11", MSN};
%% Spain, R Cable y Telec. Galicia SA
plmn("21417" ++ MSN) ->
	{"214", "17", MSN};
%% Spain, Simyo/KPN
plmn("21419" ++ MSN) ->
	{"214", "19", MSN};
%% Spain, Telecable de Asturias SA
plmn("21416" ++ MSN) ->
	{"214", "16", MSN};
%% Spain, Truphone
plmn("21427" ++ MSN) ->
	{"214", "27", MSN};
%% Spain, Vodafone
plmn("21401" ++ MSN) ->
	{"214", "01", MSN};
%% Spain, Vodafone Enabler Espana SL
plmn("21406" ++ MSN) ->
	{"214", "06", MSN};
%% Spain, Yoigo
plmn("21404" ++ MSN) ->
	{"214", "04", MSN};
%% Sri Lanka, Airtel
plmn("41305" ++ MSN) ->
	{"413", "05", MSN};
%% Sri Lanka, Etisalat/Tigo
plmn("41303" ++ MSN) ->
	{"413", "03", MSN};
%% Sri Lanka, H3G Hutchison
plmn("41308" ++ MSN) ->
	{"413", "08", MSN};
%% Sri Lanka, Mobitel Ltd.
plmn("41301" ++ MSN) ->
	{"413", "01", MSN};
%% Sri Lanka, MTN/Dialog
plmn("41302" ++ MSN) ->
	{"413", "02", MSN};
%% St. Pierre & Miquelon, Ameris
plmn("30801" ++ MSN) ->
	{"308", "01", MSN};
%% St. Vincent & Gren., C & W
plmn("360110" ++ MSN) ->
	{"360", "110", MSN};
%% St. Vincent & Gren., Cingular
plmn("360100" ++ MSN) ->
	{"360", "100", MSN};
%% St. Vincent & Gren., Cingular
plmn("36010" ++ MSN) ->
	{"360", "10", MSN};
%% St. Vincent & Gren., Digicel
plmn("36050" ++ MSN) ->
	{"360", "50", MSN};
%% St. Vincent & Gren., Digicel
plmn("36070" ++ MSN) ->
	{"360", "70", MSN};
%% Sudan, Canar Telecom
plmn("63400" ++ MSN) ->
	{"634", "00", MSN};
%% Sudan, MTN
plmn("63422" ++ MSN) ->
	{"634", "22", MSN};
%% Sudan, MTN
plmn("63402" ++ MSN) ->
	{"634", "02", MSN};
%% Sudan, Sudani One
plmn("63415" ++ MSN) ->
	{"634", "15", MSN};
%% Sudan, Sudani One
plmn("63407" ++ MSN) ->
	{"634", "07", MSN};
%% Sudan, Canar Telecom
plmn("63405" ++ MSN) ->
	{"634", "05", MSN};
%% Sudan, Canar Telecom
plmn("63408" ++ MSN) ->
	{"634", "08", MSN};
%% Sudan, ZAIN/Mobitel
plmn("63406" ++ MSN) ->
	{"634", "06", MSN};
%% Sudan, ZAIN/Mobitel
plmn("63401" ++ MSN) ->
	{"634", "01", MSN};
%% Suriname, Digicel
plmn("74603" ++ MSN) ->
	{"746", "03", MSN};
%% Suriname, Telesur
plmn("74601" ++ MSN) ->
	{"746", "01", MSN};
%% Suriname, Telecommunicatiebedrijf Suriname (TELESUR)
plmn("74602" ++ MSN) ->
	{"746", "02", MSN};
%% Suriname, UNIQA
plmn("74604" ++ MSN) ->
	{"746", "04", MSN};
%% Swaziland, Swazi Mobile
plmn("65302" ++ MSN) ->
	{"653", "02", MSN};
%% Swaziland, Swazi MTN
plmn("65310" ++ MSN) ->
	{"653", "10", MSN};
%% Swaziland, SwaziTelecom
plmn("65301" ++ MSN) ->
	{"653", "01", MSN};
%% Sweden, 42 Telecom AB
plmn("24035" ++ MSN) ->
	{"240", "35", MSN};
%% Sweden, 42 Telecom AB
plmn("24016" ++ MSN) ->
	{"240", "16", MSN};
%% Sweden, Beepsend
plmn("24026" ++ MSN) ->
	{"240", "26", MSN};
%% Sweden, NextGen Mobile Ltd (CardBoardFish)
plmn("24030" ++ MSN) ->
	{"240", "30", MSN};
%% Sweden, CoolTEL Aps
plmn("24028" ++ MSN) ->
	{"240", "28", MSN};
%% Sweden, Digitel Mobile Srl
plmn("24025" ++ MSN) ->
	{"240", "25", MSN};
%% Sweden, Eu Tel AB
plmn("24022" ++ MSN) ->
	{"240", "22", MSN};
%% Sweden, Fogg Mobile AB
plmn("24027" ++ MSN) ->
	{"240", "27", MSN};
%% Sweden, Generic Mobile Systems Sweden AB
plmn("24018" ++ MSN) ->
	{"240", "18", MSN};
%% Sweden, Gotalandsnatet AB
plmn("24017" ++ MSN) ->
	{"240", "17", MSN};
%% Sweden, H3G Access AB
plmn("24004" ++ MSN) ->
	{"240", "04", MSN};
%% Sweden, H3G Access AB
plmn("24002" ++ MSN) ->
	{"240", "02", MSN};
%% Sweden, ID Mobile
plmn("24036" ++ MSN) ->
	{"240", "36", MSN};
%% Sweden, Infobip Ltd.
plmn("24023" ++ MSN) ->
	{"240", "23", MSN};
%% Sweden, Lindholmen Science Park AB
plmn("24011" ++ MSN) ->
	{"240", "11", MSN};
%% Sweden, Lycamobile Ltd
plmn("24012" ++ MSN) ->
	{"240", "12", MSN};
%% Sweden, Mercury International Carrier Services
plmn("24029" ++ MSN) ->
	{"240", "29", MSN};
%% Sweden, Mundio Mobile (Sweden) Ltd
plmn("24019" ++ MSN) ->
	{"240", "19", MSN};
%% Sweden, Netett Sverige AB
plmn("24003" ++ MSN) ->
	{"240", "03", MSN};
%% Sweden, Spring Mobil AB
plmn("24010" ++ MSN) ->
	{"240", "10", MSN};
%% Sweden, Svenska UMTS-N
plmn("24005" ++ MSN) ->
	{"240", "05", MSN};
%% Sweden, TDC Sverige AB
plmn("24014" ++ MSN) ->
	{"240", "14", MSN};
%% Sweden, Tele2 Sverige AB
plmn("24007" ++ MSN) ->
	{"240", "07", MSN};
%% Sweden, Telenor (Vodafone)
plmn("24024" ++ MSN) ->
	{"240", "24", MSN};
%% Sweden, Telenor (Vodafone)
plmn("24008" ++ MSN) ->
	{"240", "08", MSN};
%% Sweden, Telenor (Vodafone)
plmn("24006" ++ MSN) ->
	{"240", "06", MSN};
%% Sweden, Telia Mobile
plmn("24001" ++ MSN) ->
	{"240", "01", MSN};
%% Sweden, Ventelo Sverige AB
plmn("24013" ++ MSN) ->
	{"240", "13", MSN};
%% Sweden, Wireless Maingate AB
plmn("24020" ++ MSN) ->
	{"240", "20", MSN};
%% Sweden, Wireless Maingate Nordic AB
plmn("24015" ++ MSN) ->
	{"240", "15", MSN};
%% Switzerland, BebbiCell AG
plmn("22851" ++ MSN) ->
	{"228", "51", MSN};
%% Switzerland, Beeone
plmn("22858" ++ MSN) ->
	{"228", "58", MSN};
%% Switzerland, Comfone AG
plmn("22809" ++ MSN) ->
	{"228", "09", MSN};
%% Switzerland, Comfone AG
plmn("22805" ++ MSN) ->
	{"228", "05", MSN};
%% Switzerland, TDC Sunrise
plmn("22807" ++ MSN) ->
	{"228", "07", MSN};
%% Switzerland, Lycamobile AG
plmn("22854" ++ MSN) ->
	{"228", "54", MSN};
%% Switzerland, Mundio Mobile AG
plmn("22852" ++ MSN) ->
	{"228", "52", MSN};
%% Switzerland, Salt/Orange
plmn("22803" ++ MSN) ->
	{"228", "03", MSN};
%% Switzerland, Swisscom
plmn("22801" ++ MSN) ->
	{"228", "01", MSN};
%% Switzerland, TDC Sunrise
plmn("22812" ++ MSN) ->
	{"228", "12", MSN};
%% Switzerland, TDC Sunrise
plmn("22802" ++ MSN) ->
	{"228", "02", MSN};
%% Switzerland, TDC Sunrise
plmn("22808" ++ MSN) ->
	{"228", "08", MSN};
%% Switzerland, upc cablecom GmbH
plmn("22853" ++ MSN) ->
	{"228", "53", MSN};
%% Syrian Arab Republic, MTN/Spacetel
plmn("41702" ++ MSN) ->
	{"417", "02", MSN};
%% Syrian Arab Republic, Syriatel Holdings
plmn("41709" ++ MSN) ->
	{"417", "09", MSN};
%% Syrian Arab Republic, Syriatel Holdings
plmn("41701" ++ MSN) ->
	{"417", "01", MSN};
%% Taiwan, ACeS Taiwan - ACeS Taiwan Telecommunications Co Ltd
plmn("46668" ++ MSN) ->
	{"466", "68", MSN};
%% Taiwan, Asia Pacific Telecom Co. Ltd (APT)
plmn("46605" ++ MSN) ->
	{"466", "05", MSN};
%% Taiwan, Chunghwa Telecom LDM
plmn("46692" ++ MSN) ->
	{"466", "92", MSN};
%% Taiwan, Chunghwa Telecom LDM
plmn("46611" ++ MSN) ->
	{"466", "11", MSN};
%% Taiwan, Far EasTone
plmn("46607" ++ MSN) ->
	{"466", "07", MSN};
%% Taiwan, Far EasTone
plmn("46606" ++ MSN) ->
	{"466", "06", MSN};
%% Taiwan, Far EasTone
plmn("46603" ++ MSN) ->
	{"466", "03", MSN};
%% Taiwan, Far EasTone
plmn("46602" ++ MSN) ->
	{"466", "02", MSN};
%% Taiwan, Far EasTone
plmn("46601" ++ MSN) ->
	{"466", "01", MSN};
%% Taiwan, Global Mobile Corp.
plmn("46610" ++ MSN) ->
	{"466", "10", MSN};
%% Taiwan, International Telecom Co. Ltd (FITEL)
plmn("46656" ++ MSN) ->
	{"466", "56", MSN};
%% Taiwan, KG Telecom
plmn("46688" ++ MSN) ->
	{"466", "88", MSN};
%% Taiwan, T-Star/VIBO
plmn("46690" ++ MSN) ->
	{"466", "90", MSN};
%% Taiwan, Taiwan Cellular
plmn("46697" ++ MSN) ->
	{"466", "97", MSN};
%% Taiwan, Mobitai
plmn("46693" ++ MSN) ->
	{"466", "93", MSN};
%% Taiwan, TransAsia
plmn("46699" ++ MSN) ->
	{"466", "99", MSN};
%% Taiwan, T-Star/VIBO
plmn("46689" ++ MSN) ->
	{"466", "89", MSN};
%% Taiwan, VMAX Telecom Co. Ltd
plmn("46609" ++ MSN) ->
	{"466", "09", MSN};
%% Tajikistan, Babilon-M
plmn("43604" ++ MSN) ->
	{"436", "04", MSN};
%% Tajikistan, Bee Line
plmn("43605" ++ MSN) ->
	{"436", "05", MSN};
%% Tajikistan, CJSC Indigo Tajikistan
plmn("43602" ++ MSN) ->
	{"436", "02", MSN};
%% Tajikistan, Tcell/JC Somoncom
plmn("43612" ++ MSN) ->
	{"436", "12", MSN};
%% Tajikistan, Megafon
plmn("43603" ++ MSN) ->
	{"436", "03", MSN};
%% Tajikistan, Tcell/JC Somoncom
plmn("43601" ++ MSN) ->
	{"436", "01", MSN};
%% Tanzania, Benson Informatics Ltd
plmn("64008" ++ MSN) ->
	{"640", "08", MSN};
%% Tanzania, Dovetel (T) Ltd
plmn("64006" ++ MSN) ->
	{"640", "06", MSN};
%% Tanzania, Halotel/Viettel Ltd
plmn("64009" ++ MSN) ->
	{"640", "09", MSN};
%% Tanzania, Smile Communications Tanzania Ltd
plmn("64011" ++ MSN) ->
	{"640", "11", MSN};
%% Tanzania, Tanzania Telecommunications Company Ltd (TTCL)
plmn("64007" ++ MSN) ->
	{"640", "07", MSN};
%% Tanzania, TIGO/MIC
plmn("64002" ++ MSN) ->
	{"640", "02", MSN};
%% Tanzania, Tri Telecomm. Ltd.
plmn("64001" ++ MSN) ->
	{"640", "01", MSN};
%% Tanzania, Vodacom Ltd
plmn("64004" ++ MSN) ->
	{"640", "04", MSN};
%% Tanzania, Airtel/ZAIN/Celtel
plmn("64005" ++ MSN) ->
	{"640", "05", MSN};
%% Tanzania, Zantel/Zanzibar Telecom
plmn("64003" ++ MSN) ->
	{"640", "03", MSN};
%% Thailand, ACeS Thailand - ACeS Regional Services Co Ltd
plmn("52020" ++ MSN) ->
	{"520", "20", MSN};
%% Thailand, ACT Mobile
plmn("52015" ++ MSN) ->
	{"520", "15", MSN};
%% Thailand, AIS/Advanced Info Service
plmn("52003" ++ MSN) ->
	{"520", "03", MSN};
%% Thailand, AIS/Advanced Info Service
plmn("52001" ++ MSN) ->
	{"520", "01", MSN};
%% Thailand, Digital Phone Co.
plmn("52023" ++ MSN) ->
	{"520", "23", MSN};
%% Thailand, Hutch/CAT CDMA
plmn("52000" ++ MSN) ->
	{"520", "00", MSN};
%% Thailand, Total Access (DTAC)
plmn("52005" ++ MSN) ->
	{"520", "05", MSN};
%% Thailand, Total Access (DTAC)
plmn("52018" ++ MSN) ->
	{"520", "18", MSN};
%% Thailand, True Move/Orange
plmn("52099" ++ MSN) ->
	{"520", "99", MSN};
%% Thailand, True Move/Orange
plmn("52004" ++ MSN) ->
	{"520", "04", MSN};
%% Timor-Leste, Telin/ Telkomcel
plmn("51401" ++ MSN) ->
	{"514", "01", MSN};
%% Timor-Leste, Timor Telecom
plmn("51402" ++ MSN) ->
	{"514", "02", MSN};
%% Togo, Telecel/MOOV
plmn("61502" ++ MSN) ->
	{"615", "02", MSN};
%% Togo, Telecel/MOOV
plmn("61503" ++ MSN) ->
	{"615", "03", MSN};
%% Togo, Togo Telecom/TogoCELL
plmn("61501" ++ MSN) ->
	{"615", "01", MSN};
%% Tonga, Digicel
plmn("53988" ++ MSN) ->
	{"539", "88", MSN};
%% Tonga, Shoreline Communication
plmn("53943" ++ MSN) ->
	{"539", "43", MSN};
%% Tonga, Tonga Communications
plmn("53901" ++ MSN) ->
	{"539", "01", MSN};
%% Trinidad and Tobago, Bmobile/TSTT
plmn("37412" ++ MSN) ->
	{"374", "12", MSN};
%% Trinidad and Tobago, Digicel
plmn("374130" ++ MSN) ->
	{"374", "130", MSN};
%% Trinidad and Tobago, LaqTel Ltd.
plmn("374140" ++ MSN) ->
	{"374", "140", MSN};
%% Tunisia, Orange
plmn("60501" ++ MSN) ->
	{"605", "01", MSN};
%% Tunisia, Oreedo/Orascom
plmn("60503" ++ MSN) ->
	{"605", "03", MSN};
%% Tunisia, TuniCell/Tunisia Telecom
plmn("60506" ++ MSN) ->
	{"605", "06", MSN};
%% Tunisia, TuniCell/Tunisia Telecom
plmn("60502" ++ MSN) ->
	{"605", "02", MSN};
%% Turkey, AVEA/Aria
plmn("28603" ++ MSN) ->
	{"286", "03", MSN};
%% Turkey, AVEA/Aria
plmn("28604" ++ MSN) ->
	{"286", "04", MSN};
%% Turkey, Turkcell
plmn("28601" ++ MSN) ->
	{"286", "01", MSN};
%% Turkey, Vodafone-Telsim
plmn("28602" ++ MSN) ->
	{"286", "02", MSN};
%% Turkmenistan, MTS/Barash Communication
plmn("43801" ++ MSN) ->
	{"438", "01", MSN};
%% Turkmenistan, Altyn Asyr/TM-Cell
plmn("43802" ++ MSN) ->
	{"438", "02", MSN};
%% Turks and Caicos Islands, Cable & Wireless (TCI) Ltd
plmn("376350" ++ MSN) ->
	{"376", "350", MSN};
%% "Virgin Islands,  U.S.",Digicel
%% Turks and Caicos Islands, Digicel TCI Ltd
plmn("37650" ++ MSN) ->
	{"376", "50", MSN};
%% Turks and Caicos Islands, IslandCom Communications Ltd.
plmn("376352" ++ MSN) ->
	{"376", "352", MSN};
%% Tuvalu, Tuvalu Telecommunication Corporation (TTC)
plmn("55301" ++ MSN) ->
	{"553", "01", MSN};
%% Uganda, Airtel/Celtel
plmn("64101" ++ MSN) ->
	{"641", "01", MSN};
%% Uganda, i-Tel Ltd
plmn("64166" ++ MSN) ->
	{"641", "66", MSN};
%% Uganda, K2 Telecom Ltd
plmn("64130" ++ MSN) ->
	{"641", "30", MSN};
%% Uganda, MTN Ltd.
plmn("64110" ++ MSN) ->
	{"641", "10", MSN};
%% Uganda, Orange
plmn("64114" ++ MSN) ->
	{"641", "14", MSN};
%% Uganda, Smile Communications Uganda Ltd
plmn("64133" ++ MSN) ->
	{"641", "33", MSN};
%% Uganda, Suretelecom Uganda Ltd
plmn("64118" ++ MSN) ->
	{"641", "18", MSN};
%% Uganda, Uganda Telecom Ltd.
plmn("64111" ++ MSN) ->
	{"641", "11", MSN};
%% Uganda, Airtel/Warid
plmn("64122" ++ MSN) ->
	{"641", "22", MSN};
%% Ukraine, Astelit/LIFE
plmn("25506" ++ MSN) ->
	{"255", "06", MSN};
%% Ukraine, Golden Telecom
plmn("25505" ++ MSN) ->
	{"255", "05", MSN};
%% Ukraine, Golden Telecom
plmn("25539" ++ MSN) ->
	{"255", "39", MSN};
%% Ukraine, Intertelecom Ltd (IT)
plmn("25504" ++ MSN) ->
	{"255", "04", MSN};
%% Ukraine, KyivStar
plmn("25567" ++ MSN) ->
	{"255", "67", MSN};
%% Ukraine, KyivStar
plmn("25503" ++ MSN) ->
	{"255", "03", MSN};
%% Ukraine, Phoenix
plmn("25599" ++ MSN) ->
	{"255", "99", MSN};
%% Ukraine, Telesystems Of Ukraine CJSC (TSU)
plmn("25521" ++ MSN) ->
	{"255", "21", MSN};
%% Ukraine, TriMob LLC
plmn("25507" ++ MSN) ->
	{"255", "07", MSN};
%% Ukraine, Vodafone/MTS
plmn("25550" ++ MSN) ->
	{"255", "50", MSN};
%% Ukraine, Beeline
plmn("25502" ++ MSN) ->
	{"255", "02", MSN};
%% Ukraine, Vodafone/MTS
plmn("25501" ++ MSN) ->
	{"255", "01", MSN};
%% Ukraine, Beeline
plmn("25568" ++ MSN) ->
	{"255", "68", MSN};
%% United Arab Emirates, DU
plmn("42403" ++ MSN) ->
	{"424", "03", MSN};
%% United Arab Emirates, Etisalat
plmn("43002" ++ MSN) ->
	{"430", "02", MSN};
%% United Arab Emirates, Etisalat
plmn("42402" ++ MSN) ->
	{"424", "02", MSN};
%% United Arab Emirates, Etisalat
plmn("43102" ++ MSN) ->
	{"431", "02", MSN};
%% United Kingdom, Airtel/Vodafone
plmn("23403" ++ MSN) ->
	{"234", "03", MSN};
%% United Kingdom, BT Group
plmn("23400" ++ MSN) ->
	{"234", "00", MSN};
%% United Kingdom, BT Group
plmn("23476" ++ MSN) ->
	{"234", "76", MSN};
%% United Kingdom, BT Group
plmn("23477" ++ MSN) ->
	{"234", "77", MSN};
%% United Kingdom, Cable and Wireless
plmn("23492" ++ MSN) ->
	{"234", "92", MSN};
%% United Kingdom, Cable and Wireless
plmn("23407" ++ MSN) ->
	{"234", "07", MSN};
%% United Kingdom, Cable and Wireless Isle of Man
plmn("23436" ++ MSN) ->
	{"234", "36", MSN};
%% United Kingdom, Cloud9/wire9 Tel.
plmn("23418" ++ MSN) ->
	{"234", "18", MSN};
%% United Kingdom, Everyth. Ev.wh.
plmn("23502" ++ MSN) ->
	{"235", "02", MSN};
%% United Kingdom, FIX Line
plmn("234999" ++ MSN) ->
	{"234", "999", MSN};
%% United Kingdom, FlexTel
plmn("23417" ++ MSN) ->
	{"234", "17", MSN};
%% United Kingdom, Guernsey Telecoms
plmn("23455" ++ MSN) ->
	{"234", "55", MSN};
%% United Kingdom, HaySystems
plmn("23414" ++ MSN) ->
	{"234", "14", MSN};
%% United Kingdom, H3G Hutchinson
plmn("23420" ++ MSN) ->
	{"234", "20", MSN};
%% United Kingdom, H3G Hutchinson
plmn("23494" ++ MSN) ->
	{"234", "94", MSN};
%% United Kingdom, Inquam Telecom Ltd
plmn("23475" ++ MSN) ->
	{"234", "75", MSN};
%% United Kingdom, Jersey Telecom
plmn("23450" ++ MSN) ->
	{"234", "50", MSN};
%% United Kingdom, JSC Ingenicum
plmn("23435" ++ MSN) ->
	{"234", "35", MSN};
%% United Kingdom, Lycamobile
plmn("23426" ++ MSN) ->
	{"234", "26", MSN};
%% United Kingdom, Manx Telecom
plmn("23458" ++ MSN) ->
	{"234", "58", MSN};
%% United Kingdom, Mapesbury C. Ltd
plmn("23401" ++ MSN) ->
	{"234", "01", MSN};
%% United Kingdom, Marthon Telecom
plmn("23428" ++ MSN) ->
	{"234", "28", MSN};
%% United Kingdom, O2 Ltd.
plmn("23410" ++ MSN) ->
	{"234", "10", MSN};
%% United Kingdom, O2 Ltd.
plmn("23402" ++ MSN) ->
	{"234", "02", MSN};
%% United Kingdom, O2 Ltd.
plmn("23411" ++ MSN) ->
	{"234", "11", MSN};
%% United Kingdom, OnePhone
plmn("23408" ++ MSN) ->
	{"234", "08", MSN};
%% United Kingdom, Opal Telecom
plmn("23416" ++ MSN) ->
	{"234", "16", MSN};
%% United Kingdom, Everyth. Ev.wh./Orange
plmn("23433" ++ MSN) ->
	{"234", "33", MSN};
%% United Kingdom, Everyth. Ev.wh./Orange
plmn("23434" ++ MSN) ->
	{"234", "34", MSN};
%% United Kingdom, PMN/Teleware
plmn("23419" ++ MSN) ->
	{"234", "19", MSN};
%% United Kingdom, Railtrack Plc
plmn("23412" ++ MSN) ->
	{"234", "12", MSN};
%% United Kingdom, Routotelecom
plmn("23422" ++ MSN) ->
	{"234", "22", MSN};
%% United Kingdom, Sky UK Limited
plmn("23457" ++ MSN) ->
	{"234", "57", MSN};
%% United Kingdom, Stour Marine
plmn("23424" ++ MSN) ->
	{"234", "24", MSN};
%% United Kingdom, Synectiv Ltd.
plmn("23437" ++ MSN) ->
	{"234", "37", MSN};
%% United Kingdom, Everyth. Ev.wh./T-Mobile
plmn("23431" ++ MSN) ->
	{"234", "31", MSN};
%% United Kingdom, Everyth. Ev.wh./T-Mobile
plmn("23430" ++ MSN) ->
	{"234", "30", MSN};
%% United Kingdom, Everyth. Ev.wh./T-Mobile
plmn("23432" ++ MSN) ->
	{"234", "32", MSN};
%% United Kingdom, Vodafone
plmn("23427" ++ MSN) ->
	{"234", "27", MSN};
%% United Kingdom, Tismi
plmn("23409" ++ MSN) ->
	{"234", "09", MSN};
%% United Kingdom, Truphone
plmn("23425" ++ MSN) ->
	{"234", "25", MSN};
%% United Kingdom, Jersey Telecom
plmn("23451" ++ MSN) ->
	{"234", "51", MSN};
%% United Kingdom, Vectofone Mobile Wifi
plmn("23423" ++ MSN) ->
	{"234", "23", MSN};
%% United Kingdom, Virgin Mobile
plmn("23438" ++ MSN) ->
	{"234", "38", MSN};
%% United Kingdom, Vodafone
plmn("23491" ++ MSN) ->
	{"234", "91", MSN};
%% United Kingdom, Vodafone
plmn("23415" ++ MSN) ->
	{"234", "15", MSN};
%% United Kingdom, Vodafone
plmn("23489" ++ MSN) ->
	{"234", "89", MSN};
%% United Kingdom, Wave Telecom Ltd
plmn("23478" ++ MSN) ->
	{"234", "78", MSN};
%% United States,
plmn("310880" ++ MSN) ->
	{"310", "880", MSN};
%% United States, Aeris Comm. Inc.
plmn("310850" ++ MSN) ->
	{"310", "850", MSN};
%% United States,
plmn("310640" ++ MSN) ->
	{"310", "640", MSN};
%% United States, Airtel Wireless LLC
plmn("310510" ++ MSN) ->
	{"310", "510", MSN};
%% United States, Unknown
plmn("310190" ++ MSN) ->
	{"310", "190", MSN};
%% United States, Allied Wireless Communications Corporation
plmn("31290" ++ MSN) ->
	{"312", "90", MSN};
%% United States,
plmn("311130" ++ MSN) ->
	{"311", "130", MSN};
%% United States, Arctic Slope Telephone Association Cooperative Inc.
plmn("310710" ++ MSN) ->
	{"310", "710", MSN};
%% United States, AT&T Wireless Inc.
plmn("310150" ++ MSN) ->
	{"310", "150", MSN};
%% United States, AT&T Wireless Inc.
plmn("310680" ++ MSN) ->
	{"310", "680", MSN};
%% United States, AT&T Wireless Inc.
plmn("310560" ++ MSN) ->
	{"310", "560", MSN};
%% United States, AT&T Wireless Inc.
plmn("310410" ++ MSN) ->
	{"310", "410", MSN};
%% United States, AT&T Wireless Inc.
plmn("310380" ++ MSN) ->
	{"310", "380", MSN};
%% United States, AT&T Wireless Inc.
plmn("310170" ++ MSN) ->
	{"310", "170", MSN};
%% United States, AT&T Wireless Inc.
plmn("310980" ++ MSN) ->
	{"310", "980", MSN};
%% United States, Bluegrass Wireless LLC
plmn("311810" ++ MSN) ->
	{"311", "810", MSN};
%% United States, Bluegrass Wireless LLC
plmn("311800" ++ MSN) ->
	{"311", "800", MSN};
%% United States, Bluegrass Wireless LLC
plmn("311440" ++ MSN) ->
	{"311", "440", MSN};
%% United States, Cable & Communications Corp.
plmn("310900" ++ MSN) ->
	{"310", "900", MSN};
%% United States, California RSA No. 3 Limited Partnership
plmn("311590" ++ MSN) ->
	{"311", "590", MSN};
%% United States, Cambridge Telephone Company Inc.
plmn("311500" ++ MSN) ->
	{"311", "500", MSN};
%% United States, Caprock Cellular Ltd.
plmn("310830" ++ MSN) ->
	{"310", "830", MSN};
%% United States, Verizon Wireless
plmn("311271" ++ MSN) ->
	{"311", "271", MSN};
%% United States, Verizon Wireless
plmn("311287" ++ MSN) ->
	{"311", "287", MSN};
%% United States, Verizon Wireless
plmn("311276" ++ MSN) ->
	{"311", "276", MSN};
%% United States, Verizon Wireless
plmn("311481" ++ MSN) ->
	{"311", "481", MSN};
%% United States, Verizon Wireless
plmn("311281" ++ MSN) ->
	{"311", "281", MSN};
%% United States, Verizon Wireless
plmn("311486" ++ MSN) ->
	{"311", "486", MSN};
%% United States, Verizon Wireless
plmn("311270" ++ MSN) ->
	{"311", "270", MSN};
%% United States, Verizon Wireless
plmn("311286" ++ MSN) ->
	{"311", "286", MSN};
%% United States, Verizon Wireless
plmn("311275" ++ MSN) ->
	{"311", "275", MSN};
%% United States, Verizon Wireless
plmn("311480" ++ MSN) ->
	{"311", "480", MSN};
%% United States, Verizon Wireless
%% United States, Sprint Spectrum
plmn("31012" ++ MSN) ->
	{"310", "12", MSN};
%% United States, Verizon Wireless
plmn("311280" ++ MSN) ->
	{"311", "280", MSN};
%% United States, Verizon Wireless
plmn("311485" ++ MSN) ->
	{"311", "485", MSN};
%% United States, Verizon Wireless
plmn("311110" ++ MSN) ->
	{"311", "110", MSN};
%% United States, Verizon Wireless
plmn("311285" ++ MSN) ->
	{"311", "285", MSN};
%% United States, Verizon Wireless
plmn("311274" ++ MSN) ->
	{"311", "274", MSN};
%% United States, Verizon Wireless
plmn("311390" ++ MSN) ->
	{"311", "390", MSN};
%% United States, Verizon Wireless
%% United States, Plateau Telecommunications Inc.
plmn("31010" ++ MSN) ->
	{"310", "10", MSN};
%% United States, Verizon Wireless
plmn("311279" ++ MSN) ->
	{"311", "279", MSN};
%% United States, Verizon Wireless
plmn("311484" ++ MSN) ->
	{"311", "484", MSN};
%% United States, Verizon Wireless
plmn("310910" ++ MSN) ->
	{"310", "910", MSN};
%% United States, Verizon Wireless
plmn("311284" ++ MSN) ->
	{"311", "284", MSN};
%% United States, Verizon Wireless
plmn("311489" ++ MSN) ->
	{"311", "489", MSN};
%% United States, Verizon Wireless
plmn("311273" ++ MSN) ->
	{"311", "273", MSN};
%% United States, Verizon Wireless
plmn("311289" ++ MSN) ->
	{"311", "289", MSN};
%% United States, Verizon Wireless
plmn("31004" ++ MSN) ->
	{"310", "04", MSN};
%% United States, Verizon Wireless
plmn("311278" ++ MSN) ->
	{"311", "278", MSN};
%% United States, Verizon Wireless
plmn("311483" ++ MSN) ->
	{"311", "483", MSN};
%% United States, Verizon Wireless
plmn("310890" ++ MSN) ->
	{"310", "890", MSN};
%% United States, Verizon Wireless
plmn("311283" ++ MSN) ->
	{"311", "283", MSN};
%% United States, Verizon Wireless
plmn("311488" ++ MSN) ->
	{"311", "488", MSN};
%% United States, Verizon Wireless
plmn("311272" ++ MSN) ->
	{"311", "272", MSN};
%% United States, Verizon Wireless
plmn("311288" ++ MSN) ->
	{"311", "288", MSN};
%% United States, Verizon Wireless
plmn("311277" ++ MSN) ->
	{"311", "277", MSN};
%% United States, Verizon Wireless
plmn("311482" ++ MSN) ->
	{"311", "482", MSN};
%% United States, Verizon Wireless
plmn("310590" ++ MSN) ->
	{"310", "590", MSN};
%% United States, Verizon Wireless
plmn("311282" ++ MSN) ->
	{"311", "282", MSN};
%% United States, Verizon Wireless
plmn("311487" ++ MSN) ->
	{"311", "487", MSN};
%% United States, Cellular Network Partnership LLC
plmn("312280" ++ MSN) ->
	{"312", "280", MSN};
%% United States, Cellular Network Partnership LLC
plmn("312270" ++ MSN) ->
	{"312", "270", MSN};
%% United States, Cellular Network Partnership LLC
plmn("310360" ++ MSN) ->
	{"310", "360", MSN};
%% United States,
plmn("311190" ++ MSN) ->
	{"311", "190", MSN};
%% United States, Choice Phone LLC
plmn("311120" ++ MSN) ->
	{"311", "120", MSN};
%% United States, Choice Phone LLC
plmn("310480" ++ MSN) ->
	{"310", "480", MSN};
%% United States,
plmn("310630" ++ MSN) ->
	{"310", "630", MSN};
%% United States, Cincinnati Bell Wireless LLC
plmn("310420" ++ MSN) ->
	{"310", "420", MSN};
%% United States, Cingular Wireless
plmn("310180" ++ MSN) ->
	{"310", "180", MSN};
%% United States, Coleman County Telco /Trans TX
plmn("310620" ++ MSN) ->
	{"310", "620", MSN};
%% United States,
plmn("31140" ++ MSN) ->
	{"311", "40", MSN};
%% United States, Consolidated Telcom
plmn("31006" ++ MSN) ->
	{"310", "06", MSN};
%% United States,
plmn("312380" ++ MSN) ->
	{"312", "380", MSN};
%% United States,
plmn("310930" ++ MSN) ->
	{"310", "930", MSN};
%% United States,
plmn("311240" ++ MSN) ->
	{"311", "240", MSN};
%% United States, Cross Valliant Cellular Partnership
%% United States, AT&T Wireless Inc.
plmn("310700" ++ MSN) ->
	{"310", "700", MSN};
%% United States, Cross Wireless Telephone Co.
plmn("31230" ++ MSN) ->
	{"312", "30", MSN};
%% United States, Cross Wireless Telephone Co.
plmn("311140" ++ MSN) ->
	{"311", "140", MSN};
%% United States,
plmn("311520" ++ MSN) ->
	{"311", "520", MSN};
%% United States, Custer Telephone Cooperative Inc.
plmn("31240" ++ MSN) ->
	{"312", "40", MSN};
%% United States, Dobson Cellular Systems
plmn("310440" ++ MSN) ->
	{"310", "440", MSN};
%% United States, E.N.M.R. Telephone Coop.
plmn("310990" ++ MSN) ->
	{"310", "990", MSN};
%% United States, East Kentucky Network LLC
plmn("312120" ++ MSN) ->
	{"312", "120", MSN};
%% United States, East Kentucky Network LLC
plmn("310750" ++ MSN) ->
	{"310", "750", MSN};
%% United States, East Kentucky Network LLC
plmn("312130" ++ MSN) ->
	{"312", "130", MSN};
%% United States, Edge Wireless LLC
plmn("31090" ++ MSN) ->
	{"310", "90", MSN};
%% United States, Elkhart TelCo. / Epic Touch Co.
plmn("310610" ++ MSN) ->
	{"310", "610", MSN};
%% United States,
plmn("311210" ++ MSN) ->
	{"311", "210", MSN};
%% United States, Farmers
plmn("311311" ++ MSN) ->
	{"311", "311", MSN};
%% United States, Fisher Wireless Services Inc.
plmn("311460" ++ MSN) ->
	{"311", "460", MSN};
%% United States, GCI Communication Corp.
plmn("311370" ++ MSN) ->
	{"311", "370", MSN};
%% United States, GCI Communication Corp.
plmn("310430" ++ MSN) ->
	{"310", "430", MSN};
%% United States, Get Mobile Inc.
plmn("310920" ++ MSN) ->
	{"310", "920", MSN};
%% United States,
plmn("310970" ++ MSN) ->
	{"310", "970", MSN};
%% United States, Illinois Valley Cellular RSA 2 Partnership
plmn("311340" ++ MSN) ->
	{"311", "340", MSN};
%% United States, Iowa RSA No. 2 Limited Partnership
plmn("311410" ++ MSN) ->
	{"311", "410", MSN};
%% United States, Iowa RSA No. 2 Limited Partnership
plmn("312170" ++ MSN) ->
	{"312", "170", MSN};
%% United States, Iowa Wireless Services LLC
plmn("310770" ++ MSN) ->
	{"310", "770", MSN};
%% United States, Jasper
plmn("310650" ++ MSN) ->
	{"310", "650", MSN};
%% United States, Kaplan Telephone Company Inc.
plmn("310870" ++ MSN) ->
	{"310", "870", MSN};
%% United States, Keystone Wireless LLC
plmn("312180" ++ MSN) ->
	{"312", "180", MSN};
%% United States, Keystone Wireless LLC
plmn("310690" ++ MSN) ->
	{"310", "690", MSN};
%% United States, Lamar County Cellular
plmn("311310" ++ MSN) ->
	{"311", "310", MSN};
%% United States, Leap Wireless International Inc.
plmn("31016" ++ MSN) ->
	{"310", "16", MSN};
%% United States,
plmn("31190" ++ MSN) ->
	{"311", "90", MSN};
%% United States, Message Express Co. / Airlink PCS
plmn("310780" ++ MSN) ->
	{"310", "780", MSN};
%% United States,
plmn("311660" ++ MSN) ->
	{"311", "660", MSN};
%% United States, Michigan Wireless LLC
plmn("311330" ++ MSN) ->
	{"311", "330", MSN};
%% United States,
plmn("31100" ++ MSN) ->
	{"311", "00", MSN};
%% United States, Minnesota South. Wirel. Co. / Hickory
%% United States, Matanuska Tel. Assn. Inc.
plmn("310400" ++ MSN) ->
	{"310", "400", MSN};
%% United States, Missouri RSA No 5 Partnership
plmn("31120" ++ MSN) ->
	{"311", "20", MSN};
%% United States, Missouri RSA No 5 Partnership
plmn("31110" ++ MSN) ->
	{"311", "10", MSN};
%% United States, Missouri RSA No 5 Partnership
plmn("312220" ++ MSN) ->
	{"312", "220", MSN};
%% United States, Missouri RSA No 5 Partnership
plmn("31210" ++ MSN) ->
	{"312", "10", MSN};
%% United States, Missouri RSA No 5 Partnership
plmn("311920" ++ MSN) ->
	{"311", "920", MSN};
%% United States, Mohave Cellular LP
plmn("310350" ++ MSN) ->
	{"310", "350", MSN};
%% United States, MTPCS LLC
plmn("310570" ++ MSN) ->
	{"310", "570", MSN};
%% United States, NEP Cellcorp Inc.
plmn("310290" ++ MSN) ->
	{"310", "290", MSN};
%% United States, Nevada Wireless LLC
%% United States, "Westlink Communications, LLC"
plmn("31034" ++ MSN) ->
	{"310", "34", MSN};
%% United States,
plmn("311380" ++ MSN) ->
	{"311", "380", MSN};
%% United States, New-Cell Inc.
%% United States, Consolidated Telcom
plmn("310600" ++ MSN) ->
	{"310", "600", MSN};
%% United States, Nexus Communications Inc.
plmn("311300" ++ MSN) ->
	{"311", "300", MSN};
%% United States, North Carolina RSA 3 Cellular Tel. Co.
plmn("310130" ++ MSN) ->
	{"310", "130", MSN};
%% United States, North Dakota Network Company
plmn("312230" ++ MSN) ->
	{"312", "230", MSN};
%% United States, North Dakota Network Company
plmn("311610" ++ MSN) ->
	{"311", "610", MSN};
%% United States, Northeast Colorado Cellular Inc.
plmn("310450" ++ MSN) ->
	{"310", "450", MSN};
%% United States, Northeast Wireless Networks LLC
plmn("311710" ++ MSN) ->
	{"311", "710", MSN};
%% United States, Northstar
plmn("310670" ++ MSN) ->
	{"310", "670", MSN};
%% United States, Northstar
plmn("31011" ++ MSN) ->
	{"310", "11", MSN};
%% United States, Northwest Missouri Cellular Limited Partnership
plmn("311420" ++ MSN) ->
	{"311", "420", MSN};
%% United States,
plmn("310540" ++ MSN) ->
	{"310", "540", MSN};
%% United States, Various Networks
plmn("310999" ++ MSN) ->
	{"310", "999", MSN};
%% United States, Panhandle Telephone Cooperative Inc.
plmn("310760" ++ MSN) ->
	{"310", "760", MSN};
%% United States, PCS ONE
plmn("310580" ++ MSN) ->
	{"310", "580", MSN};
%% United States, PetroCom
plmn("311170" ++ MSN) ->
	{"311", "170", MSN};
%% United States, "Pine Belt Cellular, Inc."
plmn("311670" ++ MSN) ->
	{"311", "670", MSN};
%% United States,
plmn("31180" ++ MSN) ->
	{"311", "80", MSN};
%% United States,
plmn("310790" ++ MSN) ->
	{"310", "790", MSN};
%% United States, Poka Lambro Telco Ltd.
plmn("310940" ++ MSN) ->
	{"310", "940", MSN};
%% United States,
plmn("311730" ++ MSN) ->
	{"311", "730", MSN};
%% United States,
plmn("311540" ++ MSN) ->
	{"311", "540", MSN};
%% United States, Public Service Cellular Inc.
plmn("310500" ++ MSN) ->
	{"310", "500", MSN};
%% United States, RSA 1 Limited Partnership
plmn("312160" ++ MSN) ->
	{"312", "160", MSN};
%% United States, RSA 1 Limited Partnership
plmn("311430" ++ MSN) ->
	{"311", "430", MSN};
%% United States, Sagebrush Cellular Inc.
plmn("311350" ++ MSN) ->
	{"311", "350", MSN};
%% United States,
plmn("311910" ++ MSN) ->
	{"311", "910", MSN};
%% United States, SIMMETRY
%% United States, TMP Corporation
plmn("31046" ++ MSN) ->
	{"310", "46", MSN};
%% United States, SLO Cellular Inc / Cellular One of San Luis
plmn("311260" ++ MSN) ->
	{"311", "260", MSN};
%% United States, Unknown
plmn("31015" ++ MSN) ->
	{"310", "15", MSN};
%% United States, Southern Communications Services Inc.
plmn("31611" ++ MSN) ->
	{"316", "11", MSN};
%% United States, Sprint Spectrum
plmn("312530" ++ MSN) ->
	{"312", "530", MSN};
%% United States, Sprint Spectrum
plmn("311870" ++ MSN) ->
	{"311", "870", MSN};
%% United States, Sprint Spectrum
plmn("311490" ++ MSN) ->
	{"311", "490", MSN};
%% United States, Sprint Spectrum
plmn("31610" ++ MSN) ->
	{"316", "10", MSN};
%% United States, Sprint Spectrum
plmn("312190" ++ MSN) ->
	{"312", "190", MSN};
%% United States, Sprint Spectrum
plmn("311880" ++ MSN) ->
	{"311", "880", MSN};
%% United States, T-Mobile
plmn("310260" ++ MSN) ->
	{"310", "260", MSN};
%% United States, T-Mobile
plmn("310200" ++ MSN) ->
	{"310", "200", MSN};
%% United States, T-Mobile
plmn("310250" ++ MSN) ->
	{"310", "250", MSN};
%% United States, T-Mobile
plmn("310240" ++ MSN) ->
	{"310", "240", MSN};
%% United States, T-Mobile
plmn("310660" ++ MSN) ->
	{"310", "660", MSN};
%% United States, T-Mobile
plmn("310230" ++ MSN) ->
	{"310", "230", MSN};
%% United States, T-Mobile
plmn("310220" ++ MSN) ->
	{"310", "220", MSN};
%% United States, T-Mobile
plmn("310270" ++ MSN) ->
	{"310", "270", MSN};
%% United States, T-Mobile
plmn("310210" ++ MSN) ->
	{"310", "210", MSN};
%% United States, T-Mobile
plmn("310300" ++ MSN) ->
	{"310", "300", MSN};
%% United States, T-Mobile
plmn("310280" ++ MSN) ->
	{"310", "280", MSN};
%% United States, T-Mobile
plmn("310800" ++ MSN) ->
	{"310", "800", MSN};
%% United States, T-Mobile
plmn("310310" ++ MSN) ->
	{"310", "310", MSN};
%% United States,
plmn("311740" ++ MSN) ->
	{"311", "740", MSN};
%% United States, Telemetrix Inc.
plmn("310740" ++ MSN) ->
	{"310", "740", MSN};
%% United States, Testing
plmn("31014" ++ MSN) ->
	{"310", "14", MSN};
%% United States, Unknown
plmn("310950" ++ MSN) ->
	{"310", "950", MSN};
%% United States, Texas RSA 15B2 Limited Partnership
plmn("310860" ++ MSN) ->
	{"310", "860", MSN};
%% United States, Thumb Cellular Limited Partnership
plmn("311830" ++ MSN) ->
	{"311", "830", MSN};
%% United States, Thumb Cellular Limited Partnership
plmn("31150" ++ MSN) ->
	{"311", "50", MSN};
%% United States, Triton PCS
plmn("310490" ++ MSN) ->
	{"310", "490", MSN};
%% United States, Uintah Basin Electronics Telecommunications Inc.
plmn("312290" ++ MSN) ->
	{"312", "290", MSN};
%% United States, Uintah Basin Electronics Telecommunications Inc.
plmn("311860" ++ MSN) ->
	{"311", "860", MSN};
%% United States, Uintah Basin Electronics Telecommunications Inc.
plmn("310960" ++ MSN) ->
	{"310", "960", MSN};
%% United States, Union Telephone Co.
plmn("31020" ++ MSN) ->
	{"310", "20", MSN};
%% United States, United States Cellular Corp.
plmn("311220" ++ MSN) ->
	{"311", "220", MSN};
%% United States, United States Cellular Corp.
plmn("310730" ++ MSN) ->
	{"310", "730", MSN};
%% United States, United Wireless Communications Inc.
plmn("311650" ++ MSN) ->
	{"311", "650", MSN};
%% United States, USA 3650 AT&T
plmn("31038" ++ MSN) ->
	{"310", "38", MSN};
%% United States, VeriSign
plmn("310520" ++ MSN) ->
	{"310", "520", MSN};
%% United States, Unknown
plmn("31003" ++ MSN) ->
	{"310", "03", MSN};
%% United States, Unknown
plmn("31023" ++ MSN) ->
	{"310", "23", MSN};
%% United States, Unknown
plmn("31024" ++ MSN) ->
	{"310", "24", MSN};
%% United States, Unknown
plmn("31025" ++ MSN) ->
	{"310", "25", MSN};
%% United States, West Virginia Wireless
plmn("310530" ++ MSN) ->
	{"310", "530", MSN};
%% United States, Unknown
plmn("31026" ++ MSN) ->
	{"310", "26", MSN};
%% United States
plmn("311150" ++ MSN) ->
	{"311", "150", MSN};
%% United States, Wisconsin RSA #7 Limited Partnership
plmn("31170" ++ MSN) ->
	{"311", "70", MSN};
%% United States, Yorkville Telephone Cooperative
plmn("310390" ++ MSN) ->
	{"310", "390", MSN};
%% Uruguay, Ancel/Antel
plmn("74801" ++ MSN) ->
	{"748", "01", MSN};
%% Uruguay, Ancel/Antel
plmn("74803" ++ MSN) ->
	{"748", "03", MSN};
%% Uruguay, Ancel/Antel
plmn("74800" ++ MSN) ->
	{"748", "00", MSN};
%% Uruguay, Claro/AM Wireless
plmn("74810" ++ MSN) ->
	{"748", "10", MSN};
%% Uruguay, MOVISTAR
plmn("74807" ++ MSN) ->
	{"748", "07", MSN};
%% Uzbekistan, Bee Line/Unitel
plmn("43404" ++ MSN) ->
	{"434", "04", MSN};
%% Uzbekistan, Buztel
plmn("43401" ++ MSN) ->
	{"434", "01", MSN};
%% Uzbekistan, MTS/Uzdunrobita
plmn("43407" ++ MSN) ->
	{"434", "07", MSN};
%% Uzbekistan, Ucell/Coscom
plmn("43405" ++ MSN) ->
	{"434", "05", MSN};
%% Uzbekistan, Uzmacom
plmn("43402" ++ MSN) ->
	{"434", "02", MSN};
%% Vanuatu, DigiCel
plmn("54105" ++ MSN) ->
	{"541", "05", MSN};
%% Vanuatu, SMILE
plmn("54101" ++ MSN) ->
	{"541", "01", MSN};
%% Venezuela, DigiTel C.A.
plmn("73403" ++ MSN) ->
	{"734", "03", MSN};
%% Venezuela, DigiTel C.A.
plmn("73402" ++ MSN) ->
	{"734", "02", MSN};
%% Venezuela, DigiTel C.A.
plmn("73401" ++ MSN) ->
	{"734", "01", MSN};
%% Venezuela, Movilnet C.A.
plmn("73406" ++ MSN) ->
	{"734", "06", MSN};
%% Venezuela, Movistar/TelCel
plmn("73404" ++ MSN) ->
	{"734", "04", MSN};
%% Viet Nam, Gmobile
plmn("45207" ++ MSN) ->
	{"452", "07", MSN};
%% Viet Nam, I-Telecom
plmn("45208" ++ MSN) ->
	{"452", "08", MSN};
%% Viet Nam, Mobifone
plmn("45201" ++ MSN) ->
	{"452", "01", MSN};
%% Viet Nam, S-Fone/Telecom
plmn("45203" ++ MSN) ->
	{"452", "03", MSN};
%% Viet Nam, VietnaMobile
plmn("45205" ++ MSN) ->
	{"452", "05", MSN};
%% Viet Nam, Viettel Mobile
plmn("45204" ++ MSN) ->
	{"452", "04", MSN};
%% Viet Nam, Viettel Mobile
plmn("45206" ++ MSN) ->
	{"452", "06", MSN};
%% Viet Nam, Vinaphone
plmn("45202" ++ MSN) ->
	{"452", "02", MSN};
%% Yemen, HITS/Y Unitel
plmn("42104" ++ MSN) ->
	{"421", "04", MSN};
%% Yemen, MTN/Spacetel
plmn("42102" ++ MSN) ->
	{"421", "02", MSN};
%% Yemen, Sabaphone
plmn("42101" ++ MSN) ->
	{"421", "01", MSN};
%% Yemen, Yemen Mob. CDMA
plmn("42103" ++ MSN) ->
	{"421", "03", MSN};
%% Zambia, Zamtel/Cell Z/MTS
plmn("64503" ++ MSN) ->
	{"645", "03", MSN};
%% Zambia, MTN/Telecel
plmn("64502" ++ MSN) ->
	{"645", "02", MSN};
%% Zambia, Airtel/Zain/Celtel
plmn("64501" ++ MSN) ->
	{"645", "01", MSN};
%% Zimbabwe, Econet
plmn("64804" ++ MSN) ->
	{"648", "04", MSN};
%% Zimbabwe, Net One
plmn("64801" ++ MSN) ->
	{"648", "01", MSN};
%% Zimbabwe, Telecel
plmn("64803" ++ MSN) ->
	{"648", "03", MSN}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

