-module(dds_subscriber).

-behaviour(gen_server).

-export([start_link/0,create_datareader/2,lookup_datareader/2,on_data_available/2]). %set_subscription_publisher/2,
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

-record(state,{
        rtps_participant_info=#participant{},
        builtin_pub_detector,
        builtin_sub_detector,
        data_readers = [],
        incremental_key=1}).

start_link() -> gen_server:start_link( ?MODULE, [],[]).
% set_subscription_publisher(Name, Pub) -> 
%         [Pid|_] = pg:get_members(Name),
%         gen_server:call(Pid, {set_sub_publisher,Pub}).
create_datareader(Name,Topic) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_datareader,Topic}).
lookup_datareader(Name,Topic) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{lookup_datareader, Topic}).
on_data_available(Name,{R,ChangeKey}) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {on_data_available, {R,ChangeKey}}).
%callbacks 
init([]) ->  
        %io:format("\t~p.erl STARTED!\n",[?MODULE]),
        pg:join(dds_default_subscriber, self()),
        
        P_info = rtps_participant:get_info(participant),        
        SPDP_R_cfg = rtps_participant:get_spdp_reader_config(participant),
        supervisor:start_child(dds_datareaders_pool_sup, [{discovery_reader,P_info,SPDP_R_cfg}]),


        % The publication-reader(aka detector) will listen to which topics the other participants want to publish
        GUID_p = #guId{ prefix =  P_info#participant.guid#guId.prefix, 
                entityId = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR},        
        SEDP_Pub_Config = #endPoint{guid = GUID_p}, 
        {ok, _ } = supervisor:start_child(dds_datareaders_pool_sup, 
                        [{data_reader, dds_pub_detector, P_info, SEDP_Pub_Config}]),
               
        dds_data_r:set_listener({data_r_of, GUID_p}, {dds_default_subscriber, ?MODULE}),
        
        % The subscription-reader(aka detector) will listen to which topics the other participants want to subscribe
        GUID_s = #guId{ prefix =  P_info#participant.guid#guId.prefix, 
                entityId = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR},        
        SEDP_Sub_Config = #endPoint{guid = GUID_s}, 
        {ok, _ } = supervisor:start_child(dds_datareaders_pool_sup,
                [{data_reader, dds_sub_detector, P_info, SEDP_Sub_Config}]),
        
        {ok,#state{ rtps_participant_info=P_info, builtin_pub_detector = {data_r_of,GUID_p}, builtin_sub_detector = {data_r_of,GUID_s}}}.

handle_call({create_datareader,Topic}, _, #state{rtps_participant_info=P_info,
                                        data_readers = Readers, incremental_key = K}=S) ->     
        % Endpoint creation
        EntityID = #entityId{kind=?EKIND_USER_Reader_NO_Key,key = <<K:24>>},
        GUID = #guId{ prefix =  P_info#participant.guid#guId.prefix, entityId = EntityID},   
        Config = #endPoint{guid = GUID}, 
        {ok,_} = supervisor:start_child(dds_datareaders_pool_sup,
                                [{data_reader, Topic, P_info, Config}]),
        % Endpoint subscription
        SubAnnouncer = dds_publisher:lookup_datawriter(dds_default_publisher,builtin_sub_announcer),
        dds_data_w:write(SubAnnouncer, produce_sedp_disc_enpoint_data(P_info, Topic, EntityID)),
        {reply, {data_r_of, GUID}, S#state{data_readers = Readers ++ [{{data_r_of, GUID}, Topic}], incremental_key = K+1 }};

handle_call({lookup_datareader, builtin_pub_detector}, _, State) -> 
        {reply,State#state.builtin_pub_detector,State};
handle_call({lookup_datareader, builtin_sub_detector}, _, State) -> 
        {reply,State#state.builtin_sub_detector,State};
handle_call({lookup_datareader, Topic}, _, #state{data_readers=DR}=State) -> 
        [R|_] = [ Pid || {_,T,Pid} <- DR, T==Topic ],
        {reply, R, State};
% handle_call({set_sub_publisher,Pub}, _, S) -> {reply,ok,S#state{subscription_publisher=Pub}};
handle_call(_, _, State) -> {reply,ok,State}.

handle_cast({on_data_available,{R,ChangeKey}}, #state{data_readers=DR}=S) -> 
        Change = dds_data_r:read(R,ChangeKey), 
        %io:format("DDS: change: ~p, with key: ~p\n", [Change,ChangeKey]),
        Data = Change#cacheChange.data,
        ToBeMatched = [ ID || {ID,T} <- DR, T#user_topic.name == Data#sedp_disc_endpoint_data.topic_name],
        %io:format("DDS: discovered publisher of topic: ~p\n", [Data#sedp_disc_endpoint_data.topic_name]),
        %io:format("DDS: i have theese topics: ~p\n", [[ T || {_,T} <- DR]]),
        %io:format("DDS: interested readers are: ~p\n", [ToBeMatched]),
        [P|_] = [P || #spdp_disc_part_data{guidPrefix = Pref}=P <- dds_domain_participant:get_discovered_participants(dds), 
                                                        Pref == Data#sedp_disc_endpoint_data.endpointGuid#guId.prefix],
        Proxy = #writer_proxy{guid = Data#sedp_disc_endpoint_data.endpointGuid,        
                        unicastLocatorList = P#spdp_disc_part_data.default_uni_locator_l,
                        multicastLocatorList = P#spdp_disc_part_data.default_multi_locato_l},
        [ dds_data_r:match_remote_writers(ID,[Proxy]) || ID <- ToBeMatched ],
        {noreply,S};
handle_cast(_, State) -> {noreply,State}.

handle_info(_,State) -> {noreply,State}.


% HELPERS
produce_sedp_disc_enpoint_data(#participant{guid=#guId{prefix=P},vendorId=VID,protocolVersion=PVER},
                #user_topic{ type_name=TN, name=N, 
                                qos_profile=#qos_profile{reliability=R,durability=D,history=H}},
                EntityID) -> 
        #sedp_disc_endpoint_data{
                dst_reader_id = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR,
                endpointGuid= #guId{prefix = P, entityId = EntityID},
                topic_type=TN,
                topic_name=N,
                protocolVersion=PVER,
                vendorId=VID,
                history_qos = H,
                durability_qos = D,
                reliability_qos = R
        }.