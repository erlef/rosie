-module(turtle_controller).

-behaviour(gen_server).


-export([start_link/0,receive_chat/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").

-record(state,{ ros_node,
                chatter_pub}).

start_link() -> 
        gen_server:start_link({local, turtle},?MODULE, [], []).
receive_chat(Msg) -> 
        io:format("~s\n",[Msg]).

init(_) -> 
        Node = ros_context:create_node("turtle_controller"),
        
        ChatterTopic = #user_topic{type_name=?msg_twist_topic_type , name="turtle1/cmd_vel"},
        Pub = ros_node:create_publisher(Node, ChatterTopic),

        {ok,#state{ros_node=Node, chatter_pub=Pub}}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.


handle_info(go, #state{chatter_pub=P} = S) -> 
        Sign = +1,
        Twist = #twist{linear=#vector3{x=2*Sign,y=0,z=0}},
        ros_publisher:publish(P,Twist),
        {noreply,S};
handle_info(back, #state{chatter_pub=P} = S) -> 
        Sign = -1,
        Twist = #twist{linear=#vector3{x=2*Sign,y=0,z=0}},
        ros_publisher:publish(P,Twist),
        {noreply,S};
handle_info(right, #state{chatter_pub=P} = S) -> 
        Sign = -1,
        Twist = #twist{angular=#vector3{x=0,y=0,z=1*Sign}},
        ros_publisher:publish(P,Twist),
        {noreply,S};
handle_info(left, #state{chatter_pub=P} = S) -> 
        Sign = +1,
        Twist = #twist{angular=#vector3{x=0,y=0,z=1*Sign}},
        ros_publisher:publish(P,Twist),
        {noreply,S};
handle_info(_,S) -> {noreply,S}.

