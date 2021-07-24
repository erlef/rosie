% Reliable StateFull RTPS reader with WriterProxies, receives heartbits and sends acknacks
-module(rtps_full_reader).

-behaviour(gen_server).

-export([start_link/1,update_matched_writers/2,receive_data/2,get_cache/1,receive_heartbeat/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state,{
        participant = #participant{},
        entity = #endPoint{},
        history_cache,
        writer_proxies = [],
        heartbeatResponseDelay = 10, %default should be 500
        heartbeatSuppressionDuration = 0,
        acknack_count = 0
}).
%API
start_link({Participant,ReaderConfig}) -> 
        State = #state{participant = Participant, entity = ReaderConfig},
        gen_server:start_link(?MODULE, State,[]).

get_cache(Name) ->         
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,get_cache).

receive_heartbeat(Pid,HB) when is_pid(Pid) ->
        gen_server:cast(Pid, {receive_heartbeat, HB});
receive_heartbeat(Name,HB) ->         
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {receive_heartbeat, HB}).

update_matched_writers(Name,Proxies) ->        
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{update_matched_writers, Proxies}).

receive_data(Pid,Data) when is_pid(Pid) ->     
        gen_server:cast(Pid,{receive_data,Data});
receive_data(Name,Data) ->        
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{receive_data,Data}).
% callbacks
init(#state{entity=E} = State) -> 
        %io:format("~p.erl STARTED!\n",[?MODULE]), 
        pg:join(E#endPoint.guid, self()), 
        pg:join(rtps_readers, self()),
        {ok,State#state{history_cache={cache_of,E#endPoint.guid}}}.


handle_call(get_cache, _, State) -> {reply,State#state.history_cache,State};
handle_call(_, _, State) -> {reply,ok,State}.


handle_cast({receive_data, Data}, State) -> {noreply,h_receive_data(Data,State)};
handle_cast({receive_heartbeat, HB}, State) ->  {noreply,h_receive_heartbeat(HB,State)};
handle_cast({update_matched_writers, Proxies}, S) -> {noreply,h_update_matched_writers(Proxies, S)};
handle_cast(_, State) -> {noreply,State}.

handle_info({send_acknack_if_needed,{WGUID, FF}},State) ->  {noreply,h_send_acknack_if_needed(WGUID,FF,State)};
handle_info(_,State) -> {noreply,State}.

%helpers
data_to_cache_change({Writer,SN,Data}) -> #cacheChange{writerGuid = Writer,sequenceNumber=SN, data = Data}.

h_update_matched_writers(Proxies,#state{writer_proxies=WP}=S) -> 
        %io:format("Updating with proxy: ~p\n",[Proxies]),
        NewProxies = [Proxy || #writer_proxy{guid=GUID}=Proxy <- Proxies, not lists:member(GUID,[ G || #writer_proxy{guid=G} <- WP])],
        S#state{writer_proxies = WP ++ NewProxies}.


missing_changes_update(WGUID,C,Min,Max) -> 
        PresentSN = [ SN || #change_from_writer{change_key={_,SN}} <- C],
        NewChanges = [ #change_from_writer{change_key={WGUID,SN},status=missing} || SN <- lists:seq(Min, Max), not lists:member(SN, PresentSN)],
        NewChangeList = C ++ NewChanges.

lost_change_update(#change_from_writer{change_key={_,SN},status=S}=C,FirstSN) 
        when ((S == unknown) or (S == missing)) and SN < FirstSN -> C#change_from_writer{status = lost};
lost_change_update(#change_from_writer{change_key={_,_},status=_}=C,FirstSN) -> C.
manage_heartbeat_for_writer(#heartbeat{writerGUID = WGUID, final_flag = FF, min_sn=Min,max_sn=Max},
                        #writer_proxy{changes_from_writer=C}=W,
                        #state{writer_proxies = WP, heartbeatResponseDelay = Delay}=S) ->
        %io:format("~p\n",[WGUID]),
        Others = [ P || #writer_proxy{guid=G}=P <- WP, G /= WGUID],
        NewChangeList = missing_changes_update(WGUID,C,Min,Max),
        Check2 = lists:map(fun (Elem) -> lost_change_update(Elem,Min) end, NewChangeList),
        erlang:send_after(Delay, self(), {send_acknack_if_needed,{WGUID, FF}}),
        S#state{writer_proxies = Others ++ [W#writer_proxy{changes_from_writer=Check2}]}.
h_receive_heartbeat(#heartbeat{writerGUID=WGUID,min_sn=Min,max_sn=Max}=HB,#state{writer_proxies=Proxies}=S) -> 
        case [ WP || #writer_proxy{guid=WPG}=WP <- Proxies, WPG == WGUID ] of
                [] -> S;
                [W|_] ->  manage_heartbeat_for_writer(HB,W,S) 
        end.

filter_missing_sn(ChangeList) -> [ SN || #change_from_writer{change_key={_,SN},status=S} <- ChangeList, S == missing].
available_change_max([]) -> 0;
available_change_max(ChangeList) -> lists:max([ SN || #change_from_writer{change_key={_,SN}} <- ChangeList]).
% 0 means flag not set, an acknowledgment must be sent
h_send_acknack_if_needed(WGUID, 0, #state{writer_proxies = WP}=S) -> 
        [P|_] = [ P || #writer_proxy{guid=G}=P <- WP, G == WGUID],
        case filter_missing_sn(P#writer_proxy.changes_from_writer) of 
                [] -> Missing = available_change_max(P#writer_proxy.changes_from_writer) + 1;
                List -> Missing = List
        end,
        send_acknack( WGUID, Missing, S);
% 1 means flag set, i acknoledge only if i know to miss some data
h_send_acknack_if_needed(WGUID, 1, #state{writer_proxies = WP}=S) -> 
        [P|_] = [ P || #writer_proxy{guid=G}=P <- WP, G == WGUID],
        case filter_missing_sn(P#writer_proxy.changes_from_writer) of 
                [] -> S;
                List -> send_acknack( WGUID, List, S)
        end.

send_acknack(WGUID,Missing,#state{entity=#endPoint{guid=RGUID},writer_proxies=WP,acknack_count=C}=S) -> 
        %io:format("Sending an ack nack for ~p, to ~p\n", [Missing, WGUID#guId.entityId]),
        %io:format("Proxies are: ~p\n",[[ P || #writer_proxy{guid=G}=P <- WP, G == WGUID]]),
        [[L|_]|_] = [ U_List || #writer_proxy{guid=GUID,unicastLocatorList=U_List}=P <- WP, GUID == WGUID],
        ACKNACK = #acknack{writerGUID=WGUID,readerGUID=RGUID,
                                final_flag = 1, sn_range = Missing, count = C },
        Datagram = rtps_messages:build_message(RGUID#guId.prefix,[rtps_messages:serialize_info_dst(WGUID#guId.prefix),rtps_messages:serialize_acknack(ACKNACK)]),
        [G|_] = pg:get_members(rtps_gateway),
        rtps_gateway:send(G,{ Datagram,{L#locator.ip, L#locator.port}}),
        S#state{acknack_count = C + 1}.


is_in_change_list(CFW,SN) -> 
        case [C || #change_from_writer{change_key={_,WSN}}=C <- CFW, SN == WSN] of
                [] -> false;
                _ -> true
        end.
add_change_from_writer_if_needed(WGUID,CFW,SN) ->
        case is_in_change_list(CFW,SN) of
                true -> CFW;
                false -> CFW ++ [#change_from_writer{change_key={WGUID,SN},status=missing}]
        end.                
sn_received(#change_from_writer{change_key={WGUID,SN},status=S}=C,ReceivedSN) 
        when SN == ReceivedSN -> C#change_from_writer{status = received};
sn_received(C,_) -> C.
h_receive_data({Writer,SN,Data}, #state{history_cache=Cache, writer_proxies=WP} = State) -> 
        case [P || #writer_proxy{guid=WGUID}=P <- WP, WGUID == Writer] of
                [] -> State;
                [Proxy|_] ->
                        rtps_history_cache:add_change(Cache, data_to_cache_change({Writer,SN,Data})), 
                        Others = [P || #writer_proxy{guid=WGUID}=P <- WP, WGUID /= Writer],
                        _CFW = add_change_from_writer_if_needed(Proxy#writer_proxy.guid, Proxy#writer_proxy.changes_from_writer,SN),
                        CFW = lists:map(fun (Change) -> sn_received(Change,SN) end, _CFW),
                        State#state{writer_proxies = Others ++ [Proxy#writer_proxy{changes_from_writer=CFW}]}
        end.