#!/usr/bin/env escript
%% vim: syntax=erlang

-include_lib("cse/include/diameter_gen_3gpp.hrl").
-include_lib("cse/include/diameter_gen_3gpp_ro_application.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-define(RO_APPLICATION_ID, 4).
-define(IANA_PEN_3GPP, 10415).
-define(IANA_PEN_SigScale, 50386).

main(Args) ->
	case options(Args) of
		#{help := true} = _Options ->
			usage();
		Options ->
			send_mms(Options)
	end.

send_mms(Options) ->
	try
		Name = escript:script_name(),
		ok = diameter:start(),
		Hostname = erlang:ref_to_list(make_ref()),
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
				{'Auth-Application-Id', [?RO_APPLICATION_ID]},
				{string_decode, false},
				{restrict_connections, false},
				{application, [{dictionary, diameter_gen_base_rfc6733},
						{module, Callback}]},
				{application, [{alias, ro},
						{dictionary, diameter_gen_3gpp_ro_application},
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
		MSISDN = maps:get(msisdn, Options, "14165551234"),
		IMSIr = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
			'Subscription-Id-Data' = maps:get(imsi, Options, "001001123456789")},
		MSISDNr = #'3gpp_ro_Subscription-Id'{
			'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
			'Subscription-Id-Data' = MSISDN},
		SubscriptionId = [IMSIr, MSISDNr],
   	Originator = #'3gpp_ro_Originator-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
				'Address-Data' = [maps:get(orig, Options, "14165551234")]},
   	Recipient = #'3gpp_ro_Recipient-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
				'Address-Data' = [maps:get(dest, Options, "14165556789")]},
		MMS = #'3gpp_ro_MMS-Information'{
				'Message-Size' = [rand:uniform(1000)],
				'Originator-Address' = [Originator],
				'Recipient-Address' = [Recipient]},
		ServiceInformation = #'3gpp_ro_Service-Information'{'MMS-Information' = [MMS]},
		RSU = #'3gpp_ro_Requested-Service-Unit'{},
		MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
				'Requested-Service-Unit' = [RSU]},
		CCR = #'3gpp_ro_CCR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Realm' = OriginRealm,
				'Auth-Application-Id' = ?RO_APPLICATION_ID,
				'Service-Context-Id' = "32270@3gpp.org",
				'User-Name' = [MSISDN],
				'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_EVENT_REQUEST',
				'CC-Request-Number' = 0,
				'Event-Timestamp' = [calendar:universal_time()],
				'Subscription-Id' = SubscriptionId,
				'Requested-Action' = [?'3GPP_RO_REQUESTED-ACTION_DIRECT_DEBITING'],
				'Multiple-Services-Indicator' = [1],
				'Multiple-Services-Credit-Control' = [MSCC],
				'Service-Information' = [ServiceInformation]},
		Fro = fun('3gpp_ro_CCA', _N) ->
					record_info(fields, '3gpp_ro_CCA');
				('3gpp_ro_Multiple-Services-Credit-Control', _N) ->
					record_info(fields, '3gpp_ro_Multiple-Services-Credit-Control')
		end,
		Fbase = fun('diameter_base_answer-message', _N) ->
					record_info(fields, 'diameter_base_answer-message')
		end,
		case diameter:call(Name, ro, CCR, []) of
			#'3gpp_ro_CCA'{} = Answer ->
						io:fwrite("~s~n", [io_lib_pretty:print(Answer, Fro)]);
			#'diameter_base_answer-message'{} = Answer ->
						io:fwrite("~s~n", [io_lib_pretty:print(Answer, Fbase)]);
			{error, Reason} ->
						throw(Reason)
		end
	catch
		Error:Reason1 ->
			io:fwrite("~w: ~w~n", [Error, Reason1]),
			usage()
	end.

usage() ->
	Option1 = " [--msisdn 14165551234]",
	Option2 = " [--imsi 001001123456789]",
	Option3 = " [--ip 127.0.0.1]",
	Option4 = " [--raddr 127.0.0.1]",
	Option5 = " [--rport 3868]",
	Option6 = " [--origin 14165551234]",
	Option7 = " [--destination 14165556789]",
	Options = [Option1, Option2, Option3, Option4, Option5, Option6, Option7],
	Format = lists:flatten(["usage: ~s", Options, "~n"]),
	io:fwrite(Format, [escript:script_name()]),
	halt(1).

options(Args) ->
	options(Args, #{}).
options(["--help" | T], Acc) ->
	options(T, Acc#{help => true});
options(["--imsi", IMSI | T], Acc) ->
	options(T, Acc#{imsi=> IMSI});
options(["--msisdn", MSISDN | T], Acc) ->
	options(T, Acc#{msisdn => MSISDN});
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

