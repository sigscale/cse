%%% cse_codec.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021-2025 SigScale Global Inc.
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
%%% @doc This library module implements CODEC functions for the
%%%   {@link //cse. cse} application.
%%%
-module(cse_codec).
-copyright('Copyright (c) 2021-2025 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse_codec  public API
-export([called_party/1, calling_party/1, called_party_bcd/1,
		isdn_address/1, tbcd/1, generic_number/1, generic_digits/1,
		date_time/1, cause/1, ims_uri/1, rat_type/1,
		redirect_info/1]).

-ifdef(CAP).
-export([error_code/1]).
-include_lib("cap/include/CAP-errorcodes.hrl").
-endif.
-include("cse_codec.hrl").

-type called_party() :: #called_party{}.
-type called_party_bcd() :: #called_party_bcd{}.
-type calling_party() :: #calling_party{}.
-type isdn_address() :: #isdn_address{}.
-type generic_number() :: #generic_number{}.
-type generic_digits() :: #generic_digits{}.
-type redirect_info() :: #redirect_info{}.
-type cause() :: #cause{}.
%% Use of ISUP cause values is described in ITU-T Q.850.
-type ims_uri() :: #ims_uri{}.
-export_types([called_party/0, called_party_bcd/0, calling_party/0,
		isdn_address/0, generic_number/0, generic_digits/0, cause/0,
		ims_uri/0, redirect_info/0]).

%%----------------------------------------------------------------------
%%  The cse_codec public API
%%----------------------------------------------------------------------

-spec called_party(CalledParty) -> CalledParty
	when
		CalledParty :: called_party() | binary().
%% @doc CODEC for ISUP CalledParty IE.
called_party(<<OE:1, NAI:7, INN:1, NPI:3, _:4,
		Address/binary>> = _CalledParty) ->
	called_party1(OE, Address,
			#called_party{nai = NAI, inn = INN, npi = NPI}, []);
called_party(#called_party{nai = NAI,
		inn = INN, npi = NPI, address = Address}) ->
	OE = length(Address) rem 2,
	called_party2(Address, <<OE:1, NAI:7, INN:1, NPI:3, 0:4>>).
%% @hidden
called_party1(0, <<A2:4, A1:4>>, CP, Acc) ->
	CP#called_party{address = lists:reverse([A2, A1 | Acc])};
called_party1(1, <<_:4, A:4>>, CP, Acc) ->
	CP#called_party{address = lists:reverse([A | Acc])};
called_party1(OE, <<A2:4, A1:4, Rest/binary>>, CP, Acc) ->
	called_party1(OE, Rest, CP, [A2, A1 | Acc]).
%% @hidden
called_party2([A1, A2 | T], Acc) ->
	called_party2(T, <<Acc/binary, A2:4, A1:4>>);
called_party2([A], Acc) ->
	<<Acc/binary, 0:4, A:4>>;
called_party2([], Acc) ->
	Acc.

-spec calling_party(CallingParty) -> CallingParty
	when
		CallingParty :: calling_party() | binary().
%% @doc CODEC for ISUP CallingParty IE.
calling_party(<<OE:1, NAI:7, NI:1, NPI:3, APRI:2, SI:2,
		Address/binary>> = _CallingParty) ->
	calling_party1(OE, Address, #calling_party{nai = NAI,
			ni = NI, npi = NPI, apri = APRI, si = SI}, []);
calling_party(#calling_party{nai = NAI, ni = NI,
		npi = NPI, apri = APRI, si = SI, address = Address}) ->
	OE = length(Address) rem 2,
	calling_party2(Address,
			<<OE:1, NAI:7, NI:1, NPI:3, APRI:2, SI:2>>).
%% @hidden
calling_party1(0, <<A2:4, A1:4>>, CP, Acc) ->
	CP#calling_party{address = lists:reverse([A2, A1 | Acc])};
calling_party1(1, <<_:4, A:4>>, CP, Acc) ->
	CP#calling_party{address = lists:reverse([A | Acc])};
