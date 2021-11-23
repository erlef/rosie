-module(ros_node_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include_lib("ros/include/ros_commons.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_type_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_descriptor_msg.hrl").


-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([valid_parameters_declarations/1,
        invalid_parameters_declarations/1,
        undeclare_parameters/1,
        get_parameters/1,
        set_parameters/1,
        parameter_description/1]).

-record(suite_config, { ros_node }).
 
all() -> [valid_parameters_declarations,
        invalid_parameters_declarations,
        undeclare_parameters,
        get_parameters,
        set_parameters,
        parameter_description].
 
init_per_suite(Config) ->
        {ok,_} = application:ensure_all_started(ros),
        Node = ros_context:create_node("test_node"),
        [#suite_config{ros_node = Node} | Config].
 
end_per_suite(_) -> 
        ok.

%% TEST CASES

valid_parameters_declarations(Config) ->
        Node = ?config(suite_config,Config),
        ?assertMatch(#ros_parameter{name="dummy_string", value="Hello world!", type=?PARAMETER_STRING}, 
                ros_node:declare_parameter(Node, "dummy_string", "Hello world!")),
        ?assertMatch(#ros_parameter{name="int_val", value= -4, type=?PARAMETER_INTEGER}, 
                ros_node:declare_parameter(Node, "int_val", -4)),
        ?assertMatch(#ros_parameter{name="bool_val", value = false, type=?PARAMETER_BOOL}, 
                ros_node:declare_parameter(Node, "bool_val", false)),
        ?assertMatch(#ros_parameter{name="str_list", value=["coco","Wow BRO! |-> .\n"], type=?PARAMETER_STRING_ARRAY}, 
                ros_node:declare_parameter(Node, "str_list", ["coco","Wow BRO! |-> .\n"])),
        ?assertMatch(#ros_parameter{name="int_list", value=[1,23,78,0,99], type=?PARAMETER_INTEGER_ARRAY}, 
                ros_node:declare_parameter(Node, "int_list", [1,23,78,0,99])), 
        ?assertMatch(#ros_parameter{name="bool_list", value=[true,false], type=?PARAMETER_BOOL_ARRAY}, 
                ros_node:declare_parameter(Node, "bool_list", [true,false])), 
        ?assertMatch(#ros_parameter{name="empty_list", value=none, type=?PARAMETER_NOT_SET}, 
                ros_node:declare_parameter(Node, "empty_list", [])), 
        ?assertMatch(#ros_parameter{name="not_set", value=none, type=?PARAMETER_NOT_SET}, 
                ros_node:declare_parameter(Node, "not_set")),
        ?assertMatch(#ros_parameter{name="/scoped/numbered_4", value=none, type=?PARAMETER_NOT_SET}, 
                        ros_node:declare_parameter(Node, "/scoped/numbered_4")),

        ?assert(ros_node:has_parameter(Node, "int_val")),        
        ?assert(ros_node:has_parameter(Node, "bool_val")),        
        ?assert(ros_node:has_parameter(Node, "str_list")),        
        ?assert(ros_node:has_parameter(Node, "int_list")),        
        ?assert(ros_node:has_parameter(Node, "bool_list")),        
        ?assert(ros_node:has_parameter(Node, "empty_list")),        
        ?assert(ros_node:has_parameter(Node, "not_set")),        
        ?assert(ros_node:has_parameter(Node, "/scoped/numbered_4")),  
                
        ok.

invalid_parameters_declarations(Config) ->
        Node = ?config(suite_config,Config),

        ros_node:declare_parameter(Node, "already_declared"),
        ?assertMatch({error, parameter_already_declared}, ros_node:declare_parameter(Node, "already_declared")),

        ?assertMatch({error, invalid_name},ros_node:declare_parameter(Node, "23425")),
        ?assertMatch({error, invalid_name},ros_node:declare_parameter(Node, "+chat")),
        ?assertMatch({error, invalid_name},ros_node:declare_parameter(Node, "wtf!?")),
        
        ?assertMatch({error, invalid_type},ros_node:declare_parameter(Node, "invalid1", ["ciao", 99])),
        ?assertMatch({error, invalid_type},ros_node:declare_parameter(Node, "invalid2", ["ciao", [1,2,3]])),
        ?assertMatch({error, invalid_type},ros_node:declare_parameter(Node, "invalid3", ["ciao", [1.2, 99]])),
        ?assertMatch({error, invalid_type},ros_node:declare_parameter(Node, "invalid4", ["ciao", [1, false]])),
        
        ?assertNot(ros_node:has_parameter(Node, "invalid1")),
        ?assertNot(ros_node:has_parameter(Node, "invalid2")),        
        ?assertNot(ros_node:has_parameter(Node, "invalid3")),        
        ?assertNot(ros_node:has_parameter(Node, "invalid4")), 
        ok.

undeclare_parameters(Config) ->
        Node = ?config(suite_config,Config),

        ?assertNot(ros_node:has_parameter(Node, "not_existing")),
        ?assertMatch({error, parameter_not_declared}, ros_node:undeclare_parameter(Node, "not_existing")),

        ros_node:declare_parameter(Node, "to_be_removed"),
        ?assertMatch(ok, ros_node:undeclare_parameter(Node, "to_be_removed")),
        ?assertNot(ros_node:has_parameter(Node, "to_be_removed")),

        ok.

get_parameters(Config) ->
        Node = ?config(suite_config,Config),
        
        ?assertNot(ros_node:has_parameter(Node, "not_existing")),
        ?assertMatch({error, parameter_not_declared},  ros_node:get_parameter(Node, "not_existing")),

        ros_node:declare_parameter(Node, "my_string", "Hello world!"),
        ?assertMatch(#ros_parameter{name="my_string", value="Hello world!", type=?PARAMETER_STRING}, 
                ros_node:get_parameter(Node, "my_string")),
        ok.

set_parameters(Config) ->
        Node = ?config(suite_config, Config),

        
        ros_node:declare_parameter(Node, "change", 1),
        Parameter = #ros_parameter{name="change", value="2", type=?PARAMETER_STRING},
        ?assertMatch(success, ros_node:set_parameter(Node, Parameter)),
        ?assertMatch(Parameter, ros_node:get_parameter(Node, "change")),

        BadParam = #ros_parameter{name="change", value=4, type=?PARAMETER_BOOL},        
        ?assertMatch({failure, parameter_value}, ros_node:set_parameter(Node, BadParam)),  
        
        % When setting multiple parameters if one produces an error the previus are set
        % The next remaining params rest unset
        
        ros_node:declare_parameter(Node, "first", 1),
        % Missing...  ros_node:declare_parameter(Node, "second", 2),
        ros_node:declare_parameter(Node, "third", 3),
        First = #ros_parameter{name="first", value="1", type=?PARAMETER_STRING},        
        Second = #ros_parameter{name="second", value="2", type=?PARAMETER_STRING},        
        Third = #ros_parameter{name="third", value="3", type=?PARAMETER_STRING},
        ParameterList = [First, Second, Third],
        ?assertMatch({error, parameter_not_declared}, ros_node:set_parameters(Node, ParameterList)),
        ?assertMatch(First, ros_node:get_parameter(Node, "first")),
        ?assertMatch({error, parameter_not_declared}, ros_node:get_parameter(Node, "second")),
        ?assertNotMatch(Third, ros_node:get_parameter(Node, "third")),



        % now if I set a parameter type to NOT_SET, when it has already a valid type, it should be implicitly undeclared
        ?assertMatch(success, ros_node:set_parameter(Node, Third#ros_parameter{type=?PARAMETER_NOT_SET})),
        ?assertNot(ros_node:has_parameter(Node, "third")),
        % this should not occur when the param is declared without being set
        ros_node:declare_parameter(Node, "unset"),
        ?assertMatch(success, ros_node:set_parameter(Node, #ros_parameter{name = "unset", type=?PARAMETER_NOT_SET})),
        ?assert(ros_node:has_parameter(Node, "unset")),
        ok.

parameter_description(Config) ->
        Node = ?config(suite_config, Config),
        
        Value = false,
        ros_node:declare_parameter(Node, "my_bool", Value),
        %example of changing just the description
        NewD = #rcl_interfaces_parameter_descriptor{
                name = "I should not appear",
                type = ?PARAMETER_BOOL, 
                description="New Description!"},
        ?assertMatch( Value, ros_node:set_descriptor(Node, "my_bool", NewD)),
        ?assertMatch(#rcl_interfaces_parameter_descriptor{
                        name = "my_bool",
                        type = ?PARAMETER_BOOL, 
                        description="New Description!"}, 
                ros_node:describe_parameter(Node, "my_bool")),
        
        % example of changing the type, a new value must be provided
        NewD2 = #rcl_interfaces_parameter_descriptor{description="not a boolean", type=?PARAMETER_DOUBLE},
        ?assertMatch(0.7, ros_node:set_descriptor(Node, "my_bool", NewD2, 0.7)),

        NewD3 = #rcl_interfaces_parameter_descriptor{description="oops!", type=?PARAMETER_STRING},
        ?assertMatch({error, parameter_value}, ros_node:set_descriptor(Node, "my_bool", NewD3)),
        


        ok.


