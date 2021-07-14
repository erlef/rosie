% Just a process to hold an UDP socket for sending packets
-module(rtps_gateway).

-behaviour(gen_server).

-export([start_link/0,send/2]).%send_data/2,get_cache/1]).
-export([init/1, handle_cast/2, handle_call/3]).

-include("rtps_structure.hrl").
%-include("rtps_constants.hrl").


-record(state,{
        participant = #participant{},
        socket
}).

%API
start_link() -> 
        gen_server:start_link(?MODULE, #state{},[]).


send(Pid,{Data,Dst}) -> gen_server:cast(Pid, {send,{Data,Dst}}).

% callbacks
init(State) -> 
io:format("~p.erl STARTED!\n",[?MODULE]),
        
        pg:join(rtps_gateway, self()), 
        {ok, S}  = gen_udp:open(0),
        {ok,State#state{socket=S}}.
% handle_call({send,{Datagram,Dst}}, _, #state{socket=S}=State) -> 
%         {reply,gen_udp:send(S,Dst,Datagram),State};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({send,{Datagram,Dst}}, #state{socket=S}=State) ->
        ok = gen_udp:send(S,Dst,Datagram),
        {noreply,State};
handle_cast(_, State) -> {noreply,State}.