calling_party1(OE, <<A2:4, A1:4, Rest/binary>>, CP, Acc) ->
	calling_party1(OE, Rest, CP, [A2, A1 | Acc]).
%% @hidden
calling_party2([A1, A2 | T], Acc) ->
	calling_party2(T, <<Acc/binary, A2:4, A1:4>>);
calling_party2([A], Acc) ->
	<<Acc/binary, 0:4, A:4>>;
calling_party2([], Acc) ->
	Acc.

-spec called_party_bcd(CalledParty) -> CalledParty
	when
		CalledParty :: called_party_bcd() | binary().
%% @doc CODEC for CAMEL CalledPartyBCD IE.
called_party_bcd(<<_:1, TON:3, NPI:4,
		Address/binary>> = _CalledParty) ->
	called_party_bcd1(Address,
			#called_party_bcd{ton = TON, npi = NPI}, []);
called_party_bcd(#called_party_bcd{ton = TON, npi = NPI,
		address = Address}) ->
	called_party_bcd2(Address, <<0:1, TON:3, NPI:4>>).
%% @hidden
called_party_bcd1(<<15:4, A:4>>, CP, Acc) ->
	CP#called_party_bcd{address = lists:reverse([A | Acc])};
called_party_bcd1(<<A2:4, A1:4>>, CP, Acc) ->
	CP#called_party_bcd{address = lists:reverse([A2, A1 | Acc])};
called_party_bcd1(<<A2:4, A1:4, Rest/binary>>, CP, Acc) ->
	called_party_bcd1(Rest, CP, [A2, A1 | Acc]).
%% @hidden
called_party_bcd2([A1, A2 | T], Acc) ->
	called_party_bcd2(T, <<Acc/binary, A2:4, A1:4>>);
called_party_bcd2([A], Acc) ->
	<<Acc/binary, 15:4, A:4>>;
called_party_bcd2([], Acc) ->
	Acc.

-spec isdn_address(Address) -> Address
	when
		Address :: isdn_address() | binary().
%% @doc CODEC for MAP ISDN-AddressString.
isdn_address(<<1:1, NAI:3, NPI:4, Address/binary>> = _Address) ->
	#isdn_address{nai = NAI, npi = NPI, address = tbcd(Address)};
