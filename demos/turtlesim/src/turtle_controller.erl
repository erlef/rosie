-module(turtle_controller).

-behaviour(gen_server).

-export([start_link/0, spawn/2, spawn_async/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are going to use Twist.msg and Spawn.srv, so we include their headers to use their records.
-include_lib("geometry_msgs/src/_rosie/geometry_msgs_twist_msg.hrl").
-include_lib("turtlesim/src/_rosie/turtlesim_spawn_srv.hrl").

-record(state, {ros_node, chatter_pub, spawn__client}).

start_link() ->
    gen_server:start_link({local, turtle}, ?MODULE, [], []).

spawn(Pid, Info) ->
    gen_server:call(Pid, {spawn_turtle, Info}).

spawn_async(Pid, Info) ->
    gen_server:cast(Pid, {spawn_turtle_async, Info}).

print_spawn_responce(#turtlesim_spawn_rp{name = Name}) ->
    io:format("Spawn reply: ~s\n", [Name]).

init(_) ->
    Node = ros_context:create_node("turtle_controller"),


    Pub = ros_node:create_publisher(Node, geometry_msgs_twist_msg, "turtle1/cmd_vel"),

    Client = ros_node:create_client(Node, turtlesim_spawn_srv, fun print_spawn_responce/1),

    {ok,
     #state{ros_node = Node,
            chatter_pub = Pub,
            spawn__client = Client}}.

handle_call({spawn_turtle, {X, Y, Angle, Name}}, _, #state{spawn__client = C} = S) ->
    case ros_client:service_is_ready(C) of
        true ->
            #turtlesim_spawn_rp{name = N} =
                ros_client:call(C,
                                #turtlesim_spawn_rq{x = X,
                                                    y = Y,
                                                    theta = Angle,
                                                    name = Name}),
            {reply, N, S};
        false ->
            {reply, server_unavailable, S}
    end;
handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({spawn_turtle_async, {X, Y, Angle, Name}}, #state{spawn__client = C} = S) ->
    ros_client:cast(C,
                    #turtlesim_spawn_rq{x = X,
                                        y = Y,
                                        theta = Angle,
                                        name = Name}),
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

handle_info(go, #state{chatter_pub = P} = S) ->
    Sign = +1,
    Twist =
        #geometry_msgs_twist{linear =
                                 #geometry_msgs_vector3{x = 2 * Sign,
                                                        y = 0,
                                                        z = 0}},
    ros_publisher:publish(P, Twist),
    {noreply, S};
handle_info(back, #state{chatter_pub = P} = S) ->
    Sign = -1,
    Twist =
        #geometry_msgs_twist{linear =
                                 #geometry_msgs_vector3{x = 2 * Sign,
                                                        y = 0,
                                                        z = 0}},
    ros_publisher:publish(P, Twist),
    {noreply, S};
handle_info(right, #state{chatter_pub = P} = S) ->
    Sign = -1,
    Twist =
        #geometry_msgs_twist{angular =
                                 #geometry_msgs_vector3{x = 0,
                                                        y = 0,
                                                        z = 1 * Sign}},
    ros_publisher:publish(P, Twist),
    {noreply, S};
handle_info(left, #state{chatter_pub = P} = S) ->
    Sign = +1,
    Twist =
        #geometry_msgs_twist{angular =
                                 #geometry_msgs_vector3{x = 0,
                                                        y = 0,
                                                        z = 1 * Sign}},
    ros_publisher:publish(P, Twist),
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.
