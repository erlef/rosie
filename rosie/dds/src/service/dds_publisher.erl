-module(dds_publisher).


-export([start_link/0, 
        get_all_data_writers/1, 
        create_datawriter/2, 
        lookup_datawriter/2,
        delete_datawriter/2,
        dispose_data_writers/1, 
        endpoint_has_been_acknoledged/2]).
         %wait_for_acknoledgements/1]).%set_publication_subscriber/2,suspend_publications/1,resume_pubblications/1]).

-behaviour(gen_data_reader_listener).
-export([on_data_available/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

-record(state,
        {rtps_participant_info = #participant{},
         builtin_pub_announcer,
         builtin_sub_announcer,
         builtin_msg_writer,
         data_writers = #{}, % { data_w_of, #guid{} } => {SupervisorPid, #dds_user_topic{}}
         incremental_key = 1}).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

on_data_available(Name, {R, ChangeKey}) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_data_available, {R, ChangeKey}}).

create_datawriter(Name, Topic) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_datawriter, Topic}).

lookup_datawriter(Name, Topic) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {lookup_datawriter, Topic}).

delete_datawriter(Name, WriterName) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {delete_datawriter, WriterName}).

get_all_data_writers(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_data_writers).

dispose_data_writers(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, dispose_data_writers).

endpoint_has_been_acknoledged(Name, Endpoint) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {endpoint_has_been_acknoledged,Endpoint}).

% wait_for_acknoledgements(Name) ->
%     [Pid | _] = pg:get_members(Name),
%     gen_server:call(Pid, wait_for_acknoledgements).

