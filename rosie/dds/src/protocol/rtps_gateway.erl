% Just a process to hold an UDP socket for sending packets
-module(rtps_gateway).

-behaviour(gen_server).

-export([start_link/0, send/2]).
-export([init/1, handle_cast/2, handle_call/3]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state, {participant = #participant{}, socket}).

%API
start_link() ->
    gen_server:start_link(?MODULE, #state{}, []).

send(Pid, {Data, Dst}) ->
    gen_server:cast(Pid, {send, {Data, Dst}}).

% callbacks
init(State) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    pg:join(rtps_gateway, self()),
    LocalInterface = rtps_network_utils:get_local_ip(),
    {ok, S} = gen_udp:open(0,[{ip, LocalInterface}, binary, {active, true}]),
    {ok, State#state{socket = S}}.

% handle_call({send,{Datagram,Dst}}, _, #state{socket=S}=State) ->
%         {reply,gen_udp:send(S,Dst,Datagram),State};
handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({send, {Datagram, Dst}}, #state{socket = S} = State) ->
    case gen_udp:send(S, Dst, Datagram) of
        ok -> ok;
        {error, Reason} -> 
                        io:format("[GATEWAY]: failed sending to: ~p\n",[Dst]),
                        io:format("[GATEWAY]: reason of failure: ~p\n",[Reason])
    end,
    {noreply, State};
handle_cast(_, State) ->
    {noreply, State}.
