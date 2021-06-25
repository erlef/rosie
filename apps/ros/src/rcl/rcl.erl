-module(rcl).

-behaviour(gen_server).

-export([start_link/0,get_dds_domain_participant/1,spin/1]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include("ros_commons.hrl").
-include("rmw_dds_msg.hrl").
-include("../dds/dds_types.hrl").


-record(context,{dds_domain_participant}).

%API
start_link() -> gen_server:start_link( {local, ?ROS_CONTEXT},?MODULE, #context{},[]).
get_dds_domain_participant(Pid) -> gen_server:call(Pid, get_dds_domain_participant).
spin(Node) -> gen_server:call(?ROS_CONTEXT, {spin, Node}).

% callbacks
init(S) -> 
        DomainID = 0,
        {ok,DP} = dds_domain_participant:start_link(DomainID),
        {ok,S#context{dds_domain_participant=DP}}.

handle_call(get_dds_domain_participant,_,S) -> {reply,S#context.dds_domain_participant,S};
handle_call({spin,Node},_,S) ->  h_spin(Node), {reply,ok,S};
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.
handle_info(_,S) -> {noreply,S}.

% HELPERS
h_spin(Node) -> ros_node:execute_all_jobs(Node).