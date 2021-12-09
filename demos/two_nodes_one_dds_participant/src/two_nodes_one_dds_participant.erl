-module(two_nodes_one_dds_participant).


-export([start_link/0]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-include_lib("ros/include/ros_commons.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_type_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_descriptor_msg.hrl").

-record(state, {talker, listener, subscription, chatter_pub, period = 1000, num = 0}).
-include_lib("std_msgs/src/_rosie/std_msgs_string_msg.hrl").

start_link() ->
    gen_server:start_link(?MODULE, #state{}, []).

on_topic_msg(Pid, Msg) ->
    gen_server:cast(Pid, {on_topic_msg, Msg}).

init(#state{period = P} = S) ->

    Talker = ros_context:create_node("talker"),
    Pub = ros_node:create_publisher(Talker, std_msgs_string_msg, "chatter"),
    
    Listener = ros_context:create_node("listener"),
    Sub = ros_node:create_subscription(Listener, std_msgs_string_msg, "chatter", {?MODULE, self()}),

    erlang:send_after(P, self(), publish),
    
    {ok, S#state{talker = Talker,
                listener = Listener,
                subscription = Sub, 
                chatter_pub = Pub}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({on_topic_msg, #std_msgs_string{data = Msg}}, S) ->
    io:format("ROSIE: [listener]: I heard: ~s\n", [Msg]),
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

handle_info(publish,
            #state{talker = Talker,
                   chatter_pub = P,
                   period = Period,
                   num = N} =
                S) ->
    MSG = "I'm Rosie: " ++ integer_to_list(N),
    io:format("ROSIE: [~s]: Publishing: ~s\n", [ros_node:get_name(Talker), MSG]),
    ros_publisher:publish(P, #std_msgs_string{data = MSG}),
    erlang:send_after(Period, self(), publish),
    {noreply, S#state{num = N + 1}};
handle_info(_, S) ->
    {noreply, S}.
