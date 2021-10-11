-module(minimal_service).

-export([start_link/0]).

-behaviour(gen_service_listener).
-export([on_client_request/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2]).

% We are going to use AddTwoInts.msg, so we include its header to use its record definition.
-include_lib("example_interfaces/src/_rosie/add_two_ints_srv.hrl").

-record(state,{ ros_node,
                ros_service}).

start_link() -> 
        gen_server:start_link(?MODULE, #state{}, []).

on_client_request(Pid,{_,R}) -> 
        gen_server:call(Pid,{handle_request,R}).

init(S) -> 
        Node = ros_context:create_node("minimal_server"),

        Service = ros_node:create_service(Node, add_two_ints_srv, {?MODULE,self()}),

        {ok,S#state{ros_node=Node, ros_service=Service}}.

handle_call({handle_request,#add_two_ints_rq{a=A,b=B}},_,S) -> 
        io:format("[ROSIE] Received request for: ~p ~p\n",[A,B]),
        {reply,#add_two_ints_rp{sum = A + B },S};
handle_call(_,_,S) -> {reply,ok,S}.

handle_cast(_,S) -> {noreply,S}.

