#!/usr/bin/env escript
%% vim: syntax=erlang

-mode(compile).

-export([handle_request/3]).

-include_lib("cse/include/diameter_gen_3gpp.hrl").
-include_lib("cse/include/diameter_gen_3gpp_sy_application.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-define(SY_APPLICATION_ID, 16777302).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

main(Args) ->
	case options(Args) of
		#{help := true} = _Options ->
			usage();
		Options ->
			sy_session(Options)
	end.

sy_session(Options) ->
	try
		Name = escript:script_name() ++ "-" ++ ref_to_list(make_ref()),
		ok = diameter:start(),
		Hostname = filename:rootname(filename:basename(Name), ".escript"),
		OriginRealm = case inet_db:res_option(domain) of
			Domain when length(Domain) > 0 ->
				Domain;
			_ ->
				"example.net"
		end,
		Callback = #diameter_callback{
				handle_request = {?MODULE, handle_request, []}},
		ServiceOptions = [{'Origin-Host', Hostname},
				{'Origin-Realm', OriginRealm},
				{'Vendor-Id', ?IANA_PEN_SigScale},
				{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
				{'Product-Name', "SigScale Test Script"},
				{'Auth-Application-Id', [?SY_APPLICATION_ID]},
				{string_decode, false},
				{restrict_connections, false},
				{application, [{dictionary, diameter_gen_base_rfc6733},
						{module, Callback}]},
				{application, [{alias, sy},
						{dictionary, diameter_gen_3gpp_sy_application},
						{module, Callback}]}],
		true = diameter:subscribe(Name),
		ok = diameter:start_service(Name, ServiceOptions),
		receive
			#diameter_event{service = Name, info = start} ->
				ok
		end,
		TransportOptions =  [{transport_module, diameter_tcp},
				{transport_config,
						[{raddr, maps:get(raddr, Options, {127,0,0,1})},
						{rport, maps:get(rport, Options, 3868)},
						{ip, maps:get(ip, Options, {127,0,0,1})}]}],
		{ok, _Ref} = diameter:add_transport(Name, {connect, TransportOptions}),
		receive
			#diameter_event{service = Name, info = Info}
					when element(1, Info) == up ->
				ok
		end,
		SId = diameter:session_id(Hostname),
		IMSI = #'3gpp_sy_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
				'Subscription-Id-Data' = maps:get(imsi, Options, "001001123456789")},
		MSISDN = #'3gpp_sy_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
				'Subscription-Id-Data' = maps:get(msisdn, Options, "14165551234")},
		SubscriptionId = [IMSI, MSISDN],
		PCI = string:lexemes(maps:get(pci, Options, []), [$,]),
		SupportedFeatures = #'3gpp_sy_Supported-Features'{
				'Vendor-Id' = ?IANA_PEN_3GPP,
				'Feature-List-ID' = 1,
				'Feature-List' = 1},
		SLR1 = #'3gpp_sy_SLR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Realm' = OriginRealm,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'SL-Request-Type' = ?'3GPP_SY_SL-REQUEST-TYPE_INITIAL_REQUEST',
				'Subscription-Id' = SubscriptionId,
				'Supported-Features' = [SupportedFeatures],
				'Policy-Counter-Identifier' = PCI},
		Fsy = fun('3gpp_sy_SLA', _N) ->
					record_info(fields, '3gpp_sy_SLA');
				('3gpp_sy_Experimental-Result', _N) ->
					record_info(fields, '3gpp_sy_Experimental-Result');
				('3gpp_sy_Policy-Counter-Status-Report', _N) ->
					record_info(fields, '3gpp_sy_Policy-Counter-Status-Report');
				('3gpp_sy_Pending-Policy-Counter-Information', _N) ->
					record_info(fields, '3gpp_sy_Pending-Policy-Counter-Information');
				('3gpp_sy_STA', _N) ->
					record_info(fields, '3gpp_sy_STA')
		end,
		Fbase = fun('diameter_base_answer-message', _N) ->
					record_info(fields, 'diameter_base_answer-message');
				('diameter_base_Failed-AVP', _N) ->
					record_info(fields, 'diameter_base_Failed-AVP');
				('diameter_base_Experimental-Result', _N) ->
					record_info(fields, 'diameter_base_Experimental-Result');
				('diameter_base_Vendor-Specific-Application-Id', _N) ->
					record_info(fields, 'diameter_base_Vendor-Specific-Application-Id');
				('diameter_base_Proxy-Info', _N) ->
					record_info(fields, 'diameter_base_Proxy-Info')
		end,
		case diameter:call(Name, sy, SLR1, []) of
			#'3gpp_sy_SLA'{'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fsy)]);
			#'3gpp_sy_SLA'{'Result-Code' = [ResultCode1]} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fsy)]),
				throw(ResultCode1);
			#'3gpp_sy_SLA'{'Experimental-Result' = [ResultCode1]} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fsy)]),
				throw(ResultCode1);
			#'diameter_base_answer-message'{'Result-Code' = ResultCode1} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fbase)]),
				throw(ResultCode1);
			{error, Reason1} ->
				error(Reason1)
		end,
		true = register(?MODULE, self()),
		Interval = maps:get(interval, Options, 1000),
		Updates = receive
			snr_asr ->
				0
		after
			Interval ->
				maps:get(updates, Options, 0)
		end,
		Fupdate = fun F(0) ->
					ok;
				F(N) ->
					SLR2 = SLR1#'3gpp_sy_SLR'{'Session-Id' = SId,
							'Supported-Features' = [],
							'SL-Request-Type' = ?'3GPP_SY_SL-REQUEST-TYPE_INTERMEDIATE_REQUEST'},
					case diameter:call(Name, sy, SLR2, []) of
						#'3gpp_sy_SLA'{'Result-Code' = [?'DIAMETER_BASE_RESULT-CODE_SUCCESS']} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fsy)]);
						#'3gpp_sy_SLA'{'Result-Code' = [ResultCode2]} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fsy)]),
							throw(ResultCode2);
						#'3gpp_sy_SLA'{'Experimental-Result' = [ResultCode2]} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fsy)]),
							throw(ResultCode2);
						#'diameter_base_answer-message'{'Result-Code' = ResultCode2} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fbase)]),
							throw(ResultCode2);
						{error, Reason2} ->
							error(Reason2)
					end,
					receive
						snr_asr ->
							F(0)
					after
						Interval ->
							F(N - 1)
					end
		end,
		Fupdate(Updates),
		STR = #'3gpp_sy_STR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Host' = [],
				'Destination-Realm' = OriginRealm,
				'Auth-Application-Id' = ?SY_APPLICATION_ID,
				'Termination-Cause' = ?'DIAMETER_BASE_TERMINATION-CAUSE_LOGOUT'},
		case diameter:call(Name, sy, STR, []) of
			#'3gpp_sy_STA'{'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Fsy)]);
			#'3gpp_sy_STA'{'Result-Code' = ResultCode3} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Fsy)]),
				throw(ResultCode3);
			#'diameter_base_answer-message'{'Result-Code' = ResultCode3} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Fbase)]),
				throw(ResultCode3);
			{error, Reason3} ->
				error(Reason3)
		end
	catch
		throw:_Reason4 ->
			halt(1);
		error:Reason4 ->
			io:fwrite("~w: ~w~n", [error, Reason4]),
			halt(1);
		exit:Reason4 ->
			io:fwrite("~w: ~w~n", [error, Reason4]),
			usage()
	end.

