-module(talker).

-behaviour(gen_server).


-export([start_link/0,receive_chat/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% -include("../../ros/src/protocol/rtps_constants.hrl").
% -include("../../ros/src/protocol/rtps_structure.hrl").
-include("../../ros/src/dds/dds_types.hrl").
-include("../../ros/src/rcl/rmw_dds_msg.hrl").

-record(state,{ros_node,
                chatter_pub,
                period=1000,
                num=0}).

start_link() -> gen_server:start_link(?MODULE, #state{}, []).
receive_chat(Msg) -> io:format("~s\n",[Msg]).

init(#state{period=P}=S) -> 
        rcl:start_link(),

        {ok, Node} = ros_node:create("talker"),
        
        ChatterTopic = #user_topic{type_name=?msg_string_topic_type , name="chatter"},
        Pub = ros_node:create_publisher(Node, ChatterTopic),

        rcl:spin(Node),

        erlang:send_after(P,self(),publish),

        {ok,S#state{ros_node=Node, chatter_pub=Pub}}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.

handle_info(publish,#state{ros_node=Node,chatter_pub=P, period=Period, num=N} = S) -> 
        MSG = "I'm Rosie: " ++ integer_to_list(N),
        io:format("ROSIE: [~s]: Publishing: ~s\n",[ros_node:get_name(Node), MSG]),
        ros_publisher:publish(P,MSG), 
        erlang:send_after(Period,self(),publish),
        {noreply,S#state{num=N+1}};
handle_info(_,S) -> {noreply,S}.

