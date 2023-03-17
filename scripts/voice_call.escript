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
			voice_call(Options)
	end.

voice_call(Options) ->
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
		IMSI = #'3gpp_ro_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_IMSI',
				'Subscription-Id-Data' = maps:get(imsi, Options, "001001123456789")},
		MSISDN = #'3gpp_ro_Subscription-Id'{
				'Subscription-Id-Type' = ?'3GPP_SUBSCRIPTION-ID-TYPE_END_USER_E164',
				'Subscription-Id-Data' = maps:get(msisdn, Options, "14165551234")},
		SubscriptionId = [IMSI, MSISDN],
		RSU1 = #'3gpp_ro_Requested-Service-Unit'{},
		MSCC1 = #'3gpp_ro_Multiple-Services-Credit-Control'{
				'Requested-Service-Unit' = [RSU1]},
		CallingParty = maps:get(orig, Options, "14165551234"), 
		CalledParty = maps:get(dest, Options, "14165556789"),
		CallingPartyAddress = "tel:+" ++ CallingParty,
		CalledPartyAddress = "tel:+" ++ CalledParty,
		ServiceInformation = #'3gpp_ro_Service-Information'{
				'IMS-Information' = [#'3gpp_ro_IMS-Information'{
						'Node-Functionality' = ?'3GPP_RO_NODE-FUNCTIONALITY_AS',
						'Role-Of-Node' = [?'3GPP_RO_ROLE-OF-NODE_ORIGINATING_ROLE'],
						'Calling-Party-Address' = [CallingPartyAddress],
						'Called-Party-Address' = [CalledPartyAddress]}]},
		RequestNum1 = 0,
		CCR1 = #'3gpp_ro_CCR'{'Session-Id' = SId,
				'Origin-Host' = Hostname,
				'Origin-Realm' = OriginRealm,
				'Destination-Realm' = OriginRealm,
				'Auth-Application-Id' = ?RO_APPLICATION_ID,
				'Service-Context-Id' = "32260@3gpp.org",
				'User-Name' = [list_to_binary(CallingParty)],
				'CC-Request-Type' = ?'3GPP_RO_CC-REQUEST-TYPE_INITIAL_REQUEST',
				'CC-Request-Number' = RequestNum1,
				'Event-Timestamp' = [calendar:universal_time()],
				'Subscription-Id' = SubscriptionId,
				'Multiple-Services-Credit-Control' = [MSCC1],
				'Service-Information' = [ServiceInformation]},
		Fro = fun('3gpp_ro_CCA', _N) ->
					record_info(fields, '3gpp_ro_CCA');
				('3gpp_ro_Multiple-Services-Credit-Control', _N) ->
					record_info(fields, '3gpp_ro_Multiple-Services-Credit-Control')
		end,
		Fbase = fun('diameter_base_answer-message', _N) ->
					record_info(fields, 'diameter_base_answer-message')
		end,
		case diameter:call(Name, ro, CCR1, []) of
			#'3gpp_ro_CCA'{} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fro)]);
			#'diameter_base_answer-message'{} = Answer1 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer1, Fbase)]);
			{error, Reason1} ->
				throw(Reason1)
		end,
		timer:sleep(maps:get(interval, Options, 1000)),
		Fupdate = fun F(0, ReqNum) ->
					ReqNum;
				F(N, ReqNum) ->
					NewReqNum = ReqNum + 1,
					UsedUnits1 = rand:uniform(3500) + 100,
					USU1 = #'3gpp_ro_Used-Service-Unit'{'CC-Time' = [UsedUnits1]},
					MSCC2 = #'3gpp_ro_Multiple-Services-Credit-Control'{
							'Used-Service-Unit' = [USU1]},
					CCR2 = CCR1#'3gpp_ro_CCR'{'Session-Id' = SId,
							'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_UPDATE_REQUEST',
							'CC-Request-Number' = NewReqNum,
							'Multiple-Services-Credit-Control' = [MSCC2],
							'Event-Timestamp' = [calendar:universal_time()]},
					case diameter:call(Name, ro, CCR2, []) of
						#'3gpp_ro_CCA'{} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fro)]);
						#'diameter_base_answer-message'{} = Answer2 ->
							io:fwrite("~s~n", [io_lib_pretty:print(Answer2, Fbase)]);
						{error, Reason2} ->
							throw(Reason2)
					end,
					timer:sleep(maps:get(interval, Options, 1000)),
					F(N - 1, NewReqNum)
		end,
		RequestNum2 = Fupdate(maps:get(updates, Options, 1), RequestNum1),
		UsedUnits2 = rand:uniform(3500) + 100,
		USU2 = #'3gpp_ro_Used-Service-Unit'{'CC-Time' = [UsedUnits2]},
		MSCC3 = #'3gpp_ro_Multiple-Services-Credit-Control'{
				'Used-Service-Unit' = [USU2]},
		CCR3 = CCR1#'3gpp_ro_CCR'{'Session-Id' = SId,
				'CC-Request-Type' = ?'3GPP_CC-REQUEST-TYPE_TERMINATION_REQUEST',
				'CC-Request-Number' = RequestNum2,
				'Multiple-Services-Credit-Control' = [MSCC3],
				'Event-Timestamp' = [calendar:universal_time()]},
		case diameter:call(Name, ro, CCR3, []) of
			#'3gpp_ro_CCA'{} = Answer3 ->
				io:fwrite("~s~n", [io_lib_pretty:print(Answer3, Fro)]);
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
	Option1 = " [--msisdn 14165551234]",
	Option2 = " [--imsi 001001123456789]",
	Option3 = " [--interval 1000]",
	Option4 = " [--updates 1]",
	Option5 = " [--ip 127.0.0.1]",
	Option6 = " [--raddr 127.0.0.1]",
	Option7 = " [--rport 3868]",
	Option8 = " [--origin 14165551234]",
	Option9 = " [--destination 14165556789]",
	Options = [Option1, Option2, Option3, Option4, Option5,
			Option6, Option7, Option8, Option9],
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

