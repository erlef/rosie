-module(talker).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are gonna use String.msg so we include its header to use its record definition.
-include_lib("std_msgs/src/_rosie/string_msg.hrl").

-record(state,{ ros_node,
                chatter_pub,
                period=1000,
                num=0}).

start_link() -> 
        gen_server:start_link(?MODULE, #state{}, []).

init(#state{period=P}=S) -> 
        Node = ros_context:create_node("talker"),        
        Pub = ros_node:create_publisher(Node, string_msg, "chatter"),
        erlang:send_after(P,self(),publish),
        {ok,S#state{ros_node=Node, chatter_pub=Pub}}.

handle_call(_,_,S) -> {reply,ok,S}.

handle_cast(_,S) -> {noreply,S}.

handle_info(publish,#state{ros_node=Node,chatter_pub=P, period=Period, num=N} = S) -> 
        MSG = "I'm Rosie: " ++ integer_to_list(N),
        io:format("ROSIE: [~s]: Publishing: ~s\n",[ros_node:get_name(Node), MSG]),
        ros_publisher:publish(P,#string{data = MSG}), 
        erlang:send_after(Period,self(),publish),
        {noreply,S#state{num=N+1}};
handle_info(_,S) -> {noreply,S}.

