-module(ros_context).

-behaviour(gen_server).

-export([start_link/0,create_node/1]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include_lib("ros/include/ros_commons.hrl").

-record(state,{dds_domain_participant}).

%API

start_link() -> gen_server:start_link( {local, ?ROS_CONTEXT},?MODULE, #state{},[]).
create_node(Name) -> gen_server:call(?ROS_CONTEXT, {create_node, Name}).

% callbacks
init(S) -> 
        %io:format("~p.erl STARTED!\n",[?MODULE]),
        {ok,S}.

handle_call({create_node,Name},_,S) -> 
        {ok, _} = supervisor:start_child(ros_nodes_pool_sup,[Name]),
        {reply,{ros_node, Name},S};
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.
handle_info(_,S) -> {noreply,S}.
