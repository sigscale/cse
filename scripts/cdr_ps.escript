#!/usr/bin/env escript
%% vim: syntax=erlang

-include_lib("cse/include/diameter_gen_3gpp.hrl").
-include_lib("cse/include/diameter_gen_3gpp_rf_application.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("diameter/include/diameter_gen_acct_rfc6733.hrl").
-define(RF_APPLICATION_ID, 3).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

main(Args) ->
	case options(Args) of
		#{help := true} = _Options ->
			usage();
		Options ->
			cdr_ps(Options)
	end.

cdr_ps(Options) ->
	try
		Name = escript:script_name(),
		ok = diameter:start(),
		Hostname = filename:rootname(filename:basename(Name), ".escript"),
		OriginRealm = case inet_db:res_option(domain) of
			Domain when length(Domain) > 0 ->
				Domain;
			_ ->
				"example.net"
		end,
		Callback = #diameter_callback{},
		ServiceOptions = [{'Origin-Host', Hostname},
				{'Origin-Realm', OriginRealm},
				{'Vendor-Id', ?IANA_PEN_SigScale},
				{'Supported-Vendor-Id', [?IANA_PEN_3GPP]},
				{'Product-Name', "SigScale CSE (test script)"},
				{'Acct-Application-Id', [?RF_APPLICATION_ID]},
				{string_decode, false},
				{restrict_connections, false},
				{application, [{dictionary, diameter_gen_base_rfc6733},
						{module, Callback}]},
				{application, [{alias, rf},
						{dictionary, diameter_gen_3gpp_rf_application},
						{module, Callback}]}],
		ok = diameter:start_service(Name, ServiceOptions),
		true = diameter:subscribe(Name),
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
		RecordNum0 = 0,
		IMSI = #'3gpp_rf_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
				'Subscription-Id-Data' = maps:get(imsi, Options, "001001123456789")},
		MSISDN = #'3gpp_rf_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
				'Subscription-Id-Data' = maps:get(msisdn, Options, "14165551234")},
		SubscriptionId = [IMSI, MSISDN],
		PS = #'3gpp_rf_PS-Information'{
				'3GPP-PDP-Type' = [3],
				'Serving-Node-Type' = [2],
				'SGSN-Address' = [{10,1,2,3}],
				'GGSN-Address' = [{10,4,5,6}],
				'3GPP-IMSI-MCC-MNC' = [<<"001001">>],
				'3GPP-GGSN-MCC-MNC' = [<<"001001">>],
				'3GPP-SGSN-MCC-MNC' = [<<"001001">>]},
		ServiceInformation = #'3gpp_rf_Service-Information'{
				'Subscription-Id' = SubscriptionId,
				'PS-Information' = [PS]},
		ACR1 = #'3gpp_rf_ACR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Realm' = OriginRealm,
				'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING-RECORD-TYPE_START_RECORD',
				'Accounting-Record-Number' = RecordNum0,
				'Acct-Application-Id' = [?RF_APPLICATION_ID],
				'Service-Context-Id' = [maps:get(context, Options, "32251@3gpp.org")],
				'User-Name' = [list_to_binary(Name)],
				'Event-Timestamp' = [calendar:universal_time()],
				'Service-Information' = [ServiceInformation]},
		Frf = fun('3gpp_rf_ACA', _N) ->
					record_info(fields, '3gpp_rf_ACA')
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
		case diameter:call(Name, rf, ACR1, []) of
			#'3gpp_rf_ACA'{} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Frf)]);
			#'diameter_base_answer-message'{} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fbase)]);
			{error, Reason1} ->
				throw(Reason1)
		end,
		timer:sleep(maps:get(interval, Options, 1000)),
		Fupdate = fun F(0, RecNum) ->
					RecNum;
				F(N, RecNum) ->
					NewRecNum = RecNum + 1,
					ACR2 = ACR1#'3gpp_rf_ACR'{'Session-Id' = SId,
							'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING-RECORD-TYPE_INTERIM_RECORD',
							'Accounting-Record-Number' = NewRecNum,
							'Event-Timestamp' = [calendar:universal_time()]},
					case diameter:call(Name, rf, ACR2, []) of
						#'3gpp_rf_ACA'{} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Frf)]);
						#'diameter_base_answer-message'{} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fbase)]);
						{error, Reason2} ->
							throw(Reason2)
					end,
					timer:sleep(maps:get(interval, Options, 1000)),
					F(N - 1, NewRecNum)
		end,
		RecordNum2 = Fupdate(maps:get(updates, Options, 1), RecordNum0) + 1,
		ACR3 = ACR1#'3gpp_rf_ACR'{'Session-Id' = SId,
				'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING-RECORD-TYPE_STOP_RECORD',
				'Accounting-Record-Number' = RecordNum2,
				'Event-Timestamp' = [calendar:universal_time()]},
		case diameter:call(Name, rf, ACR3, []) of
			#'3gpp_rf_ACA'{} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Frf)]);
			#'diameter_base_answer-message'{} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Fbase)]);
			{error, Reason3} ->
				throw(Reason3)
		end
	catch
		Error:Reason4 ->
			io:fwrite("~w: ~w~n", [Error, Reason4]),
			usage()
	end.

usage() ->
	Option1 = " [--context 32251@3gpp.org]",
	Option2 = " [--msisdn 14165551234]",
	Option3 = " [--imsi 001001123456789]",
	Option4 = " [--interval 1000]",
	Option5 = " [--updates 1]",
	Option6 = " [--ip 127.0.0.1]",
	Option7 = " [--raddr 127.0.0.1]",
	Option8 = " [--rport 3868]",
	Options = [Option1, Option2, Option3, Option4,
			Option5, Option6, Option7, Option8],
	Format = lists:flatten(["usage: ~s", Options, "~n"]),
	io:fwrite(Format, [escript:script_name()]),
	halt(1).

options(Args) ->
	options(Args, #{}).
options(["--help" | T], Acc) ->
	options(T, Acc#{help => true});
options(["--context", Context | T], Acc) ->
	options(T, Acc#{context => Context});
options(["--imsi", IMSI | T], Acc) ->
	options(T, Acc#{imsi=> IMSI});
options(["--msisdn", MSISDN | T], Acc) ->
	options(T, Acc#{msisdn => MSISDN});
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

