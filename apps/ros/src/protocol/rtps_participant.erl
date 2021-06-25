% This module contains the participant implementation with SPDPwriter and SDPDreader.
-module(rtps_participant).

-behaviour(gen_server).

% the rtps participant should contain all endpoints, in other terms it should also hold their pids
% and be responsible for construction and destruction of RTPS endpoints.
-export([create/1,create_full_writer/3,create_full_reader/3,send_to_all_readers/2,
        get_discovered_participants/1,get_info/1,set_built_in_endpoints/2,start_discovery/1]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include("rtps_structure.hrl").
-include("rtps_constants.hrl").

-record(state,{
        dds_domain_participant,
        participant = #participant{},
        gateway,
        msg_receiver,
        spdp_writer,
        spdp_reader,
        spdp_data,        
        readers_list = [],
        writers_list = []
}).

create({DDS_DP,DomainID,Prefix}) -> pg:start_link(), gen_server:start_link( {local, participant}, ?MODULE, {DDS_DP, DomainID,Prefix},[]).

init({DDS_DP, DomainID,GuidPrefix}) -> 
        Participant = #participant{guid=#guId{
                        prefix = GuidPrefix, 
                        entityId = ?ENTITYID_PARTICIPANT
                        },
                        domainId = DomainID,
                        protocolVersion = <<?V_MAJOR,?V_MINOR>>,
                        vendorId = <<?VendorId_0:8,?VendorId_1:8>>,
                        defaultUnicastLocatorList = [?ANY_IPV4_LOCATOR],
                        defaultMulticastLocatorList = [?DEFAULT_MULTICAST_LOCATOR(DomainID)]
                },
        pg:join(Participant#participant.guid, self()),
        {ok,Gate} = rtps_gateway:create(Participant),

        % Receiver set-up
        {ok,Msg_receiver} = rtps_receiver:create(GuidPrefix),
        rtps_receiver:open_unicast_locators(Msg_receiver, Participant#participant.defaultUnicastLocatorList),
        rtps_receiver:open_multicast_locators(Msg_receiver, Participant#participant.defaultMulticastLocatorList),
        %Discovery set-up
        {ok,SPDP_reader} = create_spdp_reader(Participant),
        {ok,SPDP_writer} = create_spdp_writer(Participant),
        rtps_writer:reader_locator_add(SPDP_writer,?DEFAULT_MULTICAST_LOCATOR(DomainID)),
        EndPointSet = ?DISC_BUILTIN_ENDPOINT_PARTICIPANT_ANNOUNCER + ?DISC_BUILTIN_ENDPOINT_PARTICIPANT_DETECTOR,
        
        Change = rtps_writer:new_change(SPDP_writer,produce_SPDP_data(Participant,Msg_receiver,EndPointSet)),
        Writer_cache = rtps_writer:get_cache(SPDP_writer),
        rtps_history_cache:add_change(Writer_cache,Change),

        State = #state{dds_domain_participant = DDS_DP,participant = Participant,spdp_reader = SPDP_reader, spdp_writer = SPDP_writer,  
                        msg_receiver = Msg_receiver, gateway = Gate},

        {ok, State}.


create_spdp_writer(#participant{guid = ID} = Participant) ->
        SPDPwriterConfig = #endPoint{
                guid = #guId{ prefix = ID#guId.prefix, entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER },     
                reliabilityLevel = best_effort,
                topicKind = ?NO_KEY,
                unicastLocatorList = [],
                multicastLocatorList = [?DEFAULT_MULTICAST_LOCATOR(Participant#participant.domainId)]
        },
        {ok,Cache} = rtps_history_cache:new(), 
        rtps_writer:create({Participant, SPDPwriterConfig, Cache}).

create_spdp_reader(#participant{guid = ID} = Participant) ->
        SPDPreaderConfig = #endPoint{
                guid = #guId{ prefix = ID#guId.prefix, entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER },     
                reliabilityLevel = best_effort,
                topicKind = ?NO_KEY,
                unicastLocatorList = [],
                multicastLocatorList = [?DEFAULT_MULTICAST_LOCATOR(Participant#participant.domainId)]
        },
        {ok,Cache} = rtps_history_cache:new(), 
        rtps_reader:create({Participant, SPDPreaderConfig, Cache}).

produce_SPDP_data(#participant{guid = ID}=P, Msg_receiver, EndPointSet) -> 
        Locators = rtps_receiver:get_local_locators(Msg_receiver),
        #spdp_disc_part_data{
                guidPrefix=ID#guId.prefix,
                protocolVersion= P#participant.protocolVersion,
                vendorId= P#participant.vendorId,
                domainId =P#participant.domainId,
                default_uni_locator_l=[ L || {Type,L} <- Locators, Type==unicast],
                default_multi_locato_l=[],
                meta_uni_locator_l=[ L || {Type,L} <- Locators, Type==unicast],
                meta_multi_locator_l= [ L || {Type,L} <- Locators, Type==multicast],
                availableBuiltinEndpoints=EndPointSet,
                leaseDuration=10
        }.
get_info(Pid) -> gen_server:call(Pid,get_info).
get_discovered_participants(Pid) -> gen_server:call(Pid,get_discovered_participants).
set_built_in_endpoints(Pid,EndPointSet) -> gen_server:cast(Pid,{set_built_in_endpoints,EndPointSet}).
start_discovery(Pid) -> gen_server:cast(Pid,start_discovery).
create_full_writer(Pid, Setup, Cache) -> gen_server:call(Pid,{create_full_writer,Setup,Cache}).
create_full_reader(Pid, Setup, Cache) -> gen_server:call(Pid,{create_full_reader,Setup,Cache}).
send_to_all_readers(Pid, Msg) -> gen_server:cast(Pid,{send_to_all_readers,Msg}).

%callbacks 
handle_call(get_info, _, State) -> {reply,State#state.participant,State};
handle_call(get_discovered_participants, _, State) -> {reply,h_get_discovered_participants(State),State};
handle_call({create_full_writer,Setup,Cache}, _, #state{participant=P, writers_list=WL}=S) -> 
        {ok,W} = rtps_full_writer:create({P,Setup,Cache}),
        {reply, W, S#state{writers_list = WL ++ [W] }};
handle_call({create_full_reader,Setup,Cache}, _, #state{participant=P, readers_list=RL}=S) -> 
        {ok,R} = rtps_full_reader:create({P,Setup,Cache}),
        {reply, R, S#state{readers_list = RL ++ [R] }};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({set_built_in_endpoints,EndPointSet}, State) -> h_set_built_in_endpoints(EndPointSet,State), {noreply,State};
handle_cast(start_discovery, State) -> self() ! discovery_loop, {noreply,State};
handle_cast({send_to_all_readers,Msg}, State) -> h_send_to_all_readers(Msg,State), {noreply,State};
handle_cast(_, State) -> {noreply,State}.

handle_info(discovery_loop,#state{dds_domain_participant=DDS,spdp_reader=Reader,spdp_writer=Writer}=State) -> 
        % Check SPDP reader-cache for participants
        Cache = rtps_reader:get_cache(Reader),
        %io:format("Discovered Participants:\n"),
        %[io:format("PREFIX: ~p\n",[W#guId.prefix]) ||  #cacheChange{writerGuid=W} <- rtps_history_cache:get_all_changes(Cache)],
        dds_domain_participant:update_participants_list(DDS,[ D || #cacheChange{data=D} <- rtps_history_cache:get_all_changes(Cache)]),
        % TRIGGER RESEND
        rtps_writer:unsent_changes_reset(Writer),
        erlang:send_after(4000, self(), discovery_loop),
        {noreply,State}.

% Callbacks helpers
% 
h_set_built_in_endpoints(EndPointSet,#state{participant=#participant{guid=#guId{prefix=Prefix}}=P,msg_receiver=Receiver,spdp_writer=Writer}) -> 
        Writer_cache = rtps_writer:get_cache(Writer),
        Change = rtps_writer:new_change(Writer,produce_SPDP_data(P,Receiver,EndPointSet)),
        rtps_history_cache:remove_change(Writer_cache, {#guId{prefix=Prefix,entityId=?ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER},1}),
        rtps_history_cache:add_change(Writer_cache,Change).
h_get_discovered_participants(#state{spdp_reader=Reader}=State) ->
        Cache = rtps_reader:get_cache(Reader),
        [W#guId.prefix ||  #cacheChange{writerGuid=W} <- rtps_history_cache:get_all_changes(Cache)].


h_send_to_all_readers(#heartbeat{}=HB,#state{readers_list=RL}) -> [ rtps_full_reader:receive_heartbeat(R, HB)|| R <- RL ];
h_send_to_all_readers(Data,#state{readers_list=RL}) -> [ rtps_full_reader:receive_data(R, Data) || R <- RL ].