-module(listener).

-export([start_link/0]).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2]).

% We are going to use String.msg so we include its header to use its record definition.
-include_lib("std_msgs/src/_rosie/string_msg.hrl").

-record(state, {subscription}).

start_link() -> 
        gen_server:start_link(?MODULE, [], []).

receive_chat(#string{message=Msg}) -> 
        io:format("ROSIE: [listener]: I heard: ~s\n",[Msg]).

init(_) -> 
        Node = ros_context:create_node("listener"),       
        Sub = ros_node:create_subscription(Node, string_msg, "chatter", fun receive_chat/1),
        {ok,#state{subscription=Sub}}.

handle_call(_,_,S) -> {reply,ok,S}.

handle_cast(_,S) -> {noreply,S}.


