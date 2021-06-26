-module(dds_publisher).

-behaviour(gen_server).

-export([start_link/1,set_publication_subscriber/2,create_datawriter/2,lookup_datawriter/2,on_data_available/2]).%,suspend_publications/1,resume_pubblications/1]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).


-include("../dds/dds_types.hrl").
-include("../protocol/rtps_constants.hrl").
-include("../protocol/rtps_structure.hrl").

-record(state,{
        domain_participant,
        rtps_participant_info=#participant{},
        publication_subscriber,
        builtin_pub_announcer,
        builtin_sub_announcer,
        data_writers = [],
        incremental_key=1}).

start_link(Setup) -> gen_server:start_link( ?MODULE, Setup,[]).
set_publication_subscriber(Pid, Sub) -> gen_server:call(Pid, {set_pub_subscriber,Sub}).
on_data_available(Pid,{R,ChangeKey}) -> gen_server:cast(Pid, {on_data_available, {R,ChangeKey}}).
create_datawriter(Pid,Topic) -> gen_server:call(Pid,{create_datawriter,Topic}).
lookup_datawriter(Pid,Topic) -> gen_server:call(Pid,{lookup_datawriter,Topic}).

%callbacks 
init({DP, P_info}) ->  
        % the Subscription-writer(aka announcer) will forward my willing to listen to defined topics
        EntityID_s = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER,        
        {ok,DW_S} = dds_data_w:start_link({builtin_sub_announcer,P_info,EntityID_s}),
        %the publication-writer(aka announcer) will forward my willing to talk to defined topics
        EntityID_p = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_ANNOUNCER,        
        {ok,DW_P} = dds_data_w:start_link({builtin_pub_announcer,P_info,EntityID_p}),
        % I subscribe the dds_publisher to the subscription detector
        
        {ok,#state{domain_participant=DP, rtps_participant_info=P_info, 
                builtin_pub_announcer=DW_P, builtin_sub_announcer = DW_S}}.

handle_call({create_datawriter,Topic}, _, 
                #state{rtps_participant_info=I,data_writers=Writers, builtin_pub_announcer=PubAnnouncer, incremental_key = K}=S) -> 
        % Endpoint creation        
        EntityID = #entityId{kind=?EKIND_USER_Writer_NO_Key,key = <<K:24>>},        
        {ok,DW} = dds_data_w:start_link({Topic,I,EntityID}),
        % Endpoint announcement
        dds_data_w:write(PubAnnouncer, produce_sedp_disc_enpoint_data(I, Topic, EntityID)),
        {reply, DW, S#state{data_writers = Writers ++ [{EntityID,Topic,DW}], incremental_key = K+1 }};

handle_call({lookup_datawriter,builtin_sub_announcer}, _, State) -> {reply,State#state.builtin_sub_announcer,State};
handle_call({lookup_datawriter,builtin_pub_announcer}, _, State) -> {reply,State#state.builtin_pub_announcer,State};
handle_call({lookup_datawriter,Topic}, _, #state{data_writers=DW} = S) -> 
        [W|_] = [ Pid || {ID,T,Pid} <- DW, T==Topic ],
        {reply, W, S};
handle_call({set_pub_subscriber,Sub}, _, S) -> 
        SubDetector = dds_subscriber:lookup_datareader(Sub, builtin_sub_detector),
        dds_data_r:set_listener(SubDetector, {self(), ?MODULE}),
        {reply,ok,S#state{publication_subscriber=Sub}};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({on_data_available,{R,ChangeKey}}, #state{domain_participant = DP, data_writers=DW}=S) -> 
        Change = dds_data_r:read(R,ChangeKey), 
        %io:format("DDS: change: ~p, with key: ~p\n", [Change,ChangeKey]),
        Data = Change#cacheChange.data,
        ToBeMatched = [ Pid || {_,T,Pid} <- DW, T#user_topic.name == Data#sedp_disc_endpoint_data.topic_name],
        % io:format("DDS: node willing to subscribe to topic : ~p\n", [Data#sedp_disc_endpoint_data.topic_name]),
        % io:format("DDS: i have theese topics: ~p\n", [[ T || {_,T,Pid} <- DR]]),
        %io:format("DDS: interested writers are: ~p\n", [ToBeMatched]),
        [P|_] = [P || #spdp_disc_part_data{guidPrefix = Pref}=P <- dds_domain_participant:get_discovered_participants(DP), 
                                                         Pref == Data#sedp_disc_endpoint_data.endpointGuid#guId.prefix],
        Proxy = #reader_proxy{guid = Data#sedp_disc_endpoint_data.endpointGuid,        
                         unicastLocatorList = P#spdp_disc_part_data.default_uni_locator_l,
                         multicastLocatorList = P#spdp_disc_part_data.default_multi_locato_l},
        [ dds_data_w:remote_reader_add(Pid,Proxy) || Pid <- ToBeMatched ],
        {noreply,S};
handle_cast(_, State) -> {noreply,State}.

handle_info(_,State) -> {noreply,State}.

% HELPERS
produce_sedp_disc_enpoint_data(#participant{guid=#guId{prefix=P},vendorId=VID,protocolVersion=PVER},
                #user_topic{ type_name=TN, name=N, 
                                qos_profile=#qos_profile{reliability=R,durability=D,history=H}},
                EntityID) -> 
        #sedp_disc_endpoint_data{
                dst_reader_id = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR,
                endpointGuid= #guId{prefix = P, entityId = EntityID},
                topic_type=TN,
                topic_name=N,
                protocolVersion=PVER,
                vendorId=VID,
                history_qos = H,
                durability_qos = D,
                reliability_qos = R
        }.