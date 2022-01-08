-module(ros_node_utils).

-export([put_topic_prefix/1,
        extract_parameter_value/1,
        build_parameter_value/2,
        is_name_legal/1,
        find_param_type/1,
        param_type_is_unset/1,
        simplified_parameter_view/1,
        get_parameters_from_map/2,
        start_up_param_topics_and_services/1
    ]).

-include_lib("ros/include/ros_commons.hrl").
-include_lib("dds/include/dds_types.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_value_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_type_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_descriptor_msg.hrl").

put_topic_prefix(N) ->
    "rt/" ++ N.

extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_NOT_SET}) ->
    none;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_BOOL, bool_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_INTEGER, integer_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_DOUBLE, double_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_STRING, string_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_BYTE_ARRAY, byte_array_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_BOOL_ARRAY, bool_array_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_INTEGER_ARRAY, integer_array_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_DOUBLE_ARRAY, double_array_value = Value}) ->
    Value;
extract_parameter_value(#rcl_interfaces_parameter_value{type = ?PARAMETER_STRING_ARRAY, string_array_value = Value}) ->
    Value.



build_parameter_value(_, invalid) ->
        invalid;
build_parameter_value(_, ?PARAMETER_NOT_SET) ->
        #rcl_interfaces_parameter_value{type = ?PARAMETER_NOT_SET};
build_parameter_value(Value, ?PARAMETER_BOOL) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_BOOL, bool_value = Value};
build_parameter_value(Value, ?PARAMETER_INTEGER) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_INTEGER, integer_value = Value};
build_parameter_value(Value, ?PARAMETER_DOUBLE) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_DOUBLE, double_value = Value};
build_parameter_value(Value, ?PARAMETER_STRING) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_STRING, string_value = Value};
build_parameter_value(Value, ?PARAMETER_BYTE_ARRAY) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_BYTE_ARRAY, byte_array_value = Value};
build_parameter_value(Value, ?PARAMETER_BOOL_ARRAY) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_BOOL_ARRAY, bool_array_value = Value};
build_parameter_value(Value, ?PARAMETER_INTEGER_ARRAY) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_INTEGER_ARRAY, integer_array_value = Value};
build_parameter_value(Value, ?PARAMETER_DOUBLE_ARRAY) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_DOUBLE_ARRAY, double_array_value = Value};
build_parameter_value(Value, ?PARAMETER_STRING_ARRAY) ->
    #rcl_interfaces_parameter_value{type = ?PARAMETER_STRING_ARRAY, string_array_value = Value}.

    
is_name_legal(N) when is_list(N) ->
    SubNames = string:split(string:trim(N,both,"/"), "/", all),
    lists:all(fun io_lib:printable_latin1_list/1, SubNames) and
    lists:all(fun(S) -> 
                {match,[{0,length(S)}]} == re:run(S,"[a-z_]+[a-z_0-9]*") 
            end, 
        SubNames);
is_name_legal(_) -> false.

% could only be a list of strings
find_param_value_list_type([Elem | _] = List) when is_list(Elem) ->
    case lists:all(fun io_lib:printable_latin1_list/1, List) of
        true -> ?PARAMETER_STRING_ARRAY;
        false -> invalid
    end;
% list of integers or a string
find_param_value_list_type([Elem | _] = List) when is_integer(Elem) ->
    case lists:all(fun is_integer/1, List) of
        true ->
            case io_lib:printable_latin1_list(List) of
                true -> ?PARAMETER_STRING;
                false -> ?PARAMETER_INTEGER_ARRAY
            end;
        false ->
            invalid
    end;
find_param_value_list_type([Elem | _] = List) when is_boolean(Elem) ->
    case lists:all(fun is_boolean/1, List) of
        true -> ?PARAMETER_BOOL_ARRAY;
        false -> invalid
    end;
find_param_value_list_type([Elem | _] = List) when is_float(Elem) ->
    case lists:all(fun is_float/1, List) of
        true -> ?PARAMETER_DOUBLE_ARRAY;
        false -> invalid
    end.

find_param_type(none) ->
    ?PARAMETER_NOT_SET;
find_param_type([]) ->
    ?PARAMETER_NOT_SET;
find_param_type(Value) when is_boolean(Value) ->
    ?PARAMETER_BOOL;
find_param_type(Value) when is_integer(Value) ->
    ?PARAMETER_INTEGER;
find_param_type(Value) when is_float(Value) ->
    ?PARAMETER_DOUBLE;
find_param_type(Value) when is_list(Value) ->
    find_param_value_list_type(Value);
find_param_type(_) ->
    invalid.



param_type_is_unset({Desc,Value}) ->
    (Desc#rcl_interfaces_parameter_descriptor.type == ?PARAMETER_NOT_SET) or
    (Value#rcl_interfaces_parameter_value.type == ?PARAMETER_NOT_SET).

simplified_parameter_view({Desc,Value}) ->
    #ros_parameter{name = Desc#rcl_interfaces_parameter_descriptor.name,
                    type = Desc#rcl_interfaces_parameter_descriptor.type,
                    value = extract_parameter_value(Value)}.


start_up_param_topics_and_services({ros_node, NodeName} = NodeID) ->
    Qos_profile = #qos_profile{history = {?KEEP_ALL_HISTORY_QOS, -1}},
    % Topics
    {ok, _} =
        supervisor:start_child(
            ros_publishers_sup,
            [
                rcl_interfaces_parameter_event_msg,
                NodeID,
                put_topic_prefix("parameter_events"),
                Qos_profile
            ]
        ),
    % ROS_PARAMETERS -> Service Servers
    NodeNamePrefix = NodeName ++ "/",
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_describe_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {ros_node, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_get_parameter_types_srv, NodeNamePrefix},
                Qos_profile,
                {ros_node, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_get_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {ros_node, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_list_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {ros_node, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_set_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {ros_node, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_set_parameters_atomically_srv, NodeName ++ "/"},
                Qos_profile,
                {ros_node, NodeID}
            ]
        ),
    Publishers = [
        {ros_publisher, NodeID, put_topic_prefix("parameter_events")}
    ],
    ParameterServices = [
        {ros_service, NodeID, rcl_interfaces_describe_parameters_srv},
        {ros_service, NodeID, rcl_interfaces_get_parameter_types_srv},
        {ros_service, NodeID, rcl_interfaces_get_parameters_srv},
        {ros_service, NodeID, rcl_interfaces_list_parameters_srv},
        {ros_service, NodeID, rcl_interfaces_set_parameters_srv},
        {ros_service, NodeID, rcl_interfaces_set_parameters_atomically_srv}
    ],
    {Publishers, ParameterServices}.

get_parameters_from_map(Names, Map) ->
    [
        maps:get(
            N,
            Map,
            {
                #rcl_interfaces_parameter_descriptor{name = N, type = ?PARAMETER_NOT_SET},
                #rcl_interfaces_parameter_value{type = ?PARAMETER_NOT_SET}
            }
        )
     || N <- Names
    ].
