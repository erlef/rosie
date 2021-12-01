-module(dds_subscriber).



-export([start_link/0, 
        get_all_data_readers/1, 
        create_datareader/2, 
        lookup_datareader/2,
        delete_datareader/2,
        dispose_data_readers/1]). %set_subscription_publisher/2,

-behaviour(gen_data_reader_listener).
-export([on_data_available/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

-record(state,
        {rtps_participant_info = #participant{},
         builtin_pub_detector,
         builtin_sub_detector,
         builtin_msg_reader,
         data_readers = #{}, % { data_r_of, #guid{} } => {SupervisorPid, #dds_user_topic{}}
         incremental_key = 1}).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

% set_subscription_publisher(Name, Pub) ->
%         [Pid|_] = pg:get_members(Name),
%         gen_server:call(Pid, {set_sub_publisher,Pub}).
create_datareader(Name, Topic) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_datareader, Topic}).

lookup_datareader(Name, Topic) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {lookup_datareader, Topic}).

delete_datareader(Name, ReaderName) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {delete_datareader, ReaderName}).

get_all_data_readers(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_data_readers).

dispose_data_readers(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, dispose_data_readers).

on_data_available(Name, {R, ChangeKey}) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_data_available, {R, ChangeKey}}).

%callbacks
init([]) ->
    %io:format("\t~p.erl STARTED!\n",[?MODULE]),
    pg:join(dds_default_subscriber, self()),

    P_info = rtps_participant:get_info(participant),
    SPDP_R_cfg = rtps_participant:get_spdp_reader_config(participant),
    SPDP_R_qos = #qos_profile{
        reliability = ?BEST_EFFORT_RELIABILITY_QOS,
        durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
        history = {?KEEP_ALL_HISTORY_QOS, -1}
    },
    supervisor:start_child(dds_datareaders_pool_sup,
                           [{discovery_reader, P_info, SPDP_R_cfg, SPDP_R_qos}]),
    
    SEDP_qos = #qos_profile{durability = ?TRANSIENT_LOCAL_DURABILITY_QOS, history = {?KEEP_ALL_HISTORY_QOS, -1}},
    % The publication-reader(aka detector) will listen to which topics the other participants want to publish
    GUID_p =
        #guId{prefix = P_info#participant.guid#guId.prefix,
              entityId = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR},
    SEDP_Pub_Config = #endPoint{guid = GUID_p},
    {ok, _} =
        supervisor:start_child(dds_datareaders_pool_sup,
                               [{data_reader, #dds_user_topic{qos_profile=SEDP_qos}, P_info, SEDP_Pub_Config}]),

    dds_data_r:set_listener({data_r_of, GUID_p}, {?MODULE, dds_default_subscriber}),

    % The subscription-reader(aka detector) will listen to which topics the other participants want to subscribe
    GUID_s =
        #guId{prefix = P_info#participant.guid#guId.prefix,
              entityId = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR},
    SEDP_Sub_Config = #endPoint{guid = GUID_s},
    {ok, _} =
        supervisor:start_child(dds_datareaders_pool_sup,
                               [{data_reader, #dds_user_topic{qos_profile=SEDP_qos}, P_info, SEDP_Sub_Config}]),

    % The builtin message reader for general purpose comunications between DDS participants
    GUID_MR =
        #guId{prefix = P_info#participant.guid#guId.prefix,
              entityId = ?ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_READER},
    P2P_Reader_Config = #endPoint{guid = GUID_MR},
    {ok, _} =
        supervisor:start_child(dds_datareaders_pool_sup,
                               [{data_reader, #dds_user_topic{qos_profile=SEDP_qos}, P_info, P2P_Reader_Config}]),

    {ok,
     #state{rtps_participant_info = P_info,
            builtin_pub_detector = {data_r_of, GUID_p},
            builtin_sub_detector = {data_r_of, GUID_s},
            builtin_msg_reader = {data_r_of, GUID_MR}}}.

handle_call({create_datareader, Topic},
            _,
            #state{rtps_participant_info = P_info,
                   data_readers = Readers,
                   incremental_key = K} =
                S) ->
    % Endpoint creation
    EntityID = #entityId{kind = ?EKIND_USER_Reader_NO_Key, key = <<K:24>>},
    GUID = #guId{prefix = P_info#participant.guid#guId.prefix, entityId = EntityID},
    Config = #endPoint{guid = GUID},
    {ok, SupervisorPid} =
        supervisor:start_child(dds_datareaders_pool_sup, [{data_reader, Topic, P_info, Config}]),

    match_with_discovered_writers({data_r_of, GUID}, Topic, S),

    % Endpoint subscription
    SubAnnouncer =
        dds_publisher:lookup_datawriter(dds_default_publisher, builtin_sub_announcer),
    dds_data_w:write(SubAnnouncer, produce_sedp_disc_enpoint_data(P_info, Topic, EntityID)),
    {reply,
     {data_r_of, GUID},
     S#state{data_readers = Readers#{ {data_r_of, GUID} => {SupervisorPid, Topic} },
             incremental_key = K + 1}};
handle_call({lookup_datareader, builtin_pub_detector}, _, State) ->
    {reply, State#state.builtin_pub_detector, State};
handle_call({lookup_datareader, builtin_sub_detector}, _, State) ->
    {reply, State#state.builtin_sub_detector, State};
handle_call({lookup_datareader, Topic}, _, #state{data_readers = DR} = S) ->
    [R | _] = [ R || {R,{_,T}} <- maps:to_list(DR), T == Topic],
    {reply, R, S};
handle_call({delete_datareader, {_,GUID} = Reader}, _, #state{rtps_participant_info = P_info, 
                                                            data_readers = DR} = S) ->
    Sub_announcer = dds_publisher:lookup_datawriter(dds_default_publisher, builtin_sub_announcer),                                                            
    dds_data_w:write(Sub_announcer, produce_sedp_endpoint_leaving(P_info, GUID#guId.entityId)),
    {SupervisorPid, _} = maps:get(Reader,DR),
    supervisor:terminate_child(dds_datareaders_pool_sup, SupervisorPid),
    {reply, ok, S#state{data_readers = maps:remove(Reader,DR)}};
handle_call(get_all_data_readers, _, #state{data_readers = DR} = S) ->
    {reply, maps:keys(DR), S};
handle_call(dispose_data_readers, _, #state{rtps_participant_info = P_info, data_readers = DR} = S) ->
    Sub_announcer =
        dds_publisher:lookup_datawriter(dds_default_publisher, builtin_sub_announcer),
    [dds_data_w:write(Sub_announcer, produce_sedp_endpoint_leaving(P_info, ID))
     || {_, #guId{entityId = ID}} <- maps:keys(DR)],
    dds_data_w:flush_all_changes(Sub_announcer),
    {reply, ok, S#state{data_readers = #{}} };
handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({on_data_available, {R, ChangeKey}}, #state{data_readers = DR} = S) ->
    Change = dds_data_r:read(R, ChangeKey), 
    % io:format("DDS: change: ~p, with key: ~p\n", [Change,ChangeKey]),
    Data = Change#cacheChange.data, 
    % io:format("~p\n",[Data#sedp_disc_endpoint_data.status_qos]),
    case ?ENDPOINT_LEAVING(Data#sedp_disc_endpoint_data.status_qos) of
        true ->
            [dds_data_r:remote_writer_remove(R, Data#sedp_disc_endpoint_data.endpointGuid)
             || R <- maps:keys(DR)];
        _ ->
            ToBeMatched =
                [R
                 || {R,{_,T}} <- maps:to_list(DR),
                    (T#dds_user_topic.name == Data#sedp_disc_endpoint_data.topic_name) and 
                    (T#dds_user_topic.type_name ==  Data#sedp_disc_endpoint_data.topic_type)],
            %io:format("DDS: discovered publisher of topic: ~p\n", [Data#sedp_disc_endpoint_data.topic_name]),
            %io:format("DDS: i have theese topics: ~p\n", [[ T || {_,T,_} <- DR]]),
            %io:format("DDS: interested readers are: ~p\n", [ToBeMatched]),
            Participants = rtps_participant:get_discovered_participants(participant),
            [match_reader_with_writer(Pid, Data, Participants) || Pid <- ToBeMatched]
    end,
    {noreply, S};
handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

% HELPERS
%
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
    #sedp_disc_endpoint_data{dst_reader_id = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR,
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

match_with_discovered_writers(DR,
                              #dds_user_topic{name = Tname, type_name = Ttype},
                              #state{builtin_pub_detector = PubDetector}) ->
    RemoteWriters = [D || #cacheChange{data = D} <- dds_data_r:read_all(PubDetector)],
    %io:format("Remote writers for topic ~p are ~p\n",[Tname,RemoteWriters]),
    ToBeMatched =
        [W || #sedp_disc_endpoint_data{topic_name = N, topic_type = T} = W <- RemoteWriters, (N == Tname) and (T == Ttype)],
    Participants = rtps_participant:get_discovered_participants(participant),
    [match_reader_with_writer(DR, W, Participants) || W <- ToBeMatched].

match_reader_with_writer(DR, WriterData, Participants) ->
    [P | _] =
        [P
         || #spdp_disc_part_data{guidPrefix = Pref} = P <- Participants,
            Pref == WriterData#sedp_disc_endpoint_data.endpointGuid#guId.prefix],
    Proxy =
        #writer_proxy{guid = WriterData#sedp_disc_endpoint_data.endpointGuid,
                      unicastLocatorList = P#spdp_disc_part_data.default_uni_locator_l,
                      multicastLocatorList = P#spdp_disc_part_data.default_multi_locator_l},
    %io:format("Matching: ~p with ~p\n",[DR,Proxy]),
    dds_data_r:remote_writer_add(DR, Proxy).
