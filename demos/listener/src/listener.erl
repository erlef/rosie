-module(listener).

-behaviour(gen_server).


-export([start_link/0,receive_chat/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").


start_link() -> 
        gen_server:start_link(?MODULE, [], []).
receive_chat({Msg}) -> 
        io:format("ROSIE: [listener]: I heard: ~s\n",[Msg]).

init(S) -> 
        Node = ros_context:create_node("listener"),       
        
        ros_node:create_subscription(Node, string_msg, "chatter", fun receive_chat/1),

        {ok,S}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.


