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
    [ io:format("~p\n",[P]) || P <- [SA,SL,S,I,B,Str_L,I_L,B_L,E_L,N, R1,R2,R3, I1,I2,I3 ]],
    io:format("ros_node:has_parameter(~p) ? = ~p\n",["scale_angular", ros_node:has_parameter(Node, "scale_angular")]),
    io:format("ros_node:has_parameter(~p) ? = ~p\n",["to_be_removed", ros_node:has_parameter(Node, "to_be_removed")]),
    io:format("ros_node:has_parameter(~p) ? = ~p\n",["Invalid example 1", ros_node:has_parameter(Node, "Invalid example 1")]),
    
    io:format("ros_node:get_parameter(~p) = ~p\n",["scale_angular", ros_node:get_parameter(Node, "scale_angular")]),
    ValidParams = ["scale_angular","int_val"],
    io:format("ros_node:get_parameters(~p) = ~p\n",[ValidParams, ros_node:get_parameters(Node, ValidParams)]),
    InvalidParams = ["scale_angular","Invalid example 1"],
    io:format("ros_node:get_parameters(~p) = ~p\n",[InvalidParams,ros_node:get_parameters(Node, InvalidParams)]),
    
    io:format("ros_node:get_parameter(~p) = ~p\n",["int_list", ros_node:get_parameter(Node, "int_list")]),
    io:format("ros_node:set_parameter(~p) = ~p\n",["int_list", ros_node:set_parameter(Node, #ros_parameter{ name = "int_list", type=?PARAMETER_INTEGER_ARRAY, value=[1,2,3]})]),
    io:format("ros_node:get_parameter(~p) = ~p\n",["int_list", ros_node:get_parameter(Node, "int_list")]),
    
    io:format("ros_node:describe_parameters(~p) = ~p\n",[InvalidParams, ros_node:describe_parameters(Node, InvalidParams)]),
    io:format("ros_node:describe_parameters(~p) = ~p\n",[ValidParams, ros_node:describe_parameters(Node, ValidParams)]),
    D = ros_node:describe_parameter(Node, "int_val"),
    %example of changing just trhe description
    NewD = D#rcl_interfaces_parameter_descriptor{name = "Ishould not appear", description="New Description!"},
    io:format("ros_node:set_descriptors(~p) = ~p\n",[NewD, ros_node:set_descriptor(Node, "int_val", NewD)]),
    io:format("ros_node:describe_parameters(~p) = ~p\n",["int_val", ros_node:describe_parameter(Node, "int_val")]),

    %example of changing just the description and type, a new value must be provided
    NewD2 = NewD#rcl_interfaces_parameter_descriptor{description="Changing type, now DOUBLE!", type=?PARAMETER_DOUBLE},
    io:format("ros_node:set_descriptors(~p) = ~p\n",[NewD2, ros_node:set_descriptor(Node, "int_val", NewD2, 0.7)]),
    io:format("ros_node:describe_parameters(~p) = ~p\n",["int_val", ros_node:describe_parameter(Node, "int_val")]),
    io:format("ros_node:get_parameter(~p) = ~p\n",["int_val", ros_node:get_parameter(Node, "int_val")])
    .

% update_existing_param_desc(N, NewDescriptor, #state{parameters=P} = S) ->
    
% update_existing_param_desc_and_val(N, NewDescriptor, AltVal, #state{parameters=P} = S) ->

% implicit_declare_param_with_desc(N, NewDescriptor, #state{parameters=P} = S) ->

% implicit_declare_param_with_desc_and_val(N, NewDescriptor, AltVal, #state{parameters=P} = S) ->
