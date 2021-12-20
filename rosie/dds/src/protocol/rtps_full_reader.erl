% Reliable StateFull RTPS reader with WriterProxies, receives heartbits and sends acknacks
-module(rtps_full_reader).

-behaviour(gen_server).

-export([start_link/1, matched_writer_add/2, matched_writer_remove/2,
         update_matched_writers/2, receive_data/2,  receive_gap/2, get_cache/1, receive_heartbeat/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state,
        {participant = #participant{},
         entity = #endPoint{},
         history_cache,
         writer_proxies = [],
         heartbeatResponseDelay = 20, %default should be 500
         heartbeatSuppressionDuration = 0,
         acknack_count = 0}).

%API
start_link({Participant, ReaderConfig}) ->
    State = #state{participant = Participant, entity = ReaderConfig},
    gen_server:start_link(?MODULE, State, []).

get_cache(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_cache).

receive_heartbeat(Pid, HB) when is_pid(Pid) ->
    gen_server:cast(Pid, {receive_heartbeat, HB});
receive_heartbeat(Name, HB) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {receive_heartbeat, HB}).

update_matched_writers(Name, Proxies) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {update_matched_writers, Proxies}).

matched_writer_add(Name, W) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {matched_writer_add, W}).

matched_writer_remove(Name, W) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {matched_writer_remove, W}).

receive_data(Pid, Data) when is_pid(Pid) ->
    gen_server:cast(Pid, {receive_data, Data});
receive_data(Name, Data) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {receive_data, Data}).

receive_gap(Name, Gap) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {receive_gap, Gap}).