handle_request(#diameter_packet{errors = [], msg = Request} = _Packet,
		_ServiceName, {_, Capabilities} = _Peer) ->
	#diameter_caps{origin_host = {Host, _},
			origin_realm = {Realm, _}} = Capabilities,
	Fsy = fun('3gpp_sy_SNR', _N) ->
				record_info(fields, '3gpp_sy_SNR');
			('3gpp_sy_Policy-Counter-Status-Report', _N) ->
				record_info(fields, '3gpp_sy_Policy-Counter-Status-Report');
			('3gpp_sy_Pending-Policy-Counter-Information', _N) ->
				record_info(fields, '3gpp_sy_Pending-Policy-Counter-Information')
	end,
	handle_request(Request, Host, Realm, Fsy).

handle_request(#'3gpp_sy_SNR'{'Session-Id' = Session,
				'SN-Request-Type' = [RequestType]} = Request,
		Host, Realm, Fsy) when (RequestType band 2#1) =:= 0 ->
	io:fwrite("~s~n", [io_lib_pretty:print(Request, Fsy)]),
	SNA = #'3gpp_sy_SNA'{'Session-Id' = Session,
			'Origin-Host' = Host,
			'Origin-Realm' = Realm,
			'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'},
	{reply, SNA};
handle_request(#'3gpp_sy_SNR'{'Session-Id' = Session,
				'SN-Request-Type' = [RequestType]} = Request,
		Host, Realm, Fsy) when (RequestType band 2#1) =:= 1 ->
	io:fwrite("~s~n", [io_lib_pretty:print(Request, Fsy)]),
	SNA = #'3gpp_sy_SNA'{'Session-Id' = Session,
			'Origin-Host' = Host,
			'Origin-Realm' = Realm,
			'Result-Code' = ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'},
	PostF = {erlang, send, [?MODULE, snr_asr]},
	{eval, {reply, SNA}, PostF}.

usage() ->
	Option1 = " [--msisdn 14165551234]",
	Option2 = " [--imsi 001001123456789]",
	Option3 = " [--policy-counter-id none]",
	Option4 = " [--updates 0]",
	Option5 = " [--interval 1000]",
	Option6 = " [--ip 127.0.0.1]",
	Option7 = " [--raddr 127.0.0.1]",
	Option8 = " [--rport 3868]",
	Options = [Option1, Option2, Option3, Option4, Option5,
			Option6, Option7, Option8],
	Format = lists:flatten(["usage: ~s", Options, "~n"]),
	io:fwrite(Format, [escript:script_name()]),
	halt(1).

options(Args) ->
	options(Args, #{}).
options(["--help" | T], Acc) ->
	options(T, Acc#{help => true});
options(["--imsi", IMSI | T], Acc) ->
	options(T, Acc#{imsi => IMSI});
options(["--msisdn", MSISDN | T], Acc) ->
	options(T, Acc#{msisdn => MSISDN});
options(["--policy-counter-id", PCI | T], Acc) ->
	options(T, Acc#{pci => PCI});
options(["--interval", MS | T], Acc) ->
	options(T, Acc#{interval => list_to_integer(MS)});
options(["--updates", N | T], Acc) ->
	options(T, Acc#{updates => list_to_integer(N)});
options(["--ip", Address | T], Acc) ->
	{ok, IP} = inet:parse_address(Address),
	options(T, Acc#{ip => IP});
options(["--raddr", Address | T], Acc) ->
	{ok, IP} = inet:parse_address(Address),
	options(T, Acc#{raddr => IP});
options(["--rport", Port | T], Acc) ->
	options(T, Acc#{rport=> list_to_integer(Port)});
options([_H | _T], _Acc) ->
	usage();
options([], Acc) ->
	Acc.

