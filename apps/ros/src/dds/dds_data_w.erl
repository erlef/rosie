-module(dds_data_w).


-behaviour(gen_server).

-export([start_link/1, write/2, match_remote_readers/2]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).
-include("../protocol/rtps_structure.hrl").
-include("../protocol/rtps_constants.hrl").
-include("dds_types.hrl").

-record(state,{publisher, topic, rtps_writer, history_cache}).

start_link(Setup) -> gen_server:start_link( ?MODULE, Setup, []).

match_remote_readers(Pid, R) -> gen_server:cast(Pid, {match_remote_readers,R}).
write(Pid, MSG) -> gen_server:cast( Pid, {write, MSG}).
%callbacks 
init({Topic,#participant{guid=ID}, PUB, EntityID}) ->  
        WriterConfig = #endPoint{
                guid = #guId{ prefix = ID#guId.prefix, entityId = EntityID },     
                reliabilityLevel = reliable,
                topicKind = ?NO_KEY,
                unicastLocatorList = [],
                multicastLocatorList = []
        },
        {ok,Cache} = rtps_history_cache:new(), 
        [P|_] = pg:get_members(ID),
        W = rtps_participant:create_full_writer(P, WriterConfig, Cache),% rtps_full_writer:create({P, WriterConfig, Cache}),
        {ok,#state{publisher = PUB,topic=Topic, rtps_writer=W, history_cache=Cache}}.

handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({match_remote_readers,R}, #state{rtps_writer=W}=S) -> rtps_full_writer:update_matched_readers(W, R), {noreply,S};
handle_cast({write, Msg}, #state{history_cache=Cache, rtps_writer=W}=S) -> 
        %io:format("Writing: ~p\n",[Msg]),
        Change = rtps_full_writer:new_change(W,Msg),
        rtps_history_cache:add_change(Cache, Change),
        {noreply,S};
handle_cast(_, State) -> {noreply,State}.

handle_info(_,State) -> {noreply,State}.