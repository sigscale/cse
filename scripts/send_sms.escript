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
			send_sms(Options)
	end.

send_sms(Options) ->
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
		IMSI = #'3gpp_ro_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
				'Subscription-Id-Data' = maps:get(imsi, Options, "001001123456789")},
		MSISDNr = #'3gpp_ro_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
				'Subscription-Id-Data' = MSISDN},
		SubscriptionId = [IMSI, MSISDNr],
		USU = #'3gpp_ro_Used-Service-Unit'{'CC-Service-Specific-Units' = [1]},
		MSCC = #'3gpp_ro_Multiple-Services-Credit-Control'{
				'Used-Service-Unit' = [USU]},
		PS = #'3gpp_ro_PS-Information'{'3GPP-SGSN-MCC-MNC' = ["001001"]},
		SMS = #'3gpp_ro_SMS-Information'{
				'Recipient-Info' = [#'3gpp_ro_Recipient-Info'{
				'Recipient-Address' = [#'3gpp_ro_Recipient-Address'{
				'Address-Type' = [?'3GPP_RO_ADDRESS-TYPE_MSISDN'],
				'Address-Data' = [maps:get(dest, Options, "14165556789")]}]}]},
		ServiceInformation = #'3gpp_ro_Service-Information'{
				'PS-Information' = [PS],
				'SMS-Information' = [SMS]},
		CCR = #'3gpp_ro_CCR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Realm' = OriginRealm,
				'Auth-Application-Id' = ?RO_APPLICATION_ID,
				'Service-Context-Id' = maps:get(context, Options, "32274@3gpp.org"),
				'User-Name' = [MSISDN],
				'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_EVENT_REQUEST',
				'CC-Request-Number' = 0,
				'Requested-Action' = [?'3GPP_RO_REQUESTED-ACTION_DIRECT_DEBITING'],
				'Multiple-Services-Indicator' = [1],
				'Multiple-Services-Credit-Control' = [MSCC],
				'Event-Timestamp' = [calendar:universal_time()],
				'Subscription-Id' = SubscriptionId,
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
	Option1 = " [--context 32274@3gpp.org]",
	Option2 = " [--msisdn 14165551234]",
	Option3 = " [--imsi 001001123456789]",
	Option4 = " [--ip 127.0.0.1]",
	Option5 = " [--raddr 127.0.0.1]",
	Option6 = " [--rport 3868]",
	Option7 = " [--recipient 14165556789]",
	Options = [Option1, Option2, Option3, Option4, Option5, Option6, Option7],
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
options(["--ip", Address | T], Acc) ->
	{ok, IP} = inet:parse_address(Address),
	options(T, Acc#{ip => IP});
options(["--raddr", Address | T], Acc) ->
	{ok, IP} = inet:parse_address(Address),
	options(T, Acc#{raddr => IP});
options(["--rport", Port | T], Acc) ->
	options(T, Acc#{rport => list_to_integer(Port)});
options(["--recipient", Destination | T], Acc) ->
	options(T, Acc#{dest => Destination});
options([_H | _T], _Acc) ->
	usage();
options([], Acc) ->
	Acc.

