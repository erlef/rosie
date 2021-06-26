% Best-effort Stateless RTPS writer, just remembers the reader locators.
-module(rtps_writer).

-behaviour(gen_server).

-export([create/1,on_change_available/2,new_change/2,get_cache/1,update_reader_locator_list/2,reader_locator_add/2,reader_locator_remove/2,unsent_changes_reset/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include("rtps_structure.hrl").
-include("rtps_constants.hrl").

-record(state,{
        participant = #participant{},
        entity = #endPoint{},
        resendPeriod=8,
        history_cache,
        reader_locators=[],
        last_sequence_number = 0
}).
%API
create({Participant,WriterConfig, Cache}) -> gen_server:start_link(?MODULE, {Participant,WriterConfig, Cache},[]).

new_change(Pid,Data) -> gen_server:call(Pid,{new_change,Data}).
on_change_available(Pid, ChangeKey) -> gen_server:cast(Pid, {on_change_available, ChangeKey}).
%Adds new locators if missing, removes old locators not specified in the call.
update_reader_locator_list(Pid, RL) -> gen_server:cast(Pid, {update_reader_locator_list, RL}).
reader_locator_add(Pid,Locator) -> gen_server:cast(Pid, {reader_locator_add,Locator}).
reader_locator_remove(Pid,Locator)-> gen_server:cast(Pid, {reader_locator_remove,Locator}).
unsent_changes_reset(Pid) -> gen_server:cast(Pid, unsent_changes_reset).

get_cache(Pid) -> gen_server:call(Pid,get_cache).

% callbacks
init({Participant,#endPoint{guid=GUID}=WriterConfig, Cache}) -> 
        State = #state{participant = Participant, entity = WriterConfig, history_cache = Cache},
        rtps_history_cache:set_listener(Cache, {self(),?MODULE}),
        pg:join(GUID, self()),
        erlang:send_after(1000,self(),writer_loop),
        {ok,State}.


handle_call({new_change,Data}, _, State) ->  
        {Change, NewState} = h_new_change(Data, State),
        {reply, Change, NewState};
handle_call(get_cache, _, State) -> {reply,State#state.history_cache,State};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({on_change_available, ChangeKey},S) -> {noreply, h_on_change_available(ChangeKey,S)};
handle_cast({update_reader_locator_list, RL}, State) -> {noreply,h_update_reader_locator_list(RL,State)};
handle_cast({reader_locator_add,Locator}, State) -> {noreply,h_reader_locator_add(Locator,State)};
handle_cast({reader_locator_remove,Locator}, State) -> {noreply,h_reader_locator_remove(Locator,State)};
handle_cast(unsent_changes_reset, State) -> {noreply,h_unsent_changes_reset(State)};
handle_cast(_, State) -> {noreply,State}.

handle_info(writer_loop,State) -> {noreply,writer_loop(State)}.


%callback helpers
% 
send_locators_changes(#state{reader_locators=RLs}=S) -> send_locators_changes(S,RLs,[]).
send_locators_changes(S,[],New_RL) -> S#state{reader_locators=New_RL};
send_locators_changes(#state{participant=P,entity=E}=S,[#reader_locator{locator=L,unsent_changes=Changes}=RL|TL], New_RL) -> 
        % prepare ordered datasubmsg in binary and send them 
        %io:format("~p\n",[Prefix]),
        %case Prefix of undefined -> DST=[]; _ -> DST = [rtps_messages:serialize_info_dst(Prefix)] end,
        SUB_MSG_LIST =  [rtps_messages:serialize_info_timestamp()]++
                        [rtps_messages:serialize_data(?ENTITYID_UNKNOWN,C) || C  <- Changes],
        Datagram = rtps_messages:build_message(P#participant.guid#guId.prefix, SUB_MSG_LIST),
        [G|_] = pg:get_members(rtps_gateway),
        rtps_gateway:send(G, {Datagram,{L#locator.ip,L#locator.port}}),
        send_locators_changes(S,TL, [RL#reader_locator{unsent_changes=[]} | New_RL]).

-define(WRITING_FREQ,1000).

writer_loop(S) -> 
        send_locators_changes(S),
        erlang:send_after(?WRITING_FREQ, self(), writer_loop),
        S.

h_new_change(D,#state{last_sequence_number=Last_SN,entity=E,history_cache=C}=S) -> 
        SN = Last_SN + 1,
        Change = #cacheChange{kind=alive,writerGuid=E#endPoint.guid,
                instanceHandle=0,sequenceNumber=SN, data = D},
        {Change, S#state{last_sequence_number=SN}}.

h_update_reader_locator_list(RL_List,#state{reader_locators=RLS, history_cache=C} = S) -> 
        L_List = [ L || #reader_locator{locator=L} <- RL_List],
        RLStillValid = [ RL || #reader_locator{locator=L}=RL <- RLS, lists:member(L, L_List) ],
        NewRLS = [ RL || #reader_locator{locator=L}=RL <- RL_List, not lists:member(L,[ Loc || #reader_locator{locator=Loc}<-RLS])],
        % add cache changes to the unsent list for the new added locators
        Changes = rtps_history_cache:get_all_changes(C),
        S#state{reader_locators= RLStillValid ++ reset_locators(Changes,NewRLS)}.
h_reader_locator_add(L,#state{reader_locators=RL} = S) -> S#state{reader_locators=[#reader_locator{locator=L}| RL]}.

h_reader_locator_remove(L,#state{reader_locators=RL} = S) -> S#state{reader_locators=[Loc || Loc <- RL, Loc#reader_locator.locator /= L]}.

reset_locators(Changes,RL) -> reset_locators(Changes,RL,[]).
reset_locators(_,[],NewRL) -> NewRL;
reset_locators(Changes,[RL| TL],NewLocators) ->  
        N_RL = RL#reader_locator{unsent_changes=Changes},
        reset_locators(Changes, TL, [N_RL|NewLocators]).

h_unsent_changes_reset(#state{history_cache=C,reader_locators=RL}=S) ->  
        %io:format("Resetting\n"),
        Changes = rtps_history_cache:get_all_changes(C),
        S#state{reader_locators = reset_locators(Changes,RL)}.
add_change_to_locators(Change,RL) -> add_change_to_locators(Change,RL,[]).
add_change_to_locators(_,[],NewRL) -> NewRL;
add_change_to_locators(Change,[RL| TL],NewLocators) ->  
        ChangeList = RL#reader_locator.unsent_changes ++ [Change],
        N_RL = RL#reader_locator{unsent_changes=ChangeList},
        add_change_to_locators(Change, TL, [N_RL|NewLocators]).

h_on_change_available(Key,#state{history_cache=C,reader_locators=L}=S) -> 
        S#state{reader_locators = add_change_to_locators(rtps_history_cache:get_change(C, Key), L)}.