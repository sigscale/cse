%%% cse_codec.erl
%%% vim: ts=3
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2021 SigScale Global Inc.
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
-copyright('Copyright (c) 2021 SigScale Global Inc.').
-author('Vance Shipley <vances@sigscale.org>').

%% export the cse_codec  public API
-export([called_party/1, calling_party/1, called_party_bcd/1,
		isdn_address/1, tbcd/1, date_time/1, error_code/1, cause/1]).

-include("cse_codec.hrl").
-include_lib("cap/include/CAP-errorcodes.hrl").

-type called_party() :: #called_party{}.
-type called_party_bcd() :: #called_party_bcd{}.
-type calling_party() :: #calling_party{}.
-type isdn_address() :: #isdn_address{}.
-export_types([called_party/0, called_party_bcd/0, calling_party/0,
		isdn_address/0]).

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

-spec cause(Cause) -> Cause
	when
		Cause :: #cause{} | binary().
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
cause(6, Acc) ->
	Acc#cause{location = international};
cause(7, Acc) ->
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
	<<1:1, Coding:2, 0:1, 6:4, Acc/binary>>;
cause2(Coding, beyond, Acc) ->
	<<1:1, Coding:2, 0:1, 7:4, Acc/binary>>.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

-spec digit(Digit) -> Digit
	when
		Digit :: 0..14 | $0..$9 | $* | $# | $a..$c.
%% @doc Convert between integer and ASCII digit.
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

