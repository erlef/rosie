-module(turtle_controller).

-behaviour(gen_server).


-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").

-record(state,{ ros_node,
                chatter_pub,
                spawn__client}).

start_link() -> 
        gen_server:start_link({local, turtle},?MODULE, [], []).

print_spawn_responce(Msg) -> 
        io:format("Spawn reply: ~s\n",[Msg]).

init(_) -> 
        Node = ros_context:create_node("turtle_controller"),
        
        ChatterTopic = #user_topic{type_name=?msg_twist_topic_type , name="turtle1/cmd_vel"},
        Pub = ros_node:create_publisher(Node, ChatterTopic),

        Client = ros_node:create_client(Node, spawn_interface, fun print_spawn_responce/1),

        {ok,#state{ros_node=Node, chatter_pub=Pub, spawn__client = Client}}.
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
handle_info({spawn, X, Y, Angle, Name}, #state{spawn__client=C} = S) -> 
        io:format("To be implemented\n"),
        ros_client:send_request(C, {X, Y, Angle, Name}),
        {noreply,S};
handle_info(_,S) -> {noreply,S}.

