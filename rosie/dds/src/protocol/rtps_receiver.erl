% In one rtps application even with multiple participants, one receiver process should be enough.
% Each RTPS message may have multiple sub_messages destined to other entities or participants.
% for now i consider just one participant for each erlang node.
%
% In general the receiver could even be able to handle different domains.
-module(rtps_receiver).

-behaviour(gen_server).

-export([start_link/0, open_unicast_locators/2, get_local_locators/1,
         open_multicast_locators/2,stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

-record(state,
        {openedSockets = [],
         sourceVersion,
         sourceVendorId,
         sourceGuidPrefix,
         destGuidPrefix,
         unicastReplyLocatorList,
         multicastReplyLocatorList,
         haveTimestamp,
         timestamp}).

pl_to_discov_part_data(D, []) ->
    D;
pl_to_discov_part_data(D, [{status_info, S} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{status_qos = S}, TL);
pl_to_discov_part_data(D, [{user_data, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{user_data = V}, TL);
pl_to_discov_part_data(D, [{rtps_version, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{protocolVersion = V}, TL);
pl_to_discov_part_data(D, [{vendor_id, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{vendorId = V}, TL);
pl_to_discov_part_data(D, [{participant_lease, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{leaseDuration = V}, TL);
pl_to_discov_part_data(D, [{participant_guid, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{guidPrefix = V#guId.prefix}, TL);
pl_to_discov_part_data(D, [{builtin_endpoint_set, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{availableBuiltinEndpoints = V}, TL);
pl_to_discov_part_data(D, [{domain_id, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{domainId = V}, TL);
pl_to_discov_part_data(D, [{default_uni_locator, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{default_uni_locator_l =
                                                     D#spdp_disc_part_data.default_uni_locator_l
                                                     ++ [V]},
                           TL);
pl_to_discov_part_data(D, [{default_multi_locator, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{default_multi_locator_l =
                                                     D#spdp_disc_part_data.default_multi_locator_l
                                                     ++ [V]},
                           TL);
pl_to_discov_part_data(D, [{meta_uni_locator, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{meta_uni_locator_l =
                                                     D#spdp_disc_part_data.meta_uni_locator_l
                                                     ++ [V]},
                           TL);
pl_to_discov_part_data(D, [{meta_multi_locator, V} | TL]) ->
    pl_to_discov_part_data(D#spdp_disc_part_data{meta_multi_locator_l =
                                                     D#spdp_disc_part_data.meta_multi_locator_l
                                                     ++ [V]},
                           TL);
pl_to_discov_part_data(D, [_ | TL]) ->
    pl_to_discov_part_data(D, TL).

pl_to_discovered_participant_data(P_list) ->
    pl_to_discov_part_data(#spdp_disc_part_data{}, P_list).

pl_to_discov_endp_data(D, []) ->
    D;
pl_to_discov_endp_data(D, [{status_info, S} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{status_qos = S}, TL);
pl_to_discov_endp_data(D, [{rtps_version, V} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{protocolVersion = V}, TL);
pl_to_discov_endp_data(D, [{vendor_id, V} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{vendorId = V}, TL);
pl_to_discov_endp_data(D, [{topic_name, N} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{topic_name = N}, TL);
pl_to_discov_endp_data(D, [{topic_type, N} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{topic_type = N}, TL);
pl_to_discov_endp_data(D, [{durability_qos, Q} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{durability_qos = Q}, TL);
pl_to_discov_endp_data(D, [{history_qos, Q} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{history_qos = Q}, TL);
pl_to_discov_endp_data(D, [{reliability_qos, Q} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{reliability_qos = Q}, TL);
pl_to_discov_endp_data(D, [{endpoint_guid, GUID} | TL]) ->
    pl_to_discov_endp_data(D#sedp_disc_endpoint_data{endpointGuid = GUID}, TL);
pl_to_discov_endp_data(D, [_ | TL]) ->
    pl_to_discov_endp_data(D, TL).

pl_to_discovered_endpoint_data(P_list) ->
    pl_to_discov_endp_data(#sedp_disc_endpoint_data{}, P_list).

% Data is a Parameter list in little endian
handle_data({Reader, Writer, WriterSN, ?PL_CDR_LE, SerializedPayload})  % SPDP with data
    when Writer == ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER ->
    P_list = rtps_messages:parse_param_list(SerializedPayload),
    ParticipantData = pl_to_discovered_participant_data(P_list),
    {data, {Reader, Writer, WriterSN, ParticipantData}};
handle_data({Reader, Writer, WriterSN, ?PL_CDR_LE, SerializedPayload}) % SEDP with data
    when (Writer == ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_ANNOUNCER)
         or (Writer == ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER) ->
    P_list = rtps_messages:parse_param_list(SerializedPayload),
    EndpointData = pl_to_discovered_endpoint_data(P_list),
    {data, {Reader, Writer, WriterSN, EndpointData}};
handle_data({QOS_LIST, Reader, Writer, WriterSN,?PL_CDR_LE, SerializedPayload}) % SEDP with key and QOS
    when (Writer == ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_ANNOUNCER)
         or (Writer == ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER) ->
    P_list = rtps_messages:parse_param_list(SerializedPayload),
    EndpointData = pl_to_discovered_endpoint_data(P_list ++ QOS_LIST),
    {data, {Reader, Writer, WriterSN, EndpointData}};
handle_data({QOS_LIST, Reader, Writer,  WriterSN,  ?PL_CDR_LE, SerializedPayload}) % SPDP with key and QOS
    when Writer == ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER ->
    P_list = rtps_messages:parse_param_list(SerializedPayload),
    ParticipantData = pl_to_discovered_participant_data(P_list ++ QOS_LIST),
    {data, {Reader, Writer, WriterSN, ParticipantData}};
handle_data({QOS_LIST, Reader, Writer, WriterSN}) ->
    io:format("Data msg with only inline_qos not supported by implementaiton... \n"),
    not_managed;
% Data is user-defined binary in little endian
handle_data({Reader, Writer, WriterSN, ?CDR_LE, SerializedPayload}) ->
    {data, {Reader, Writer, WriterSN, SerializedPayload}};
% Inline-QOS for user data are ignored 
handle_data({_, Reader, Writer, WriterSN, ?CDR_LE, SerializedPayload}) ->
    {data, {Reader, Writer, WriterSN, SerializedPayload}};
handle_data(D) ->
    io:format("Data unknown or rappresentation not supported by implementation: ~p\n",[D]),
    not_managed.

handle_acknack(#state{sourceGuidPrefix = SRC, destGuidPrefix = DST},
               #acknack{writerGUID = #guId{entityId = WID}, readerGUID = #guId{entityId = RID}} =
                   A) ->
    {acknack,
     A#acknack{writerGUID = #guId{prefix = DST, entityId = WID},
               readerGUID = #guId{prefix = SRC, entityId = RID}}}.

handle_heartbeat(#state{sourceGuidPrefix = SRC, destGuidPrefix = DST},
                 #heartbeat{writerGUID = #guId{entityId = WID},
                            readerGUID = #guId{entityId = RID}} =
                     H) ->
    {heartbeat,
     H#heartbeat{writerGUID = #guId{prefix = SRC, entityId = WID},
                 readerGUID = #guId{prefix = DST, entityId = RID}}}.

handle_gap(#state{sourceGuidPrefix = SRC, destGuidPrefix = DST},
               #gap{writerGUID = #guId{entityId = WID}, readerGUID = #guId{entityId = RID}} = G) ->
    {gap,
     G#gap{writerGUID = #guId{prefix = SRC, entityId = WID},
               readerGUID = #guId{prefix = DST, entityId = RID}}}.

change_receiver_state_for(?SUB_MSG_KIND_INFO_TS, _, State) ->
    State;
change_receiver_state_for(?SUB_MSG_KIND_INFO_DST, _, State) ->
    State;
change_receiver_state_for(?SUB_MSG_KIND_INFO_REPLY, _, State) ->
    State;
change_receiver_state_for(?SUB_MSG_KIND_INFO_SRC, _, State) ->
    State;
change_receiver_state_for(_, _, State) ->
    State.

process_entity_sub_msg(?SUB_MSG_KIND_DATA, {Flags, Body}, _) ->
    handle_data(rtps_messages:parse_data(Flags, Body));
process_entity_sub_msg(?SUB_MSG_KIND_ACKNACK, {Flags, Body}, S) ->
    handle_acknack(S, rtps_messages:parse_acknack(Flags, Body));
process_entity_sub_msg(?SUB_MSG_KIND_HEARTBEAT, {Flags, Body}, S) ->
    handle_heartbeat(S, rtps_messages:parse_heartbeat(Flags, Body));
process_entity_sub_msg(?SUB_MSG_KIND_GAP, {Flags, Body}, S) ->
    handle_gap(S, rtps_messages:parse_gap(Flags, Body));
process_entity_sub_msg(?SUB_MSG_KIND_PAD, {Flags, Body}, _) ->
    not_managed;
process_entity_sub_msg(_, _, _) ->
    not_managed.

send_data_to_reader(State,
                    {DstEntityID, SrcEntityID, SN, #spdp_disc_part_data{} = Data}) ->
    R_GUID =
        #guId{prefix = State#state.destGuidPrefix,
              entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER},
    rtps_reader:receive_data(R_GUID,
                             {#guId{prefix = State#state.sourceGuidPrefix, entityId = SrcEntityID},
                              SN,
                              Data});
send_data_to_reader(State, {?ENTITYID_UNKNOWN, SrcEntityID, SN, Data}) ->
    %io:format("Data for unknown, maybe writer is in PUSH-mode, should be broadcasted... \n"),
    rtps_participant:send_to_all_readers(participant,
                                         {#guId{prefix = State#state.sourceGuidPrefix,
                                                entityId = SrcEntityID},
                                          SN,
                                          Data});
send_data_to_reader(State, {DstEntityID, SrcEntityID, SN, Data}) ->
    %io:format("Data for ~p\n",[DstEntityID]),
    R_GUID = #guId{prefix = State#state.destGuidPrefix, entityId = DstEntityID},
    rtps_full_reader:receive_data(R_GUID,
                                  {#guId{prefix = State#state.sourceGuidPrefix,
                                         entityId = SrcEntityID},
                                   SN,
                                   Data}).

send_gap_to_reader(State, #gap{readerGUID = R_GUID} = GAP) ->
    rtps_full_reader:receive_gap(R_GUID#guId{prefix = State#state.destGuidPrefix}, GAP).

send_acknack_to_writer(State, #acknack{writerGUID = W} = A) ->
    rtps_full_writer:receive_acknack(W, A).

send_heartbit_to_reader(State,
                        #heartbeat{readerGUID = #guId{prefix = Prefix, entityId = RID}} = H)
    when RID == ?ENTITYID_UNKNOWN ->
    %io:format("should send heartbeat ~p to all readers inside me \n",[H]), ok,
    rtps_participant:send_to_all_readers(participant, H);
send_heartbit_to_reader(State, #heartbeat{readerGUID = R} = H) ->
    [P | _] = pg:get_members(R),
    rtps_full_reader:receive_heartbeat(P, H).

sub_msg_parsing_loop(_, <<>>) ->
    ok;
sub_msg_parsing_loop(State, PayLoad) ->
    {Kind, Flags, Length, Tail} = rtps_messages:parse_submsg_header(PayLoad),
    <<Body:Length/binary, NextSubMsg/binary>> = Tail,
    % interpreter sub-msg (they change the state)
    NewState = change_receiver_state_for(Kind, Body, State),
    % enitities sub-msg (they exchange info for entities)
    case process_entity_sub_msg(Kind, {Flags, Body}, State) of
        not_managed ->
            ok;
        {data, D} ->
            send_data_to_reader(State, D);
        {gap, G} ->
            send_gap_to_reader(State, G);
        {heartbeat, H} ->
            send_heartbit_to_reader(State, H);
        {acknack, A} ->
            send_acknack_to_writer(State, A)
    end,
    % other messages
    sub_msg_parsing_loop(NewState, NextSubMsg).

analize(GuidPrefix, Packet, {Ip, Port}) ->
    {Version, Vendor, SourceGuidPrefix, PayLoad} = rtps_messages:parse_rtps_header(Packet),
    %io:format("Receiver parsing packet: guid_prefix = ~p\n",[SourceGuidPrefix]),
    State =
        #state{sourceVersion = Version,
               sourceVendorId = Vendor,% unknown vendor
               sourceGuidPrefix = SourceGuidPrefix,
               destGuidPrefix = GuidPrefix,
               unicastReplyLocatorList =
                   [#locator{kind = ?LOCATOR_KIND_UDPv4,
                             ip = Ip,
                             port = Port}],
               multicastReplyLocatorList =
                   [#locator{kind = ?LOCATOR_KIND_UDPv4,
                             ip = ?LOCATOR_ADDRESS_INVALID,
                             port = ?LOCATOR_PORT_INVALID}],
               haveTimestamp = false,
               timestamp = ?TIME_INVALID},

    % Do not interpret possible loopback messages:
    % NOTE: 
    % This forbids communications between endpoints in the same dds participant (Virtual Machine)
    % Communication inside one participant should be possible but should never rely on loopback UDP datagrams
    case GuidPrefix /= SourceGuidPrefix of
        true ->
            sub_msg_parsing_loop(State, PayLoad);
        false ->
            ok
    end.

% API
start_link() ->
    gen_server:start_link(?MODULE, #state{}, []).

get_local_locators(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_local_locators).

open_unicast_locators(Name, LocatorList) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {open_unicast_locators, LocatorList}).

open_multicast_locators(Name, LocatorList) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {open_multicast_locators, LocatorList}).

stop(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, stop).

% call backs
init(State) ->
    P = rtps_participant:get_info(participant),
    ID = {receiver_of, P#participant.guid#guId.prefix},
    pg:join(ID, self()),
    S1 = open_udp_locators(unicast, P#participant.defaultUnicastLocatorList, #state{}),
    S2 = open_udp_locators(multicast, P#participant.defaultMulticastLocatorList, S1),
    {ok, S2#state{destGuidPrefix = P#participant.guid#guId.prefix}}.

handle_call(get_local_locators, _, S) ->
    {reply, h_get_local_locators(S), S};
handle_call(stop, _, S) ->
    close_sockets(S#state.openedSockets),
    {reply, ok, S#state{openedSockets = []}};
handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({open_unicast_locators, List}, State) ->
    {noreply, open_udp_locators(unicast, List, State)};
handle_cast({open_multicast_locators, List}, State) ->
    {noreply, open_udp_locators(multicast, List, State)}.

handle_info({udp, Socket, Ip, Port, Packet}, #state{openedSockets = OS} = S) ->
    IsSocketValid = lists:any(fun({_,Socket,_,_}) -> true; (_) -> false end, OS),
    case IsSocketValid and rtps_messages:is_rtps_packet(Packet) of
        true ->
            analize(S#state.destGuidPrefix, Packet, {Ip, Port});
        false ->
            io:format("[RTPS_RECEIVER]: Bad packet\n")
    end,
    {noreply, S}.


% callback helpers

open_udp_locators(_, [], S) ->
    S;
open_udp_locators(unicast,
                  [#locator{ip = _, port = P} | TL],
                  #state{openedSockets = Soc} = S) ->
    LocalInterface = rtps_network_utils:get_local_ip(),
    {ok, Socket} = gen_udp:open(P, [{ip, {0,0,0,0}}, binary, {active, true}]),
    {ok, Port} = inet:port(Socket),
    open_udp_locators(unicast,
                      TL,
                      S#state{openedSockets = [{unicast, Socket, Port, LocalInterface} | Soc]});
open_udp_locators(multicast,
                  [#locator{ip = IP, port = P} | TL],
                  #state{openedSockets = Soc} = S) ->
    %io:format("~p.erl Opened Socket!\n",[?MODULE]),
    LocalInterface = rtps_network_utils:get_local_ip(),
    {ok, Socket} =
        gen_udp:open(P,
                     [{reuseaddr, true},
                      {ip, LocalInterface}, %{multicast_loop, false},
                      binary,
                      {active, true},
                      {add_membership, {IP, LocalInterface}}]),
    {ok, Port} = inet:port(Socket),
    open_udp_locators(multicast,
                      TL,
                      S#state{openedSockets = [{multicast, Socket, Port, IP} | Soc]}).

h_get_local_locators(#state{openedSockets =
                                Sockets}) -> %io:format("Asking locators: ~p\n",[Sockets]),
    [{Type,
      #locator{kind = ?LOCATOR_KIND_UDPv4,
               ip = I,
               port = P}}
     || {Type, S, P, I} <- Sockets].

close_sockets([]) ->
    ok;
close_sockets([{_, Socket, _, _} | TL]) ->
    gen_udp:close(Socket).
