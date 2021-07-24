-module(rtps_history_cache).

-include_lib("dds/include/rtps_structure.hrl").

-behaviour(gen_server).

-export([start_link/1,set_listener/2,add_change/2,remove_change/2,get_change/2,get_all_changes/1,get_min_seq_num/1,get_max_seq_num/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, { listener = not_set, cache=#{} }).

start_link(OwnerGUID) -> gen_server:start_link( ?MODULE, OwnerGUID, []).
% API
set_listener(Name, L) ->
        [Pid|_] = pg:get_members(Name), 
        gen_server:cast(Pid,{set_listener,L}).
add_change(Name,Change) ->
        [Pid|_] = pg:get_members(Name), 
        gen_server:cast(Pid,{add_change, Change}).
get_change(Name,{WriterGuid,SequenceNumber}) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{get_change,WriterGuid, SequenceNumber}).
get_all_changes(Name) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,get_all_changes).
remove_change(Name,{WriterGuid,SequenceNumber}) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{remove_change, WriterGuid, SequenceNumber}).
get_max_seq_num(Name) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,get_max_seq_num).
get_min_seq_num(Name) ->
        [Pid|_] = pg:get_members(Name),
         gen_server:call(Pid,get_min_seq_num).
% CALL_BACKS
init(OwnerGUID) -> 
        %io:format("~p.erl STARTED!\n",[?MODULE]), 
        pg:join({cache_of,OwnerGUID},self()),
        {ok,#state{}}.
handle_call(get_min_seq_num, _, State) -> {reply,h_get_min_seq_num(State),State};
handle_call(get_max_seq_num, _, State) -> {reply,h_get_max_seq_num(State),State};
handle_call({get_change, WriterGuid, SequenceNumber}, _, State) -> {reply,h_get_change(State,WriterGuid,SequenceNumber),State};
handle_call(get_all_changes, _, State) -> {reply, maps:values(State#state.cache) , State}.
handle_cast({set_listener, L}, State) -> {noreply,State#state{listener=L}};
handle_cast({add_change, Change}, #state{listener = L}=S) when L == not_set -> {noreply,h_add_change(S, Change)};
handle_cast({add_change, Change}, #state{listener = {ID,Module}}=S) ->
        Module:on_change_available(ID,{Change#cacheChange.writerGuid,Change#cacheChange.sequenceNumber}),
        {noreply,h_add_change(S, Change)};
handle_cast({remove_change, WriterGuid, SequenceNumber}, State) -> {noreply,h_remove_change(State, WriterGuid,SequenceNumber)}.
handle_info(clean_up_loop,State) -> {noreply,State}.


%CALL_BACK HELPERS
h_add_change(#state{cache=C}=State,Change) -> State#state{cache = C#{ {Change#cacheChange.writerGuid,Change#cacheChange.sequenceNumber} => Change}}.
h_get_change(#state{cache=C},WriterGuid,SequenceNumber) -> 
        case maps:find({WriterGuid,SequenceNumber},C) of
                {ok,Change} -> Change; 
                error -> not_found
        end.
h_remove_change(#state{cache=C}=State,WriterGuid,SequenceNumber) -> State#state{cache = maps:remove({WriterGuid,SequenceNumber}, C)}.

h_get_min_seq_num(#state{cache=C}) -> 
        case maps:size(C) of 0 -> 0; _ -> lists:min([ SN || {_,SN} <- maps:keys(C)]) end.
h_get_max_seq_num(#state{cache=C}) ->  
        case maps:size(C) of 0 -> 0; _ -> lists:max([ SN || {_,SN} <- maps:keys(C)]) end.



-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include("rtps_constants.hrl").

% history_cache_test() -> 
%         {ok, Cache } = rtps_history_cache:new(),
%         SN = 10,
%         Change = #cacheChange{   kind=brutto, writerGuid= ?GUID_UNKNOWN,
%                 instanceHandle=0,
%                 sequenceNumber=SN,
%                 inlineQoS=[],
%                 data=#spdp_disc_part_data{}},
%         Change2 = Change#cacheChange{instanceHandle=1,sequenceNumber=SN+1},
%         Change3 = Change#cacheChange{instanceHandle=2,sequenceNumber=SN+2},

%         rtps_history_cache:add_change(Cache,Change),
%         rtps_history_cache:add_change(Cache,Change2),
%         rtps_history_cache:add_change(Cache,Change3),
%         List = rtps_history_cache:get_all_changes(Cache),
%         ?assert( [Change,Change2,Change3] == List), 
%         C = rtps_history_cache:get_change(Cache,{?GUID_UNKNOWN,SN}),
%         io:format("~p\n",[C]),
%         ?assert(Change == C),
%         Min = rtps_history_cache:get_min_seq_num(Cache),
%         Max = rtps_history_cache:get_max_seq_num(Cache),
%         io:format("Max=~p, Min=~p\n",[Max,Min]),
%         ?assert(Min == 10),
%         ?assert(Max == 12),
%         rtps_history_cache:remove_change(Cache,{?GUID_UNKNOWN,10}),        
%         C2 = rtps_history_cache:get_change(Cache,{?GUID_UNKNOWN,10}),
%         io:format("~p\n",[C2]),
%         ?assert(C2 == not_found),
%         Min2 = rtps_history_cache:get_min_seq_num(Cache),
%         ?assert(Min2 == 11),
%         rtps_history_cache:add_change(Cache,Change),
%         C3 = rtps_history_cache:get_change(Cache,{?GUID_UNKNOWN,10}),
%         io:format("~p\n",[C3]),
%         ?assert(C3 == C).



-endif.