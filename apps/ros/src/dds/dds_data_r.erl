-module(dds_data_r).


-behaviour(gen_server).

-export([start_link/1,read/2,on_change_available/2,set_listener/2, match_remote_writers/2]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).
-include("../protocol/rtps_structure.hrl").
-include("../protocol/rtps_constants.hrl").

-record(state,{topic, listener = not_set, rtps_reader, history_cache}).

start_link(Setup) -> gen_server:start_link( ?MODULE, Setup,[]).
on_change_available(Name, ChangeKey) ->       
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {on_change_available, ChangeKey}).
set_listener(Name, Listener) ->        
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid, {set_listener, Listener}).
read(Name, Change) ->        
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid, {read, Change}).
match_remote_writers(Name, Writers) ->        
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{match_remote_writers,Writers}).


%callbacks 
init({Topic,#participant{guid=ID}, GUID}) ->  
        io:format("~p.erl STARTED!\n",[?MODULE]), 
        pg:join({data_r_of, GUID},self()),
        rtps_history_cache:set_listener({cache_of, GUID}, {{data_r_of, GUID},?MODULE}),
        % [P|_] = pg:get_members(ID),
        % R = rtps_participant:create_full_reader(P,ReaderConfig,Cache),
        {ok,#state{topic=Topic,rtps_reader = GUID, history_cache = {cache_of, GUID}}}.

handle_call({read, ChangeKey}, _, #state{history_cache=C}=S) -> {reply,rtps_history_cache:get_change(C,ChangeKey),S};
handle_call({set_listener, L}, _, State) -> {reply,ok,State#state{listener=L}};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({on_change_available, _}, #state{listener = L}=S) when L == not_set -> {noreply,S};
handle_cast({on_change_available, ChangeKey}, #state{rtps_reader= GUID, listener = {Name,Module}}=S) -> 
        Module:on_data_available(Name,{{data_r_of, GUID},ChangeKey}), 
        {noreply,S};
handle_cast({match_remote_writers,Writers}, #state{rtps_reader= Reader} =S) -> rtps_full_reader:update_matched_writers(Reader,Writers), {noreply,S};
handle_cast(_, State) -> {noreply,State}.
handle_info(_,State) -> {noreply,State}.