%callbacks
init([]) ->
    process_flag(trap_exit, true),
    pg:join(dds_default_publisher, self()),

    P_info = rtps_participant:get_info(participant),
    SPDP_W_cfg = rtps_participant:get_spdp_writer_config(participant),
    SPDP_W_qos = #qos_profile{
        reliability = ?BEST_EFFORT_RELIABILITY_QOS,
        durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
        history = {?KEEP_ALL_HISTORY_QOS, -1}
    },
    {ok, _} =
        supervisor:start_child(dds_datawriters_pool_sup,
                               [{discovery_writer, P_info, SPDP_W_cfg, SPDP_W_qos}]),

    SEDP_qos = #qos_profile{durability = ?TRANSIENT_LOCAL_DURABILITY_QOS, history = {?KEEP_ALL_HISTORY_QOS, -1}},
    % the Subscription-writer(aka announcer) will forward my willing to listen to defined topics
    GUID_s =
        #guId{prefix = P_info#participant.guid#guId.prefix,
              entityId = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER},
    SEDP_Sub_Config = #endPoint{guid = GUID_s},
    {ok, _} =
        supervisor:start_child(dds_datawriters_pool_sup,
                               [{data_writer, #dds_user_topic{qos_profile=SEDP_qos}, P_info, SEDP_Sub_Config}]),

    %the publication-writer(aka announcer) will forward my willing to talk to defined topics
    GUID_p =
        #guId{prefix = P_info#participant.guid#guId.prefix,
              entityId = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_ANNOUNCER},
    SEDP_Pub_Config = #endPoint{guid = GUID_p},
    {ok, _} =
        supervisor:start_child(dds_datawriters_pool_sup,
                               [{data_writer, #dds_user_topic{qos_profile=SEDP_qos}, P_info, SEDP_Pub_Config}]),

    % the publisher listens to the sub_detector to add remote readers to its writers
    SubDetector =
        dds_subscriber:lookup_datareader(dds_default_subscriber, builtin_sub_detector),
    dds_data_r:set_listener(SubDetector, {?MODULE, dds_default_publisher}),

    % The builtin message writer for general purpose comunications between DDS participants
    GUID_MW =
        #guId{prefix = P_info#participant.guid#guId.prefix,
              entityId = ?ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER},
    P2P_Writer_Config = #endPoint{guid = GUID_MW},
    {ok, _} =
        supervisor:start_child(dds_datawriters_pool_sup,
                               [{data_writer, #dds_user_topic{qos_profile=SEDP_qos}, P_info, P2P_Writer_Config}]),

    {ok,
     #state{rtps_participant_info = P_info,
            builtin_pub_announcer = {data_w_of, GUID_p},
            builtin_sub_announcer = {data_w_of, GUID_s},
            builtin_msg_writer = {data_w_of, GUID_MW}}}.

handle_call({create_datawriter, Topic},
            _,
            #state{rtps_participant_info = P_info,
                   data_writers = Writers,
                   builtin_pub_announcer = PubAnnouncer,
                   incremental_key = K} =
                S) ->
    % Endpoint creation
    EntityID = #entityId{kind = ?EKIND_USER_Writer_NO_Key, key = <<K:24>>},
    GUID = #guId{prefix = P_info#participant.guid#guId.prefix, entityId = EntityID},
    Config = #endPoint{guid = GUID},
    {ok, SupPid} =
        supervisor:start_child(dds_datawriters_pool_sup, [{data_writer, Topic, P_info, Config}]),
    match_with_discovered_readers({data_w_of, GUID}, Topic),
    % Endpoint announcement
    dds_data_w:write(PubAnnouncer, produce_sedp_disc_enpoint_data(P_info, Topic, EntityID)),
    {reply,
     {data_w_of, GUID},
     S#state{data_writers = Writers#{ {data_w_of, GUID} => {SupPid, Topic} },
             incremental_key = K + 1}};
handle_call({lookup_datawriter, builtin_sub_announcer}, _, State) ->
    {reply, State#state.builtin_sub_announcer, State};
handle_call({lookup_datawriter, builtin_pub_announcer}, _, State) ->
    {reply, State#state.builtin_pub_announcer, State};
handle_call({lookup_datawriter, Topic}, _, #state{data_writers = DW} = S) ->
    [W | _] = [ W || {W,{_,T}} <- maps:to_list(DW), T == Topic],
    {reply, W, S};
handle_call({delete_datawriter, {_,GUID} = Writer}, _, #state{rtps_participant_info = P_info, 
                                                            builtin_pub_announcer = PubAnnouncer,
                                                            data_writers = DW} = S) ->
    dds_data_w:write(PubAnnouncer, produce_sedp_endpoint_leaving(P_info, GUID#guId.entityId)),
    {SupervisorPid, _} = maps:get(Writer,DW),
    supervisor:terminate_child(dds_datawriters_pool_sup, SupervisorPid),
    {reply, ok, S#state{data_writers = maps:remove(Writer,DW)}};
handle_call(get_all_data_writers, _, #state{data_writers = DW} = S) ->
    {reply, maps:keys(DW), S};
handle_call(dispose_data_writers, _,#state{rtps_participant_info = P_info,
                    builtin_pub_announcer = Pub_announcer, data_writers = DW} = S) ->
    [dds_data_w:write(Pub_announcer, produce_sedp_endpoint_leaving(P_info, ID))
     || {_, #guId{entityId = ID}} <- maps:keys(DW)],
    dds_data_w:flush_all_changes(Pub_announcer),
    {reply, ok, S#state{data_writers = #{}} };
handle_call({endpoint_has_been_acknoledged,{data_w_of, WGUID}}, _, #state{builtin_pub_announcer = {data_w_of, PUB_GUID}} = S) ->
    Changes = rtps_history_cache:get_all_changes({cache_of,PUB_GUID}),
    [ChangeKey|_] = [ {GUID, SN} || #cacheChange{writerGuid=GUID,sequenceNumber=SN,data=#sedp_disc_endpoint_data{endpointGuid=E}} <- Changes, E == WGUID],
    {reply, dds_data_w:is_sample_acknowledged({data_w_of, PUB_GUID}, ChangeKey), S};
handle_call({endpoint_has_been_acknoledged,{data_r_of, RGUID}}, _, #state{builtin_sub_announcer = {data_w_of, SUB_GUID}} = S) ->
    Changes = rtps_history_cache:get_all_changes({cache_of,SUB_GUID}),
    %io:format("Subscriptions:\n~p\n",[Changes]),
    [ChangeKey|_] = [ {GUID, SN} || #cacheChange{writerGuid=GUID,sequenceNumber=SN,data=#sedp_disc_endpoint_data{endpointGuid=E}} <- Changes, E == RGUID],
    %io:format("Change:\n~p\n",[ChangeKey]),
    {reply, dds_data_w:is_sample_acknowledged({data_w_of, SUB_GUID}, ChangeKey), S}.
% handle_call(wait_for_acknoledgements,
%             _,
%             #state{rtps_participant_info = P_info,
%                    builtin_pub_announcer = Pub_announcer,
%                    data_writers = DW} =
%                 S) ->
%     {reply, ok, S};

handle_cast({on_data_available, {R, ChangeKey}}, #state{data_writers = DW} = S) ->
    Change = dds_data_r:read(R, ChangeKey),  %io:format("DDS: change: ~p, with key: ~p\n", [Change,ChangeKey]),
    Data = Change#cacheChange.data,
    case ?ENDPOINT_LEAVING(Data#sedp_disc_endpoint_data.status_qos) of
        true -> %io:format("I should remove some ReaderProxy\n"),
            [dds_data_w:remote_reader_remove(W, Data#sedp_disc_endpoint_data.endpointGuid)
             || W <- maps:keys(DW)];
        _ ->
            ToBeMatched =
                [W
                 || {W,{_,T}} <- maps:to_list(DW),
                    (T#dds_user_topic.name == Data#sedp_disc_endpoint_data.topic_name) and 
                    (T#dds_user_topic.type_name ==  Data#sedp_disc_endpoint_data.topic_type)],
            %io:format("DDS: node willing to subscribe to topic : ~p\n", [Data#sedp_disc_endpoint_data.topic_name]),
            %io:format("DDS: i have theese topics: ~p\n", [[ T || {_,T,Pid} <- DW]]),
            %io:format("DDS: interested writers are: ~p\n", [ToBeMatched]),
            Participants = rtps_participant:get_discovered_participants(participant),
            [match_writer_with_reader(Pid, Data, Participants) || Pid <- ToBeMatched]
    end,
    {noreply, S}.

% HELPERS
produce_sedp_disc_enpoint_data(#participant{guid = #guId{prefix = P},
                                            vendorId = VID,
                                            protocolVersion = PVER},
                               #dds_user_topic{type_name = TN,
                                           name = N,
                                           qos_profile =
                                               #qos_profile{reliability = R,
                                                            durability = D,
                                                            history = H}},
                               EntityID) ->
    #sedp_disc_endpoint_data{dst_reader_id = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR,
                             endpointGuid = #guId{prefix = P, entityId = EntityID},
                             topic_type = TN,
                             topic_name = N,
                             protocolVersion = PVER,
                             vendorId = VID,
                             history_qos = H,
                             durability_qos = D,
                             reliability_qos = R}.

produce_sedp_endpoint_leaving(#participant{guid = #guId{prefix = P}}, EntityID) ->
    #sedp_endpoint_state{guid = #guId{prefix = P, entityId = EntityID},
                         status_flags = ?STATUS_INFO_UNREGISTERED + ?STATUS_INFO_DISPOSED}.

match_with_discovered_readers(DW, #dds_user_topic{name = Tname, type_name = Ttype}) ->
    SubDetector =
        dds_subscriber:lookup_datareader(dds_default_subscriber, builtin_sub_detector),
    RemoteReaders = [D || #cacheChange{data = D} <- dds_data_r:read_all(SubDetector)],
    %io:format("Remote readers for topic ~p are ~p\n",[Tname,RemoteReaders]),
    ToBeMatched =
        [R || #sedp_disc_endpoint_data{topic_name = N, topic_type = T} = R <- RemoteReaders, (N == Tname) and (T == Ttype)],

    Participants = rtps_participant:get_discovered_participants(participant),
    [match_writer_with_reader(DW, R, Participants) || R <- ToBeMatched].

match_writer_with_reader(DW, ReaderData, Participants) ->
    [P | _] =
        [P
         || #spdp_disc_part_data{guidPrefix = Pref} = P <- Participants,
            Pref == ReaderData#sedp_disc_endpoint_data.endpointGuid#guId.prefix],
    Proxy =
        #reader_proxy{guid = ReaderData#sedp_disc_endpoint_data.endpointGuid,
                      unicastLocatorList = P#spdp_disc_part_data.default_uni_locator_l,
                      multicastLocatorList = P#spdp_disc_part_data.default_multi_locator_l},
    %io:format("Matching: ~p with ~p\n",[DW,Proxy]),
    dds_data_w:remote_reader_add(DW, Proxy).
