-module(ros_context).

-behaviour(gen_server).

-export([start_link/0,get_dds_domain_participant/0,create_node/1,spin/1]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include("ros_commons.hrl").
-include("rmw_dds_msg.hrl").
-include("../dds/dds_types.hrl").


-record(state,{dds_domain_participant}).

%API

start_link() -> gen_server:start_link( {local, ?ROS_CONTEXT},?MODULE, #state{},[]).
get_dds_domain_participant() -> gen_server:call(?ROS_CONTEXT, get_dds_domain_participant).
create_node(Name) -> gen_server:call(?ROS_CONTEXT, {create_node, Name}).
spin(Node) -> gen_server:call(?ROS_CONTEXT, {spin, Node}).

% callbacks
init(S) -> 
        io:format("~p.erl STARTED!\n",[?MODULE]),
        {ok,S}.

handle_call(get_dds_domain_participant,_,S) -> {reply,S#state.dds_domain_participant,S};
handle_call({create_node,Name},_,S) -> 
        {ok, _} = supervisor:start_child(ros_nodes_pool_sup,[Name]),
        {reply,{ros_node, Name},S};
handle_call({spin,Node},_,S) ->  h_spin(Node), {reply,ok,S};
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.
handle_info(_,S) -> {noreply,S}.

% HELPERS
h_spin(Node) -> ros_node:execute_all_jobs(Node).