isdn_address(#isdn_address{nai = NAI, npi = NPI, address = Address}) ->
	TBCD = tbcd(Address),
	<<1:1, NAI:3, NPI:4, TBCD/binary>>.

-spec tbcd(Digits) -> Digits
	when
		Digits :: [Digit] | binary(),
		Digit :: $0..$9 | $* | $# | $a | $b | $c.
%% @doc CODEC for TBCD-String.
%%
%% 	The Telephony Binary Coded Decimal String (TBCD)
%% 	type is used to store dialing digits in a compact
%% 	form. Digits are "0123456789*#abc"..
tbcd(Digits) when is_binary(Digits) ->
	tbcd(Digits, []);
tbcd(Digits) when is_list(Digits) ->
	tbcd(Digits, <<>>).
%% @hidden
tbcd(<<15:4, A:4>>, Acc) ->
	lists:reverse([digit(A) | Acc]);
tbcd(<<A2:4, A1:4, Rest/binary>>, Acc)
		when A1 >= 0, A1 < 15, A2 >= 0, A2 < 15 ->
	tbcd(Rest, [digit(A2), digit(A1) | Acc]);
tbcd(<<>>, Acc) ->
	lists:reverse(Acc);
tbcd([A], Acc) when ((A >= $0) and (A =< $9)) or (A == $*)
		or (A == $#) or ((A >= $a) and (A =<$c)) ->
	B = digit(A),
	<<Acc/binary, 15:4, B:4>>;
tbcd([A2, A1 | T], Acc)
		when (((A1 >= $0) or (A1 =< $9)) or (A1 == $*)
		or (A1 == $#) or ((A1 >= $a) and (A1 =<$c))),
		(((A2 >= $0) and (A2 =< $9)) or (A2 == $*)
		or (A2 == $#) or ((A2 >= $a) and (A2 =<$c))) ->
	B1 = digit(A1),
	B2 = digit(A2),
	tbcd(T, <<Acc/binary, B1:4, B2:4>>);
tbcd([], Acc) ->
	Acc.

-spec generic_number(GenericNumber) -> GenericNumber
	when
		GenericNumber :: generic_number() | binary().
%% @doc CODEC for ISUP Generic Number IE.
generic_number(<<NQI:8, OE:1, NAI:7, NI:1, NPI:3, APRI:2, SI:2,
		Address/binary>> = _GenericNumber) ->
	generic_number1(OE, Address, #generic_number{nqi = NQI,
			nai = NAI, ni = NI, npi = NPI, apri = APRI, si = SI}, []);
generic_number(#generic_number{nqi = NQI, nai = NAI, ni = NI,
		npi = NPI, apri = APRI, si = SI, address = Address}) ->
	OE = length(Address) rem 2,
	generic_number2(Address,
			<<NQI:8, OE:1, NAI:7, NI:1, NPI:3, APRI:2, SI:2>>).
%% @hidden
generic_number1(0, <<A2:4, A1:4>>, GN, Acc) ->
	GN#generic_number{address = lists:reverse([A2, A1 | Acc])};
generic_number1(1, <<_:4, A:4>>, GN, Acc) ->
	GN#generic_number{address = lists:reverse([A | Acc])};
generic_number1(OE, <<A2:4, A1:4, Rest/binary>>, GN, Acc) ->
	generic_number1(OE, Rest, GN, [A2, A1 | Acc]).
%% @hidden
generic_number2([A1, A2 | T], Acc) ->
	generic_number2(T, <<Acc/binary, A2:4, A1:4>>);
generic_number2([A], Acc) ->
	<<Acc/binary, 0:4, A:4>>;
generic_number2([], Acc) ->
	Acc.

-spec generic_digits(GenericDigits) -> GenericDigits
	when
		GenericDigits :: generic_digits() | binary().
%% @doc CODEC for ISUP Generic Digits IE.
generic_digits(<<ENC:3, TOD:5, Digits/binary>> = _GenericDigits) ->
	#generic_digits{enc = ENC, tod = TOD, digits = Digits};
generic_digits(#generic_digits{enc = ENC, tod = TOD, digits = Digits})
		when is_binary(Digits) ->
	<<ENC:3, TOD:5, Digits/binary>>.

-spec date_time(DateAndTime) -> DateAndTime
	when
		DateAndTime :: binary() | calendar:datetime().
%% @doc CODEC for CAMEL DateAndTime.
date_time(<<Y2:4, Y1:4, Y4:4, Y3:4, M2:4, M1:4, D2:4, D1:4,
		H2:4, H1:4, Min2:4, Min1:4, S2:4, S1:4>> = _DateAndTime) ->
	Year = (Y1 * 1000) + (Y2 * 100) + (Y3 * 10) + Y4,
	Month = (M1 * 10) + M2,
	Day = (D1 * 10) + D2,
	Hour = (H1 * 10) + H2,
	Minute = (Min1 * 10) + Min2,
	Second = (S1 * 10) + S2,
	{{Year, Month, Day}, {Hour, Minute, Second}};
date_time(DateAndTime) when byte_size(DateAndTime) == 6 ->
	date_time(<<0:4, 2:4, DateAndTime/binary>>);
date_time({{Year, Month, Day}, {Hour, Minute, Second}}) ->
	Y1 = Year div 1000,
	Y2 = (Year div 100) - (Y1 * 10),
	Y3 = (Year div 10) - (Y1 * 100) - (Y2 * 10),
	Y4 = Year - (Y1 * 1000) - (Y2 * 100) - (Y3 * 10),
	M1 = Month div 10,
	M2 = Month - (M1 * 10),
	D1 = Day div 10,
	D2 = Day - (D1 * 10),
	H1 = Hour div 10,
	H2 = Hour - (H1 * 10),
	Min1 = Minute div 10,
	Min2 = Minute - (Min1 * 10),
	S1 = Second div 10,
	S2 = Second - (S1 * 10),
	<<Y2:4, Y1:4, Y4:4, Y3:4, M2:4, M1:4, D2:4, D1:4,
		H2:4, H1:4, Min2:4, Min1:4, S2:4, S1:4>>.
	
-ifdef(CAP).
-spec error_code(ErrorCode) -> ErrorName
	when
		ErrorCode :: {local, integer()} | {global, tuple()},
		ErrorName :: atom() | tuple().
%% @doc Returns the name for an error code.
error_code({global, OID}) ->
	OID;
error_code(?'errcode-canceled') ->
	canceled;
error_code(?'errcode-cancelFailed') ->
	cancelFailed;
error_code(?'errcode-eTCFailed') ->
	eTCFailed;
error_code(?'errcode-improperCallerResponse') ->
	improperCallerResponse;
error_code(?'errcode-missingCustomerRecord') ->
	missingCustomerRecord;
error_code(?'errcode-missingParameter') ->
	missingParameter;
error_code(?'errcode-parameterOutOfRange') ->
	parameterOutOfRange;
error_code(?'errcode-requestedInfoError') ->
	requestedInfoError;
error_code(?'errcode-systemFailure') ->
	systemFailure;
error_code(?'errcode-taskRefused') ->
	taskRefused;
error_code(?'errcode-unavailableResource') ->
	unavailableResource;
error_code(?'errcode-unexpectedComponentSequence') ->
	unexpectedComponentSequence;
error_code(?'errcode-unexpectedDataValue') ->
	unexpectedDataValue;
error_code(?'errcode-unexpectedParameter') ->
	unexpectedParameter;
error_code(?'errcode-unknownLegID') ->
	unknownLegID;
error_code(?'errcode-unknownPDPID') ->
	unknownPDPID;
error_code(?'errcode-unknownCSID') ->
	unknownCSID.
-endif.

-spec cause(Cause) -> Cause
	when
		Cause :: cause() | binary().
%% @doc CODEC for ISUP Cause.
cause(<<1:1, Coding:2, 0:1, Location:4, 1:1, Value:7>>) ->
	cause(Coding, Location, #cause{value = Value});
cause(<<1:1, Coding:2, 0:1, Location:4, 1:1, Value:7,
		Diagnostics/binary>>) ->
	cause(Coding, Location,
			#cause{value = Value, diagnostic = Diagnostics});
cause(#cause{coding = Coding, location = Location,
		value = Value, diagnostic = undefined})
		when Value > 0, Value < 128 ->
	cause1(Coding, Location, <<1:1, Value:7>>);
cause(#cause{coding = Coding, location = Location,
		value = Value, diagnostic = Diagnostics})
		when Value > 0, Value < 128, is_binary(Diagnostics) ->
	cause1(Coding, Location, <<1:1, Value:7, Diagnostics/binary>>).
%% @hidden
cause(0, Location, Acc) ->
	cause(Location, Acc#cause{coding = itu});
cause(1, Location, Acc) ->
	cause(Location, Acc#cause{coding = iso});
cause(2, Location, Acc) ->
	cause(Location, Acc#cause{coding = national});
cause(3, Location, Acc) ->
	cause(Location, Acc#cause{coding = other}).
%% @hidden
cause(0, Acc) ->
	Acc#cause{location = user};
cause(1, Acc) ->
	Acc#cause{location = local_private};
cause(2, Acc) ->
	Acc#cause{location = local_public};
cause(3, Acc) ->
	Acc#cause{location = transit};
cause(4, Acc) ->
	Acc#cause{location = remote_public};
cause(5, Acc) ->
	Acc#cause{location = remote_private};
cause(7, Acc) ->
	Acc#cause{location = international};
cause(10, Acc) ->
	Acc#cause{location = beyond}.
%% @hidden
cause1(itu, Location, Acc) ->
	cause2(0, Location, Acc);
cause1(iso, Location, Acc) ->
	cause2(1, Location, Acc);
cause1(national, Location, Acc) ->
	cause2(2, Location, Acc);
cause1(other, Location, Acc) ->
	cause2(3, Location, Acc).
%% @hidden
cause2(Coding, user, Acc) ->
	<<1:1, Coding:2, 0:1, 0:4, Acc/binary>>;
cause2(Coding, local_private, Acc) ->
	<<1:1, Coding:2, 0:1, 1:4, Acc/binary>>;
cause2(Coding, local_public, Acc) ->
	<<1:1, Coding:2, 0:1, 2:4, Acc/binary>>;
cause2(Coding, transit, Acc) ->
	<<1:1, Coding:2, 0:1, 3:4, Acc/binary>>;
cause2(Coding, remote_public, Acc) ->
	<<1:1, Coding:2, 0:1, 4:4, Acc/binary>>;
cause2(Coding, remote_private, Acc) ->
	<<1:1, Coding:2, 0:1, 5:4, Acc/binary>>;
cause2(Coding, international, Acc) ->
	<<1:1, Coding:2, 0:1, 7:4, Acc/binary>>;
cause2(Coding, beyond, Acc) ->
	<<1:1, Coding:2, 0:1, 10:4, Acc/binary>>.

-spec ims_uri(URIString) -> Result
	when
		URIString :: uri_string:uri_string(),
		Result :: ims_uri() | {error, Reason},
		Reason :: term().
%% @doc Parse an IMS address.
%%
%% 	An IP Multimedia Subsystem (IMS) address is provided
%% 	as a SIP URI (RFC3261) or a Tel URI (RFC3966).
%%
ims_uri(URIString)
		when is_list(URIString); is_binary(URIString)  ->
	ims_uri1(uri_string:parse(URIString)).
%% @hidden
ims_uri1(#{scheme := "tel", path := Path}) ->
	[Subscriber | Params] = string:lexemes(Path, [$;]),
	#ims_uri{scheme = tel, user = Subscriber,
			user_params = params(Params)};
ims_uri1(#{scheme := <<"tel">>, path := Path}) ->
	[Subscriber | Params] = string:lexemes(Path, [$;]),
	#ims_uri{scheme = tel, user = Subscriber,
			user_params = params(Params)};
ims_uri1(#{scheme := "sip", path := Path}) ->
	ims_uri2(Path, #ims_uri{scheme = sip});
ims_uri1(#{scheme := <<"sip">>, path := Path}) ->
	ims_uri2(Path, #ims_uri{scheme = sip});
ims_uri1(#{scheme := "sips", path := Path}) ->
	ims_uri2(Path, #ims_uri{scheme = sips});
ims_uri1(#{scheme := <<"sips">>, path := Path}) ->
	ims_uri2(Path, #ims_uri{scheme = sips});
ims_uri1({error, Reason, _}) ->
	{error, Reason}.
%% @hidden
ims_uri2(Path, Acc) ->
	ims_uri3(string:split(Path, [$@]), Acc).
%% @hidden
ims_uri3([Rest], Acc) ->
	ims_uri4(Rest, Acc);
ims_uri3([User, Rest], Acc) ->
	[Subscriber | Params] = string:lexemes(User, [$;]),
	NewAcc = Acc#ims_uri{user = Subscriber, user_params = params(Params)},
	ims_uri4(Rest, NewAcc);
ims_uri3([[]], Acc) ->
	Acc.
%% @hidden
ims_uri4(Rest, Acc) ->
	[Host | Params] = string:lexemes(Rest, [$;]),
	NewAcc = Acc#ims_uri{uri_params = params(Params)},
	ims_uri5(string:split(Host, [$:]), NewAcc).
%% @hidden
ims_uri5([Host], Acc) ->
	Acc#ims_uri{host = Host};
ims_uri5([Host, Port], Acc) when is_list(Port) ->
	Acc#ims_uri{host = Host, port = list_to_integer(Port)};
ims_uri5([Host, Port], Acc) when is_binary(Port) ->
	Acc#ims_uri{host = Host, port = binary_to_integer(Port)};
ims_uri5([[]], Acc) ->
	Acc.

-spec rat_type(RatType) -> string()
	when
		RatType :: binary().
%% @doc Decode a `3GPP-RAT-Type' value.
%%
%% 	Identifies a type of Radio Access Technology (RAT).
%%
%% 	See: 3GPP TS 29.061
%%
rat_type(<<1>> = _RatType) ->
	"UTRAN";
rat_type(<<2>>) ->
	"GERAN";
rat_type(<<3>>) ->
	"WLAN";
rat_type(<<4>>) ->
	"GAN";
rat_type(<<5>>) ->
	"HSPA-evolution";
rat_type(<<6>>) ->
	"EUTRAN";
rat_type(<<7>>) ->
	"VIRTUAL";
rat_type(<<8>>) ->
	"EUTRAN-NB-IoT";
rat_type(<<9>>) ->
	"LTE-M";
rat_type(<<10>>) ->
	"NR";
rat_type(<<51>>) ->
	"NR";
rat_type(<<52>>) ->
	"NR-unlicensed";
rat_type(<<53>>) ->
	"Trusted-WLAN";
rat_type(<<54>>) ->
	"Trusted-non3GPP";
rat_type(<<55>>) ->
	"Wireline";
rat_type(<<56>>) ->
	"Wireline-cable";
rat_type(<<57>>) ->
	"Wireline-BBF";
rat_type(<<101>>) ->
	"IEEE-802.16e";
rat_type(<<102>>) ->
	"3GPP2-eHRPD";
rat_type(<<103>>) ->
	"3GPP2-HRPD";
rat_type(<<104>>) ->
	"3GPP2-1xRTT";
rat_type(<<105>>) ->
	"3GPP2-UMB";
rat_type(Other) when is_binary(Other) ->
	integer_to_list(binary_to_integer(Other)).

-spec redirect_info(RedirectionInformation) -> RedirectionInformation
	when
		RedirectionInformation :: binary() | redirect_info().
%% @doc CODEC for ISUP Redirection information.
redirect_info(<<Orig:4, _:1, Ind:3>> = _RedirectionInformation) ->
	#redirect_info{indicator = Ind,
			orig_reason = Orig,
			reason = 0,
			counter = 0};
redirect_info(<<Orig:4, _:1, Ind:3, Reason:4, _:1, Count:3>>) ->
	#redirect_info{indicator = Ind,
			orig_reason = Orig,
			reason = Reason,
			counter = Count};
redirect_info(#redirect_info{indicator = Ind,
		orig_reason = Orig, reason = Reason, counter = Count}) ->
	<<Orig:4, 0:1, Ind:3, Reason:4, 0:1, Count:3>>.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec params(ParamList) -> Params
	when
		ParamList :: [Parameter],
		Parameter :: string() | binary(),
		Params :: map().
%% @doc Create `map()' from parsed parameter list.
%% @hidden
params(ParamList) ->
	params(ParamList, #{}).
%% @hidden
params([H | T], Acc) ->
	case string:lexemes(H, [$=]) of
		[Param] ->
			params(T, Acc#{Param => true});
		[Param, Value] ->
			params(T, Acc#{Param => Value})
	end;
params([], Acc) ->
	Acc.

-spec digit(Digit) -> Digit
	when
		Digit :: 0..14 | $0..$9 | $* | $# | $a..$c.
%% @doc Convert between integer and ASCII digit.
%% @hidden
digit(0) ->
	$0;
digit($0) ->
	0;
digit(1) ->
	$1;
digit($1) ->
	1;
digit(2) ->
	$2;
digit($2) ->
	2;
digit(3) ->
	$3;
digit($3) ->
	3;
digit(4) ->
	$4;
digit($4) ->
	4;
digit(5) ->
	$5;
digit($5) ->
	5;
digit(6) ->
	$6;
digit($6) ->
	6;
digit(7) ->
	$7;
digit($7) ->
	7;
digit(8) ->
	$8;
digit($8) ->
	8;
digit(9) ->
	$9;
digit($9) ->
	9;
digit(10) ->
	$*;
digit($*) ->
	10;
digit(11) ->
	$#;
digit($#) ->
	11;
digit(12) ->
	$a;
digit($a) ->
	12;
digit(13) ->
	$b;
digit($b) ->
	13;
digit(14) ->
	$c;
digit($c) ->
	14.

