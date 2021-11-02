-module(parameters).

-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are gonna use String.msg so we include its header to use its record definition.
-include_lib("std_msgs/src/_rosie/std_msgs_string_msg.hrl").

-record(state, {ros_node}).

start_link() ->
    gen_server:start_link(?MODULE, #state{}, []).

init(_) ->
    Node = ros_context:create_node("parameter_test"),
    
    OtherNode = ros_context:create_node("secon_node"),

    test_parameter_declaration_api(Node),

    {ok, #state{ros_node = Node}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast(_, S) ->
    {noreply, S}.

handle_info(_, S) ->
    {noreply, S}.

test_parameter_declaration_api(Node) ->
    SA = ros_node:declare_parameter(Node, "scale_angular", 1.0),
    SL = ros_node:declare_parameter(Node, "scale_linear", 1.0),    
    % Code to test other param type declarations
    S = ros_node:declare_parameter(Node, "dummy_string", "Hellow world!"), 
    I = ros_node:declare_parameter(Node, "int_val", -4), 
    B = ros_node:declare_parameter(Node, "bool_val", false), 
    Str_L = ros_node:declare_parameter(Node, "str_list", ["coco","Wow BRO! |-> .\n"]),    
    I_L = ros_node:declare_parameter(Node, "int_list", [1,23,78,0,99]),    
    B_L = ros_node:declare_parameter(Node, "bool_list", [true,false]), 
    E_L = ros_node:declare_parameter(Node, "empty_list", []),
    N = ros_node:declare_parameter(Node, "not_set"),


    R1 = ros_node:declare_parameter(Node, "to_be_removed"),    
    R2 = ros_node:undeclare_parameter(Node, "to_be_removed"),
    R3 = ros_node:undeclare_parameter(Node, "never_declared"),

    I1 = ros_node:declare_parameter(Node, "Invalid example 1", ["ciao", 99]),
    I2 = ros_node:declare_parameter(Node, "Invalid example 2", [1.2, 99]),
    I3 = ros_node:declare_parameter(Node, "Invalid example 3", [1, false]),
    [ io:format("~p\n",[P]) || P <- [SA,SL,S,I,B,Str_L,I_L,B_L,E_L,N, R1,R2,R3, I1,I2,I3 ]].