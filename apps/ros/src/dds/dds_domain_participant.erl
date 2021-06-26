-module(dds_domain_participant).

-behaviour(gen_server).

-export([start_link/1]).
-export([get_default_publisher/1,update_participants_list/2,get_default_subscriber/1,get_discovered_participants/1]).%,create_publisher/2,create_subscriber/2]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).
-include("../protocol/rtps_structure.hrl").
-include("../protocol/rtps_constants.hrl").
-include("dds_types.hrl").
-include("../rcl/rmw_dds_msg.hrl").

-record(state,{
        guid_prefix,
        domain_id,
        default_publisher,
        default_subscriber,
        rtps_participant_pid,
        rtps_participant_info,
        known_participants = []}).

start_link(DomainID) -> gen_server:start_link( {local, dds},?MODULE, #state{domain_id=DomainID},[]).
% API
update_participants_list(Pid,Participants) -> gen_server:cast(Pid,{update_participants_list,Participants}).
get_default_publisher(Pid) -> gen_server:call(Pid,get_default_publisher).
get_default_subscriber(Pid) -> gen_server:call(Pid,get_default_subscriber).
get_discovered_participants(Pid) -> gen_server:call(Pid,get_discovered_participants).
%create_publisher(Pid,Setup) -> gen_server:call(Pid,{create_publisher,Setup}).
%create_subscriber(Pid,Setup) -> gen_server:call(Pid,{create_subscriber,Setup}).

%callbacks 
init(S) -> 
        {ok,P} = rtps_participant:create({self(),S#state.domain_id,<<?VendorId_0:8,?VendorId_1:8,(crypto:strong_rand_bytes(10))/binary>>}),
        rtps_participant:set_built_in_endpoints(P, 
                ?DISC_BUILTIN_ENDPOINT_PARTICIPANT_ANNOUNCER + 
                ?DISC_BUILTIN_ENDPOINT_PARTICIPANT_DETECTOR +
                ?DISC_BUILTIN_ENDPOINT_SUBSCRIPTIONS_ANNOUNCER+
                ?DISC_BUILTIN_ENDPOINT_SUBSCRIPTIONS_DETECTOR+   
                ?DISC_BUILTIN_ENDPOINT_PUBLICATIONS_ANNOUNCER+ 
                ?DISC_BUILTIN_ENDPOINT_PUBLICATIONS_DETECTOR),
        P_Info = rtps_participant:get_info(P),

        % The Default publisher and subscriber already create the built-in endpoints
        % needed to share info on the presence of application-defined DataWriters and DataReaders
        {ok,DP} = dds_publisher:start_link({self(), P_Info}), % holds data_writers
        {ok,DS} = dds_subscriber:start_link({self(), P_Info}), % holds data_readers

        % The subscriber needs the publisher to write subscriptions
        dds_subscriber:set_subscription_publisher(DS,DP),
        % The publisher needs the subscriber to listen to subscriptions
        % THIS triggers the publisher adding itself as listener 
        % of the subscription detector held by the subscriber
        dds_publisher:set_publication_subscriber(DP,DS),

        rtps_participant:start_discovery(P),
        {ok,S#state{rtps_participant_pid=P, rtps_participant_info=P_Info, default_publisher=DP, default_subscriber=DS}}.

handle_call(get_default_publisher, _, #state{default_publisher=PUB}=S) -> 
        {reply,PUB,S};
handle_call(get_default_subscriber, _, #state{default_subscriber=SUB}=S) -> 
        {reply,SUB,S};
handle_call({create_publisher,_}, _, S) -> 
        {reply, only_default_publisher, S};
handle_call({create_subscriber,_}, _, S) -> 
        {reply, only_default_subscriber, S};
handle_call(get_discovered_participants, _, #state{known_participants=P}=S) -> 
        {reply, P, S};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({update_participants_list,PL}, S) -> {noreply,h_update_participants_list(PL,S)};
handle_cast(_, State) -> {noreply,State}.

handle_info(_,State) -> {noreply,State}.

%HELPERS
filter_participants_with(PL, BUILTIN_ENDPOINT) -> 
        [D || #spdp_disc_part_data{availableBuiltinEndpoints=E}=D <- PL, 0 /= (E band BUILTIN_ENDPOINT) ].


h_update_participants_list(PL,#state{default_subscriber = DS, default_publisher= DP} = S) -> 
        
        Sub_Detectors = filter_participants_with(PL,?DISC_BUILTIN_ENDPOINT_SUBSCRIPTIONS_DETECTOR),
        MatchedReaders = [ #reader_proxy{
                                guid=#guId{prefix=P,entityId=?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR},
                                unicastLocatorList=U,
                                multicastLocatorList=M} || 
                        #spdp_disc_part_data{guidPrefix=P,meta_uni_locator_l=U,meta_multi_locator_l=M} <- Sub_Detectors],
        DW = dds_publisher:lookup_datawriter(DP, builtin_sub_announcer),
        dds_data_w:match_remote_readers(DW, MatchedReaders),

        Pub_Detectors = filter_participants_with(PL,?DISC_BUILTIN_ENDPOINT_PUBLICATIONS_DETECTOR),
        MatchedReaders_2 = [ #reader_proxy{
                                guid=#guId{prefix=P,entityId=?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR},
                                unicastLocatorList=U,
                                multicastLocatorList=M} || 
                        #spdp_disc_part_data{guidPrefix=P,meta_uni_locator_l=U,meta_multi_locator_l=M} <- Pub_Detectors],
        DW2 = dds_publisher:lookup_datawriter(DP, builtin_pub_announcer),
        dds_data_w:match_remote_readers(DW2, MatchedReaders_2),
        
        
        Pub_Annoucers = filter_participants_with(PL,?DISC_BUILTIN_ENDPOINT_PUBLICATIONS_ANNOUNCER),
        MatchedWriters_P = [ #writer_proxy{
                                guid=#guId{prefix=P,entityId=?ENTITYID_SEDP_BUILTIN_PUBLICATIONS_ANNOUNCER},
                                unicastLocatorList=U,
                                multicastLocatorList=M} || 
                        #spdp_disc_part_data{guidPrefix=P,meta_uni_locator_l=U,meta_multi_locator_l=M} <- Pub_Annoucers],
        %io:format("Subscriver is: ~p\n",[DS]),
        DR_P = dds_subscriber:lookup_datareader(DS, builtin_pub_detector),
        dds_data_r:match_remote_writers(DR_P, MatchedWriters_P),

        Sub_Annoucers = filter_participants_with(PL,?DISC_BUILTIN_ENDPOINT_SUBSCRIPTIONS_ANNOUNCER),
        MatchedWriters_S = [ #writer_proxy{
                                guid=#guId{prefix=P,entityId=?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER},
                                unicastLocatorList=U,
                                multicastLocatorList=M} || 
                        #spdp_disc_part_data{guidPrefix=P,meta_uni_locator_l=U,meta_multi_locator_l=M} <- Sub_Annoucers],
        %io:format("Sub announcer is is: ~p\n",[MatchedWriters_S]),
        DR_S = dds_subscriber:lookup_datareader(DS, builtin_sub_detector),
        dds_data_r:match_remote_writers(DR_S, MatchedWriters_S),

        % update the list of participants
        S#state{known_participants=PL}.