-module(parameters).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).


-include_lib("ros/include/ros_commons.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_type_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_descriptor_msg.hrl").

-record(state, {ros_node}).

start_link() ->
    gen_server:start_link(?MODULE, #state{}, []).

% TODO: develop an interesting demo around parameter events and services
init(_) ->
    Node = ros_context:create_node("parameter_test"),

    OtherNode = ros_context:create_node("second_node"),

    ok = ros_context:destroy_node(OtherNode),

    {ok, #state{ros_node = Node}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast(_, S) ->
    {noreply, S}.

handle_info(_, S) ->
    {noreply, S}.
