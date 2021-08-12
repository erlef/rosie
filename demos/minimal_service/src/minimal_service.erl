-module(minimal_service).

-behaviour(gen_server).


-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").

-record(state,{ ros_node,
                ros_service}).

start_link() -> 
        gen_server:start_link(?MODULE, #state{}, []).
handle_request({A,B}) -> 
        io:format("[ROSIE] Received request for: ~p ~p\n",[A,B]),
        A + B.

init(S) -> 
        Node = ros_context:create_node("minimal_server"),

        Service = ros_node:create_service(Node, add_two_ints, fun handle_request/1),

        {ok,S#state{ros_node=Node, ros_service=Service}}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.

