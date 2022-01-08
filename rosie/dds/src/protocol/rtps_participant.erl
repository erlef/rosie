% This module contains the participant implementation with SPDPwriter and SDPDreader.
-module(rtps_participant).

-behaviour(gen_server).

-export([start_link/0, get_spdp_writer_config/1, get_spdp_reader_config/1,
         send_to_all_readers/2, get_discovered_participants/1, get_info/1, start_discovery/2,
         on_change_available/2, on_change_removed/2, stop_discovery/1, stop_receiver/1]).
%set_built_in_endpoints/2,
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

-record(state,
        {participant = #participant{}, spdp_writer_guid, spdp_reader_guid}).

start_link() ->
    gen_server:start_link({local, participant}, ?MODULE, #state{}, []).

get_spdp_writer_config(Pid) ->
    gen_server:call(Pid, get_spdp_writer_config).

get_spdp_reader_config(Pid) ->
    gen_server:call(Pid, get_spdp_reader_config).

get_info(Pid) ->
    gen_server:call(Pid, get_info).

get_discovered_participants(Pid) ->
    gen_server:call(Pid, get_discovered_participants).

start_discovery(Pid, EndPointSet) ->
    gen_server:cast(Pid, {start_discovery, EndPointSet}).

stop_discovery(Pid) ->
    gen_server:call(Pid, stop_discovery).

stop_receiver(Pid) ->
    gen_server:call(Pid, stop_receiver).

send_to_all_readers(Pid, Msg) ->
    gen_server:cast(Pid, {send_to_all_readers, Msg}).

on_change_available(Pid, Msg) ->
    gen_server:cast(Pid, {on_change_available, Msg}).

on_change_removed(Pid, ChangeKey) ->
    %ignored
    ok.

%callbacks

init(S) ->
    DomainID = 0,
    GuidPrefix = <<?VendorId_0:8, ?VendorId_1:8, (crypto:strong_rand_bytes(10))/binary>>,
    Participant =
        #participant{guid = #guId{prefix = GuidPrefix, entityId = ?ENTITYID_PARTICIPANT},
                     domainId = DomainID,
                     protocolVersion = <<?V_MAJOR, ?V_MINOR>>,
                     vendorId = <<?VendorId_0:8, ?VendorId_1:8>>,
                     defaultUnicastLocatorList = [?ANY_IPV4_LOCATOR],
                     defaultMulticastLocatorList = [?DEFAULT_MULTICAST_LOCATOR(DomainID)]},
    pg:join(Participant#participant.guid, self()),

    State =
        #state{participant = Participant,
               spdp_reader_guid =
                   #guId{prefix = GuidPrefix, entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER},
               spdp_writer_guid =
                   #guId{prefix = GuidPrefix,
                         entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER}},
    {ok, State}.

handle_call(get_spdp_writer_config, _, State) ->
    {reply, h_get_spdp_writer_config(State#state.participant), State};
handle_call(get_spdp_reader_config, _, State) ->
    {reply, h_get_spdp_reader_config(State#state.participant), State};
handle_call(get_info, _, State) ->
    {reply, State#state.participant, State};
handle_call(get_discovered_participants, _, State) ->
    {reply, h_get_discovered_participants(State), State};
handle_call(stop_discovery, _, State) ->
    {reply, h_stop_discovery(State), State};
handle_call(stop_receiver, _, #state{ participant = #participant{guid = ID}} = S) ->
    {reply, rtps_receiver:stop({receiver_of,ID#guId.prefix}), S};
handle_call(_, _, State) ->
    {reply, ok, State}.

% handle_cast({set_built_in_endpoints,EndPointSet}, State) ->
%         h_set_built_in_endpoints(EndPointSet,State), {noreply,State};
handle_cast({start_discovery, EndPointSet},
            #state{participant = P,
                   spdp_reader_guid = R_GUID,
                   spdp_writer_guid = W_GUID} =
                State) ->
    % %Discovery set-up
    rtps_writer:reader_locator_add(W_GUID,
                                   ?DEFAULT_MULTICAST_LOCATOR(P#participant.domainId)),
    Change = rtps_writer:new_change(W_GUID, produce_SPDP_data(P, EndPointSet)),
    rtps_history_cache:add_change({cache_of, W_GUID}, Change),

    rtps_history_cache:set_listener({cache_of, R_GUID}, { ?MODULE, participant}),
    self() ! discovery_loop,
    {noreply, State};
handle_cast({send_to_all_readers, Msg}, State) ->
    h_send_to_all_readers(Msg),
    {noreply, State};
handle_cast({on_change_available, _}, #state{spdp_reader_guid = R_GUID, spdp_writer_guid = W_GUID} = State) ->
    %io:format("P data!\n"),
    CacheContent = rtps_history_cache:get_all_changes({cache_of, R_GUID}),
    LEAVING = [ {WGUID,D} || #cacheChange{writerGuid = WGUID, data = #spdp_disc_part_data{status_qos = S} = D} <- CacheContent, ?ENDPOINT_LEAVING(S)],
    {LEAVING_GUIDS , LEAVING_DATA} = lists:unzip(LEAVING),
    
    [rtps_history_cache:remove_change({cache_of, R_GUID}, {WGUID, SN})
     || #cacheChange{writerGuid = WGUID, sequenceNumber = SN} <- CacheContent,
        lists:member(WGUID, LEAVING_GUIDS)],
    % clear unicast locators of the participants who left
    % InvalidLocators = lists:flatten([ L || #spdp_disc_part_data{default_uni_locator_l=L} <- LEAVING_DATA]),
    % [rtps_writer:reader_locator_remove(W_GUID,L) || L <- InvalidLocators],

    % the cache is updated, all changes are valid
    ValidParticipants = [ D|| #cacheChange{data = D} <- rtps_history_cache:get_all_changes({cache_of, R_GUID})],
    dds_domain_participant:update_participants_list(dds, ValidParticipants),
    % make sure unicast locators are added to SPDP writer, in case multicast sending is not enough
    % ValidLocators = lists:flatten([L || #spdp_disc_part_data{default_uni_locator_l=L} <- ValidParticipants]),
    % [rtps_writer:reader_locator_add(W_GUID,L) || L <- ValidLocators],
    {noreply, State};
handle_cast(_, State) ->
    {noreply, State}.

handle_info(discovery_loop,
            #state{spdp_reader_guid = R_GUID, spdp_writer_guid = W_GUID} = State) ->
    % TRIGGER RESEND
    rtps_writer:unsent_changes_reset(W_GUID),
    erlang:send_after(4000, self(), discovery_loop),
    {noreply, State}.

% Callbacks helpers
%
h_stop_discovery(#state{participant = P, spdp_writer_guid = W_GUID}) ->
    rtps_history_cache:remove_change({cache_of, W_GUID}, {W_GUID, 1}),
    Change = rtps_writer:new_change(W_GUID, produce_spdp_participant_leaving(P)),
    rtps_history_cache:add_change({cache_of, W_GUID}, Change),
    rtps_writer:flush_all_changes(W_GUID).

h_get_discovered_participants(#state{spdp_reader_guid = R_GUID} = State) ->
    [D || #cacheChange{data = D} <- rtps_history_cache:get_all_changes({cache_of, R_GUID})].

h_send_to_all_readers(#heartbeat{} = HB) ->
    [rtps_full_reader:receive_heartbeat(R, HB) || R <- pg:get_local_members(rtps_readers)];
h_send_to_all_readers(Data) ->
    [rtps_full_reader:receive_data(R, Data) || R <- pg:get_local_members(rtps_readers)].

h_get_spdp_writer_config(#participant{guid = ID} = Participant) ->
    #endPoint{guid =
                  #guId{prefix = ID#guId.prefix,
                        entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER},
              reliabilityLevel = best_effort,
              topicKind = ?NO_KEY,
              unicastLocatorList = [],
              multicastLocatorList =
                  [?DEFAULT_MULTICAST_LOCATOR(Participant#participant.domainId)]}.

h_get_spdp_reader_config(#participant{guid = ID} = Participant) ->
    #endPoint{guid =
                  #guId{prefix = ID#guId.prefix,
                        entityId = ?ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER},
              reliabilityLevel = best_effort,
              topicKind = ?NO_KEY,
              unicastLocatorList = [],
              multicastLocatorList =
                  [?DEFAULT_MULTICAST_LOCATOR(Participant#participant.domainId)]}.

produce_SPDP_data(#participant{guid = ID} = P, EndPointSet) ->
    Locators = rtps_receiver:get_local_locators({receiver_of, ID#guId.prefix}),
    #spdp_disc_part_data{guidPrefix = ID#guId.prefix,
                         protocolVersion = P#participant.protocolVersion,
                         vendorId = P#participant.vendorId,
                         domainId = P#participant.domainId,
                         default_uni_locator_l = [L || {Type, L} <- Locators, Type == unicast],
                         default_multi_locator_l = [],
                         meta_uni_locator_l = [L || {Type, L} <- Locators, Type == unicast],
                         meta_multi_locator_l = [L || {Type, L} <- Locators, Type == multicast],
                         availableBuiltinEndpoints = EndPointSet,
                         leaseDuration = 10}.

produce_spdp_participant_leaving(#participant{guid = G}) ->
    #spdp_participant_state{guid = G,
                            status_flags = ?STATUS_INFO_UNREGISTERED + ?STATUS_INFO_DISPOSED}.
