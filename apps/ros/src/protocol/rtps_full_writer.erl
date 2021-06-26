% Realiable statefull writer, it manages Reader-proxies sends heatbeats and receives acknacks
-module(rtps_full_writer).

-behaviour(gen_server).

-export([create/1,on_change_available/2,new_change/2,get_cache/1,update_matched_readers/2,
        matched_reader_add/2,matched_reader_remove/2,is_acked_by_all/1,receive_acknack/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include("rtps_structure.hrl").
-include("rtps_constants.hrl").

-record(state,{
        participant = #participant{},
        entity = #endPoint{},
        datawrite_period= 1000, % default at 1000
        heatbeat_period= 1000, % default at 1000
        heatbeat_count= 1,
        nackResponseDelay= 200, % default at 200
        nackSuppressionDuration= 0,
        push_mode = false,
        history_cache,
        reader_proxies=[],
        last_sequence_number = 0
}).
%API
create({Participant,WriterConfig, Cache}) -> gen_server:start_link(?MODULE, {Participant,WriterConfig, Cache},[]).

new_change(Pid,Data) -> gen_server:call(Pid,{new_change,Data}).
on_change_available(Pid, ChangeKey) -> gen_server:cast(Pid, {on_change_available, ChangeKey}).
%Adds new locators if missing, removes old locators not specified in the call.
update_matched_readers(Pid, R) -> gen_server:cast(Pid, {update_matched_readers, R}).
matched_reader_add(Pid, R) -> gen_server:cast(Pid, {matched_reader_add, R}).
matched_reader_remove(Pid, R)-> gen_server:cast(Pid, {matched_reader_remove, R}).
is_acked_by_all(Pid) -> gen_server:call(Pid, is_acked_by_all).
receive_acknack(Pid, Acknack) -> gen_server:cast(Pid, {receive_acknack, Acknack}).
get_cache(Pid) -> gen_server:call(Pid,get_cache).

% callbacks
init({Participant,#endPoint{guid=GUID}=WriterConfig, Cache}) -> 
        State = #state{participant = Participant, entity = WriterConfig, history_cache = Cache},
        rtps_history_cache:set_listener(Cache, {self(),?MODULE}),
        pg:join(GUID, self()),
        erlang:send_after(100,self(),heartbeat_loop),
        erlang:send_after(200,self(),write_loop),
        {ok,State}.
terminate(_,_) -> io:format("I FULL WRITER DIED\n").

handle_call({new_change,Data}, _, State) ->  
        {Change, NewState} = h_new_change(Data, State),
        {reply, Change, NewState};
handle_call(get_cache, _, State) -> {reply,State#state.history_cache,State};
handle_call(is_acked_by_all, _, State) -> {reply,h_is_acked_by_all(State),State};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({on_change_available, ChangeKey},S) -> {noreply, h_on_change_available(ChangeKey,S)};
handle_cast({update_matched_readers, Proxies}, State) -> {noreply,h_update_matched_readers(Proxies,State)};
handle_cast({matched_reader_add,Proxy}, State) -> {noreply,h_matched_reader_add(Proxy,State)};
handle_cast({matched_reader_remove,Guid}, State) -> {noreply,h_matched_reader_remove(Guid,State)};
handle_cast({receive_acknack, Acknack}, State) -> {noreply, h_receive_acknack(Acknack,State)};
handle_cast(_, State) -> {noreply,State}.

handle_info(heartbeat_loop,State) -> {noreply,heartbeat_loop(State)};
handle_info(write_loop,State) -> {noreply,write_loop(State)}.


%callback helpers
% 
% send_locators_changes(#state{reader_proxies=RLs}=S) -> send_locators_changes(S,RLs,[]).
% send_locators_changes(S,[],New_RL) -> S#state{reader_proxies=New_RL};
% send_locators_changes(#state{participant=P,entity=E}=S,[#reader_locator{guid_prefix=Prefix,locator=L,unsent_changes=Changes}=RL|TL], New_RL) -> 
%         % prepare ordered datasubmsg in binary and send them 
%         %io:format("~p\n",[Prefix]),
%         case Prefix of undefined -> DST=[]; _ -> DST = [rtps_messages:serialize_info_dst(Prefix)] end,
%         SUB_MSG_LIST =  DST ++ [rtps_messages:serialize_info_timestamp()]++
%                         [rtps_messages:serialize_data(C) || C  <- Changes],
%         Datagram = rtps_messages:build_message(P#participant.guid#guId.prefix, SUB_MSG_LIST),
%         [G|_] = pg:get_members(rtps_gateway),
%         rtps_gateway:send(G, {Datagram,{L#locator.ip,L#locator.port}}),
%         send_locators_changes(S,TL, [RL#reader_locator{unsent_changes=[]} | New_RL]).
send_to_heatbeat_to_readers(_,_,[]) -> ok;
send_to_heatbeat_to_readers(GuidPrefix, HB, [#reader_proxy{ unacked_changes = []} | TL]) ->
        send_to_heatbeat_to_readers(GuidPrefix, HB, TL);
send_to_heatbeat_to_readers(GuidPrefix, HB, [#reader_proxy{guid = ReaderGUID,unicastLocatorList=[L|_]} | TL]) -> 
        [G|_] = pg:get_members(rtps_gateway),
        SUB_MSG_LIST = [rtps_messages:serialize_heatbeat(HB#heartbeat{readerGUID=ReaderGUID})],
        Datagram = rtps_messages:build_message(GuidPrefix, SUB_MSG_LIST),
        rtps_gateway:send(G, {Datagram,{L#locator.ip,L#locator.port}}),
        send_to_heatbeat_to_readers(GuidPrefix, HB, TL).
send_heatbeat(#state{entity=#endPoint{guid=GUID}, history_cache=C, heatbeat_count=Count,reader_proxies=RP}) -> 
        MinSN = rtps_history_cache:get_min_seq_num(C),
        MaxSN = rtps_history_cache:get_max_seq_num(C),
        HB = #heartbeat{
                writerGUID = GUID,
                min_sn = MinSN,
                max_sn = MaxSN,
                count = Count,
                final_flag = 1,
                readerGUID= ?GUID_UNKNOWN
        },
        send_to_heatbeat_to_readers(GUID#guId.prefix,HB,RP).

heartbeat_loop(#state{heatbeat_period=HP,heatbeat_count=C}=S) -> 
        send_heatbeat(S),
        erlang:send_after(1000, self(), heartbeat_loop),
        S#state{heatbeat_count=C+1}.

send_requested_changes(Prefix,RP) -> send_requested_changes(Prefix,RP,[]).
send_requested_changes(Prefix,[],Sent) -> Sent;
send_requested_changes(Prefix,[#reader_proxy{requested_changes=[]}=P|TL], Sent) -> 
        send_requested_changes(Prefix, TL, Sent ++ [P] );
send_requested_changes(Prefix,[#reader_proxy{guid=#guId{entityId=RID},unicastLocatorList=[L|_], requested_changes=RC}=P|TL], Sent) -> 
        [G|_] = pg:get_members(rtps_gateway),
        SUB_MSG = [rtps_messages:serialize_info_timestamp()] ++ [ rtps_messages:serialize_data(RID,C) || C <- RC ],
        Msg = rtps_messages:build_message(Prefix, SUB_MSG),
        rtps_gateway:send(G,{ Msg,{L#locator.ip, L#locator.port}}),
        send_requested_changes(Prefix, TL, Sent ++ [P#reader_proxy{requested_changes=[]}]).
write_loop(#state{entity=#endPoint{guid=#guId{prefix=Prefix}},datawrite_period=P,reader_proxies=RP} = S) ->
        erlang:send_after(P, self(), write_loop),
        S#state{reader_proxies = send_requested_changes(Prefix,RP)}.

h_new_change(D,#state{last_sequence_number=Last_SN,entity=E,history_cache=C}=S) -> 
        SN = Last_SN + 1,
        Change = #cacheChange{kind=alive,writerGuid=E#endPoint.guid,
                instanceHandle=0,sequenceNumber=SN, data = D},
        {Change, S#state{last_sequence_number=SN}}.

h_update_matched_readers(Proxies,#state{reader_proxies=RP, history_cache=C} = S) ->  
        Valid_GUIDS = [ G || #reader_proxy{guid=G} <- Proxies],
        ProxyStillValid = [ Proxy || #reader_proxy{guid=G}=Proxy <- RP, lists:member(G, Valid_GUIDS) ],
        NewProxies = [Proxy || #reader_proxy{guid=G}=Proxy <- Proxies, not lists:member(G,[ G || #reader_proxy{guid=G} <- RP])],
        % add cache changes to the unsent list for the new added locators
        Changes = rtps_history_cache:get_all_changes(C),
        S#state{reader_proxies= ProxyStillValid ++ reset_reader_proxies(Changes,NewProxies)}.

h_matched_reader_add(Proxy,#state{reader_proxies=RP, history_cache=C} = S) -> 
        Changes = rtps_history_cache:get_all_changes(C),
        S#state{reader_proxies=RP++reset_reader_proxies(Changes,[Proxy])}.

h_matched_reader_remove(Guid,#state{reader_proxies=RP} = S) -> 
        S#state{reader_proxies=[ P || #reader_proxy{guid=G}=P <- RP, G /= Guid]}.

reset_reader_proxies(Changes,RP) -> reset_reader_proxies(Changes,RP,[]).
reset_reader_proxies(_,[],NewRP) -> NewRP;
reset_reader_proxies(Changes,[RP| TL],NewProxies) ->  
        N_RP = RP#reader_proxy{requested_changes=[],unacked_changes=Changes,unsent_changes=[]},
        reset_reader_proxies(Changes, TL, [N_RP|NewProxies]).

h_is_acked_by_all(_) -> false.
add_change_to_proxies(Change,Proxies) -> add_change_to_proxies(Change,Proxies,[]).
add_change_to_proxies(_,[],NewPR) -> NewPR;
add_change_to_proxies(Change,[Proxy| TL],NewProxies) ->  
        ChangeList = Proxy#reader_proxy.unacked_changes ++ [Change],
        New_PR = Proxy#reader_proxy{unacked_changes=ChangeList},
        add_change_to_proxies(Change, TL, [New_PR|NewProxies]).

h_on_change_available(Key,#state{history_cache=C,reader_proxies=RP, push_mode=Push}=S) when Push == false -> 
        S#state{reader_proxies = add_change_to_proxies(rtps_history_cache:get_change(C, Key), RP)}.

update_for_acknack([], _, L, S) -> S;
update_for_acknack([#reader_proxy{unacked_changes=UC}=Proxy|_], Others, L, #state{reader_proxies=RP,history_cache=Cache} = S) -> 
        Changes = rtps_history_cache:get_all_changes(Cache),
        Requested = [ C || #cacheChange{sequenceNumber=SN}=C <- Changes , lists:member(SN,L) ],
        Unacked = [ C || #cacheChange{sequenceNumber=SN}=C <- Changes , SN >= lists:min(L) ],
        S#state{reader_proxies = Others ++ [Proxy#reader_proxy{requested_changes = Requested, unacked_changes = Unacked}]}.
h_receive_acknack(_,#state{reader_proxies=[]} = S) -> S;
h_receive_acknack(#acknack{readerGUID=RID,sn_range=Single},#state{reader_proxies=RP,history_cache=Cache} = S)
        when is_integer(Single) ->
        Others = [ P || #reader_proxy{guid=G}=P <- RP, G /= RID],
        update_for_acknack([ P || #reader_proxy{guid=G}=P <- RP, G == RID], Others, [Single], S);
h_receive_acknack(#acknack{readerGUID=RID,sn_range=Range},#state{reader_proxies=RP,history_cache=Cache} = S) ->
        Others = [ P || #reader_proxy{guid=G}=P <- RP, G /= RID],
        update_for_acknack([ P || #reader_proxy{guid=G}=P <- RP, G == RID], Others, Range, S).