% callbacks
init(#state{entity = E} = State) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    pg:join(E#endPoint.guid, self()),
    pg:join(rtps_readers, self()),
    {ok, State#state{history_cache = {cache_of, E#endPoint.guid}}}.

handle_call(get_cache, _, State) ->
    {reply, State#state.history_cache, State};
handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({receive_data, Data}, State) ->
    {noreply, h_receive_data(Data, State)};
handle_cast({receive_gap, Gap}, State) ->
    {noreply, h_receive_gap(Gap, State)};
handle_cast({receive_heartbeat, HB}, State) ->
    {noreply, h_receive_heartbeat(HB, State)};
handle_cast({update_matched_writers, Proxies}, S) ->
    {noreply, h_update_matched_writers(Proxies, S)};
handle_cast({matched_writer_add, Proxy}, S) ->
    {noreply, h_matched_writer_add(Proxy, S)};
handle_cast({matched_writer_remove, R}, S) ->
    {noreply, h_matched_writer_remove(R, S)};
handle_cast(_, State) ->
    {noreply, State}.

handle_info({send_acknack_if_needed, {WGUID, FF}}, State) ->
    {noreply, h_send_acknack_if_needed(WGUID, FF, State)};
handle_info(_, State) ->
    {noreply, State}.

%helpers
data_to_cache_change({Writer, SN, Data}) ->
    #cacheChange{writerGuid = Writer,
                 sequenceNumber = SN,
                 data = Data}.

h_update_matched_writers(Proxies, #state{writer_proxies = WP} = S) ->
    %io:format("Updating with proxy: ~p\n",[Proxies]),
    NewProxies =
        [Proxy
         || #writer_proxy{guid = GUID} = Proxy <- Proxies,
            not lists:member(GUID, [G || #writer_proxy{guid = G} <- WP])],
    S#state{writer_proxies = WP ++ NewProxies}.

h_matched_writer_add(Proxy, #state{writer_proxies = WP} = S) ->
    S#state{writer_proxies = [Proxy | WP]}.

h_matched_writer_remove(Guid, #state{writer_proxies = WP} = S) ->
    S#state{writer_proxies = [P || #writer_proxy{guid = G} = P <- WP, G /= Guid]}.

missing_changes_update(WGUID, Changes, Min, Max) ->
    PresentSN = [SN || #change_from_writer{change_key = {_, SN}} <- Changes],
    NewChanges =
        [#change_from_writer{change_key = {WGUID, SN}, status = missing}
         || SN <- lists:seq(Min, Max), not lists:member(SN, PresentSN)],
    Changes ++ NewChanges.

gen_change_if_not_there(WGUID,LastSN,ToBeMarked) ->
    case lists:member(LastSN, [ SN || #change_from_writer{ change_key = {_, SN}} <- ToBeMarked]) of
        true -> [];
        false -> [#change_from_writer{ change_key = {WGUID, LastSN}}]
    end.

lost_changes_update( WGUID, FirstSN, LastSN, Changes) ->
    {ToBeMarked, Others} = lists:partition(fun(#change_from_writer{ change_key = {_, SN}, status = S}) -> 
                                                ((S == unknown) or (S == missing)) and (SN < FirstSN) 
                                            end,
                                            Changes),
    LastLostChange = case LastSN < FirstSN of 
        true -> gen_change_if_not_there(WGUID,LastSN,ToBeMarked);
        false -> []
    end,
    Others ++ [ C#change_from_writer{ status = lost} || C <- ToBeMarked ++ LastLostChange].

manage_heartbeat_for_writer(#heartbeat{writerGUID = WGUID,
                                       final_flag = FF,
                                       min_sn = Min,
                                       max_sn = Max},
                            #writer_proxy{changes_from_writer = Changes} = W,
                            #state{writer_proxies = WP, heartbeatResponseDelay = Delay} = S) ->
    %io:format("~p\n",[WGUID]),
    Others = [P || #writer_proxy{guid = G} = P <- WP, G /= WGUID],
    NewChangeList = missing_changes_update(WGUID, Changes, Min, Max),
    Check2 = lost_changes_update(WGUID, Min, Max, NewChangeList),
    erlang:send_after(Delay, self(), {send_acknack_if_needed, {WGUID, FF}}),
    S#state{writer_proxies = Others ++ [W#writer_proxy{changes_from_writer = Check2}]}.

h_receive_heartbeat(#heartbeat{writerGUID = WGUID,
                               min_sn = Min,
                               max_sn = Max} =
                        HB,
                    #state{writer_proxies = Proxies} = S) ->
    case [WP || #writer_proxy{guid = WPG} = WP <- Proxies, WPG == WGUID] of
        [] ->
            S;
        [W | _] ->
            manage_heartbeat_for_writer(HB, W, S)
    end.

filter_missing_sn(ChangeList) ->
    [SN || #change_from_writer{change_key = {_, SN}, status = S} <- ChangeList, S == missing].

available_change_max([]) ->
    0;
available_change_max(ChangeList) ->
    lists:max([SN || #change_from_writer{change_key = {_, SN}} <- ChangeList]).

% 0 means flag not set, an acknowledgment must be sent
h_send_acknack_if_needed(WGUID, 0, #state{writer_proxies = WP} = S) ->
    case [P || #writer_proxy{guid = G} = P <- WP, G == WGUID] of
        [P | _] ->
            case filter_missing_sn(P#writer_proxy.changes_from_writer) of
                [] ->
                    Missing = available_change_max(P#writer_proxy.changes_from_writer) + 1;
                List ->
                    Missing = List
            end,
            send_acknack(WGUID, Missing, S);
        [] ->
            S
    end;
% 1 means flag set, i acknoledge only if i know to miss some data
h_send_acknack_if_needed(WGUID, 1, #state{writer_proxies = WP} = S) ->
    case [P || #writer_proxy{guid = G} = P <- WP, G == WGUID] of
        [P | _] ->
            case filter_missing_sn(P#writer_proxy.changes_from_writer) of
                [] ->
                    S;
                List ->
                    send_acknack(WGUID, List, S)
            end;
        [] ->
            S
    end.

send_acknack(WGUID,
             Missing,
             #state{entity = #endPoint{guid = RGUID},
                    writer_proxies = WP,
                    acknack_count = C} =
                 S) ->
    %io:format("Sending an ack nack for ~p, to ~p\n", [Missing, WGUID#guId.entityId]),
    %io:format("Proxies are: ~p\n",[[ P || #writer_proxy{guid=G}=P <- WP, G == WGUID]]),
    [[L | _] | _] =
        [U_List
         || #writer_proxy{guid = GUID, unicastLocatorList = U_List} = P <- WP, GUID == WGUID],
    ACKNACK =
        #acknack{writerGUID = WGUID,
                 readerGUID = RGUID,
                 final_flag = 1,
                 sn_range = Missing,
                 count = C},
    Datagram =
        rtps_messages:build_message(RGUID#guId.prefix,
                                    [rtps_messages:serialize_info_dst(WGUID#guId.prefix),
                                     rtps_messages:serialize_acknack(ACKNACK)]),
    [G | _] = pg:get_members(rtps_gateway),
    rtps_gateway:send(G, {Datagram, {L#locator.ip, L#locator.port}}),
    S#state{acknack_count = C + 1}.

is_in_change_list(CFW, SN) ->
    case [C || #change_from_writer{change_key = {_, WSN}} = C <- CFW, SN == WSN] of
        [] ->
            false;
        _ ->
            true
    end.

add_change_from_writer_if_needed(WGUID, CFW, SN) ->
    case is_in_change_list(CFW, SN) of
        true ->
            CFW;
        false ->
            CFW ++ [#change_from_writer{change_key = {WGUID, SN}, status = missing}]
    end.

sn_received(#change_from_writer{change_key = {WGUID, SN}, status = S} = C, ReceivedSN)
    when SN == ReceivedSN ->
    C#change_from_writer{status = received};
sn_received(C, _) ->
    C.

h_receive_data({Writer, SN, Data},
               #state{history_cache = Cache, writer_proxies = WP} = State) ->
    case [P || #writer_proxy{guid = WGUID} = P <- WP, WGUID == Writer] of
        [] ->
            State;
        [Proxy | _] ->
            rtps_history_cache:add_change(Cache, data_to_cache_change({Writer, SN, Data})),
            Others = [P || #writer_proxy{guid = WGUID} = P <- WP, WGUID /= Writer],
            _CFW =
                add_change_from_writer_if_needed(Proxy#writer_proxy.guid,
                                                 Proxy#writer_proxy.changes_from_writer,
                                                 SN),
            CFW = lists:map(fun(Change) -> sn_received(Change, SN) end, _CFW),
            State#state{writer_proxies = Others ++ [Proxy#writer_proxy{changes_from_writer = CFW}]}
    end.

h_receive_gap(#gap{writerGUID = Writer, sn_set = SET},
               #state{history_cache = Cache, writer_proxies = WP} = State) -> 
    case [P || #writer_proxy{guid = WGUID} = P <- WP, WGUID == Writer] of
        [] -> 
            State;
        [Selected | _] ->
            %io:format("GAP processing...for numbers ~p\n", [SET]),
            %DEBUG_SN_STATES = [ {SN,S} || #change_from_writer{change_key = {_,SN}, status = S} <- Selected#writer_proxy.changes_from_writer],
            %io:format("Current changes state ~p\n", [DEBUG_SN_STATES]),
            Others = [P || #writer_proxy{guid = WGUID} = P <- WP, WGUID /= Writer],
            AddedChanges = lists:foldl(
                fun (SN, CFW) -> 
                        add_change_from_writer_if_needed(Selected#writer_proxy.guid,
                                    CFW,
                                    SN)
                end,  
                Selected#writer_proxy.changes_from_writer, 
                SET),

            AddedAndMarked = lists:map(fun(#change_from_writer{change_key = {_, SN}} = C) -> 
                                            case lists:member(SN, SET) of
                                                true -> C#change_from_writer{status = received};
                                                false -> C
                                            end
                                        end, AddedChanges),
            State#state{writer_proxies = Others ++ [Selected#writer_proxy{changes_from_writer = AddedAndMarked}]}
    end.