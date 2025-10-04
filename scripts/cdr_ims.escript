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
				{'Product-Name', "SigScale Test Script"},
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
		CallingParty = maps:get(orig, Options, "14165551234"), 
		CalledParty = maps:get(dest, Options, "14165556789"),
		CallingPartyAddress = "tel:+" ++ CallingParty,
		CalledPartyAddress = "tel:+" ++ CalledParty,
		PS = #'3gpp_rf_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
		IMS = #'3gpp_rf_IMS-Information'{
						'Node-Functionality' = ?'3GPP_RF_NODE-FUNCTIONALITY_AS',
						'Role-Of-Node' = [?'3GPP_RF_ROLE-OF-NODE_ORIGINATING_ROLE'],
						'Calling-Party-Address' = [CallingPartyAddress],
						'Called-Party-Address' = [CalledPartyAddress]},
		ServiceInformation = #'3gpp_rf_Service-Information'{
				'Subscription-Id' = SubscriptionId,
				'PS-Information' = [PS],
				'IMS-Information' = [IMS]},
		ACR1 = #'3gpp_rf_ACR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Realm' = OriginRealm,
				'Accounting-Record-Type' = ?'DIAMETER_BASE_ACCOUNTING-RECORD-TYPE_START_RECORD',
				'Accounting-Record-Number' = RecordNum0,
				'Acct-Application-Id' = [?RF_APPLICATION_ID],
				'Service-Context-Id' = [maps:get(context, Options, "32260@3gpp.org")],
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
			#'3gpp_rf_ACA'{'Result-Code' = 2001} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Frf)]);
			#'3gpp_rf_ACA'{'Result-Code' = ResultCode} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Frf)]),
				throw(ResultCode);
			#'diameter_base_answer-message'{'Result-Code' = ResultCode} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fbase)]),
				throw(ResultCode);
			{error, Reason1} ->
				error(Reason1)
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
						#'3gpp_rf_ACA'{'Result-Code' = 2001} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Frf)]);
						#'3gpp_rf_ACA'{'Result-Code' = ResultCode1} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Frf)]),
							throw(ResultCode1);
						#'diameter_base_answer-message'{'Result-Code' = ResultCode1} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fbase)]),
							throw(ResultCode1);
						{error, Reason2} ->
							error(Reason2)
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
			#'3gpp_rf_ACA'{'Result-Code' = 2001} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Frf)]);
			#'3gpp_rf_ACA'{'Result-Code' = ResultCode2} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Frf)]),
				throw(ResultCode2);
			#'diameter_base_answer-message'{'Result-Code' = ResultCode2} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Fbase)]),
				throw(ResultCode2);
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

usage() ->
	Option1 = " [--context 32260@3gpp.org]",
	Option2 = " [--msisdn 14165551234]",
	Option3 = " [--imsi 001001123456789]",
	Option4 = " [--interval 1000]",
	Option5 = " [--updates 1]",
	Option6 = " [--ip 127.0.0.1]",
	Option7 = " [--raddr 127.0.0.1]",
	Option8 = " [--rport 3868]",
	Option9 = " [--origin 14165551234]",
	Option10 = " [--destination 14165556789]",
	Options = [Option1, Option2, Option3, Option4, Option5,
			Option6, Option7, Option8, Option9, Option10],
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
	options(T, Acc#{imsi => IMSI});
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
	options(T, Acc#{rport => list_to_integer(Port)});
options(["--origin", Origin | T], Acc) ->
	options(T, Acc#{orig => Origin});
options(["--destination", Destination | T], Acc) ->
	options(T, Acc#{dest => Destination});
options([_H | _T], _Acc) ->
	usage();
options([], Acc) ->
	Acc.

