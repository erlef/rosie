-module(dds_subscriber).

-behaviour(gen_server).

-export([start_link/1,set_subscription_publisher/2,create_datareader/2,lookup_datareader/2,on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include("../protocol/rtps_constants.hrl").
-include("../protocol/rtps_structure.hrl").
-include("dds_types.hrl").

-record(state,{
        domain_participant,
        rtps_participant_info=#participant{},
        subscription_publisher,
        builtin_pub_detector,
        builtin_sub_detector,
        data_readers = [],
        incremental_key=1}).

start_link(Setup) -> gen_server:start_link( ?MODULE, Setup,[]).
set_subscription_publisher(Pid, Pub) -> gen_server:call(Pid, {set_sub_publisher,Pub}).
create_datareader(Pid,Topic) -> gen_server:call(Pid,{create_datareader,Topic}).
lookup_datareader(Pid,Topic) -> gen_server:call(Pid,{lookup_datareader, Topic}).
on_data_available(Pid,{R,ChangeKey}) -> gen_server:cast(Pid, {on_data_available, {R,ChangeKey}}).
%callbacks 
init({DP, P_info}) ->  
        % The publication-reader(aka detector) will listen to which topics the other participants want to publish
        EntityID_p = ?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR,        
        {ok,DR_P} = dds_data_r:start_link({dds_pub_detector,P_info,EntityID_p}),
        dds_data_r:set_listener(DR_P, {self(), ?MODULE}),
        % The subscription-reader(aka detector) will listen to which topics the other participants want to subscribe
        EntityID_s = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR,        
        {ok,DR_S} = dds_data_r:start_link({dds_sub_detector,P_info,EntityID_s}),
        
        {ok,#state{domain_participant=DP, rtps_participant_info=P_info,
                 builtin_pub_detector = DR_P, builtin_sub_detector = DR_S}}.

handle_call({create_datareader,Topic}, _, #state{domain_participant=DP,rtps_participant_info=I,
                subscription_publisher = Sub_p, data_readers = Readers, incremental_key = K}=S) ->        
        % Endpoint creation
        EntityID = #entityId{kind=?EKIND_USER_Reader_NO_Key,key = <<K:24>>},
        {ok,DR} = dds_data_r:start_link({Topic,I,EntityID}),
        % Endpoint subscription
        SubAnnouncer = dds_publisher:lookup_datawriter(Sub_p,builtin_sub_announcer),
        dds_data_w:write(SubAnnouncer, produce_sedp_disc_enpoint_data(I, Topic, EntityID)),
        {reply, DR, S#state{data_readers = Readers ++ [{EntityID, Topic, DR}], incremental_key = K+1 }};

handle_call({lookup_datareader, builtin_pub_detector}, _, State) -> 
        {reply,State#state.builtin_pub_detector,State};
handle_call({lookup_datareader, builtin_sub_detector}, _, State) -> 
        {reply,State#state.builtin_sub_detector,State};
handle_call({lookup_datareader, Topic}, _, #state{data_readers=DR}=State) -> 
        [R|_] = [ Pid || {ID,T,Pid} <- DR, T==Topic ],
        {reply, R, State};
handle_call({set_sub_publisher,Pub}, _, S) -> {reply,ok,S#state{subscription_publisher=Pub}};
handle_call(_, _, State) -> {reply,ok,State}.

handle_cast({on_data_available,{R,ChangeKey}}, #state{domain_participant = DP, data_readers=DR}=S) -> 
        Change = dds_data_r:read(R,ChangeKey), 
        %io:format("DDS: change: ~p, with key: ~p\n", [Change,ChangeKey]),
        Data = Change#cacheChange.data,
        ToBeMatched = [ Pid || {_,T,Pid} <- DR, T#user_topic.name == Data#sedp_disc_endpoint_data.topic_name],
        io:format("DDS: discovered publisher of topic: ~p\n", [Data#sedp_disc_endpoint_data.topic_name]),
        % io:format("DDS: i have theese topics: ~p\n", [[ T || {_,T,Pid} <- DR]]),
        % io:format("DDS: interested readers are: ~p\n", [ToBeMatched]),
        [P|_] = [P || #spdp_disc_part_data{guidPrefix = Pref}=P <- dds_domain_participant:get_discovered_participants(DP), 
                                                        Pref == Data#sedp_disc_endpoint_data.endpointGuid#guId.prefix],
        Proxy = #writer_proxy{guid = Data#sedp_disc_endpoint_data.endpointGuid,        
                        unicastLocatorList = P#spdp_disc_part_data.default_uni_locator_l,
                        multicastLocatorList = P#spdp_disc_part_data.default_multi_locato_l},
        [ dds_data_r:match_remote_writers(Pid,[Proxy]) || Pid <- ToBeMatched ],
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