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
		date_time/1, error_code/1]).

-include("cse_codec.hrl").
-include_lib("cap/include/CAP-errorcodes.hrl").

-type called_party() :: #called_party{}.
-type called_party_bcd() :: #called_party_bcd{}.
-type calling_party() :: #calling_party{}.
-export_types([called_party/0, called_party_bcd/0, calling_party/0]).

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
error_code({local, ?'errcode-canceled'}) ->
	canceled;
error_code({local, ?'errcode-cancelFailed'}) ->
	cancelFailed;
error_code({local, ?'errcode-eTCFailed'}) ->
	eTCFailed;
error_code({local, ?'errcode-improperCallerResponse'}) ->
	improperCallerResponse;
error_code({local, ?'errcode-missingCustomerRecord'}) ->
	missingCustomerRecord;
error_code({local, ?'errcode-missingParameter'}) ->
	missingParameter;
error_code({local, ?'errcode-parameterOutOfRange'}) ->
	parameterOutOfRange;
error_code({local, ?'errcode-requestedInfoError'}) ->
	requestedInfoError;
error_code({local, ?'errcode-systemFailure'}) ->
	systemFailure;
error_code({local, ?'errcode-taskRefused'}) ->
	taskRefused;
error_code({local, ?'errcode-unavailableResource'}) ->
	unavailableResource;
error_code({local, ?'errcode-unexpectedComponentSequence'}) ->
	unexpectedComponentSequence;
error_code({local, ?'errcode-unexpectedDataValue'}) ->
	unexpectedDataValue;
error_code({local, ?'errcode-unexpectedParameter'}) ->
	unexpectedParameter;
error_code({local, ?'errcode-unknownLegID'}) ->
	unknownLegID;
error_code({local, ?'errcode-unknownPDPID'}) ->
	unknownPDPID;
error_code({local, ?'errcode-unknownCSID'}) ->
	unknownCSID.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

