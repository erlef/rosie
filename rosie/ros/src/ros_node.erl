-module(ros_node).

-export([
    start_link/2,
    get_name/1,

    declare_parameter/2,
    declare_parameter/3,
    undeclare_parameter/2,

    has_parameter/2,
    get_parameter/2,
    get_parameters/2,
    set_parameter/2,
    set_parameters/2,

    describe_parameter/2,
    describe_parameters/2,
    set_descriptor/3,
    set_descriptor/4,

    create_subscription/4,
    create_publisher/3,
    create_publisher/4,
    create_client/3,
    create_service/3,
    create_service/4
]).

-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_service_listener).
-export([on_client_request/2]).

-behaviour(gen_dds_entity_owner).
-export([get_all_dds_entities/1]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("ros/include/ros_commons.hrl").
-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").

-include_lib("rmw_dds_common/src/_rosie/rmw_dds_common_participant_entities_info_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_log_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_event_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_type_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_list_parameters_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_get_parameter_types_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_get_parameters_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_set_parameters_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_set_parameters_atomically_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_describe_parameters_srv.hrl").

-record(state, {
    name,
    subscriptions = [],
    publishers = [],
    clients = [],
    services = [],
    % Parameters
    options = #ros_node_options{},
    parameters = #{
        "use_sim_time" => {
            #rcl_interfaces_parameter_descriptor{name = "use_sim_time", type = ?PARAMETER_BOOL},
            #rcl_interfaces_parameter_value{type = ?PARAMETER_BOOL, bool_value = false}
        }
    }
}).

start_link(Name, OptionRecord) ->
    gen_server:start_link(?MODULE, {Name, OptionRecord}, []).

get_name(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_name).

declare_parameter(Name, ParamName) ->
    declare_parameter(Name, ParamName, none).

declare_parameter(Name, ParamName, ParamValue) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {declare_parameter, ParamName, ParamValue}).

undeclare_parameter(Name, ParamName) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {undeclare_parameter, ParamName}).

has_parameter(Name, ParamName) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {has_parameter, ParamName}).

get_parameter(Name, ParamName) ->
    [P|_] = get_parameters(Name, [ParamName]),
    P.

get_parameters(Name, ParamNameList) ->
    [Pid|_] = pg:get_members(Name),
    gen_server:call(Pid, {get_parameters, ParamNameList}).

set_parameter(Name, Param) ->
    [R|_] = set_parameters(Name, [Param]),
    R.

set_parameters(Name, ParamList) ->
    [Pid|_] = pg:get_members(Name),
    gen_server:call(Pid, {set_parameters, ParamList}).

describe_parameter(Name, ParamName) ->
    [D|_] = describe_parameters(Name, [ParamName]),
    D.

describe_parameters(Name, ParamNames) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {describe_parameters, ParamNames}).

set_descriptor(Name,  ParamName, NewDescriptor) ->
    set_descriptor(Name,  ParamName, NewDescriptor, none).

set_descriptor(Name,  ParamName, NewDescriptor, AlternativeValue) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {set_descriptor,  ParamName, NewDescriptor, AlternativeValue}).

create_subscription(Name, raw, Topic, Callback) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_subscription, raw, Topic, Callback});
create_subscription(Name, MsgModule, TopicName, Callback) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_subscription, MsgModule, TopicName, Callback}).

create_publisher(Name, raw, Topic) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_publisher, raw, Topic});
create_publisher(Name, MsgModule, TopicName) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_publisher, MsgModule, TopicName}).

create_publisher(Name, MsgModule, TopicName, QoS) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_publisher, MsgModule, TopicName, QoS}).

create_client(Name, Service, CallbackHandler) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_client, Service, CallbackHandler}).

create_service(Name, Service, Callback) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_service, Service, Callback}).

create_service(Name, Service, QoSProfile, Callback) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_service, Service, QoSProfile, Callback}).

on_topic_msg(Name, Msg) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_topic_msg, Msg}).

on_client_request(Name, Msg) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {on_client_request, Msg}).

get_all_dds_entities(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_dds_entities).

%callbacks
%
init(
    {NodeName,
        #ros_node_options{
            namespace = N,
            enable_rosout = ROSOUT,
            start_parameter_services = StartServices,
            parameter_overrides = Override_list,
            allow_undeclared_parameters = AllowUndeclared,
            automatically_declare_parameters_from_overrides = AutoDeclareFromOverrides
        } = Options}
) ->
    NodeID = {ros_node, NodeName},
    pg:join(NodeID, self()),
    Rosout_pub =
        case ROSOUT of
            true -> [start_up_rosout(NodeID)];
            false -> []
        end,
    {ParamPublishers, ParamServices} =
        case StartServices of
            true -> start_up_param_topics_and_services(NodeID);
            false -> {[], []}
        end,

    {ok, #state{
        name = NodeName,
        options = Options,
        publishers = Rosout_pub ++ ParamPublishers,
        services = ParamServices
    }}.

handle_call({declare_parameter, ParamName, ParamValue}, _, S) ->
    {Result, NewS} = h_declare_parameter(ParamName, ParamValue, S),
    {reply, Result, NewS};
handle_call({has_parameter, ParamName}, _, #state{parameters = P} = S) ->
    {reply, lists:member(ParamName, maps:keys(P)), S};
handle_call({undeclare_parameter, ParamName}, _, S) ->
    {Result, NewS} = h_undeclare_parameter(ParamName, S),
    {reply, Result, NewS};
handle_call({get_parameters, ParamNameList}, _, S) ->
    {reply, h_get_parameters(ParamNameList, S), S};
handle_call({set_parameters, ParamList}, _, S) ->
    {Result, NewS} = h_set_parameters(ParamList, S),
    {reply, Result, NewS};
handle_call({describe_parameters, ParamNameList}, _, S) ->
    {reply, h_describe_parameters(ParamNameList, S), S};
handle_call({set_descriptor,  ParamName, NewDescriptor, AlternativeValue}, _, S) ->
    {ParamValue, NewS} = h_set_descriptor( ParamName, NewDescriptor, AlternativeValue, S),
    {reply, ParamValue, NewS};


handle_call(
    {create_subscription, raw, Topic, CallbackHandler}, _, #state{subscriptions = SUBS} = S
) ->
    ID = h_create_subscription(raw, Topic, CallbackHandler, S),
    {reply, ID, S#state{subscriptions = [ID | SUBS]}};
handle_call(
    {create_subscription, MsgModule, TopicName, CallbackHandler},
    _,
    #state{subscriptions = SUBS} = S
) ->
    ID = h_create_subscription(MsgModule, put_topic_prefix(TopicName), CallbackHandler, S),
    {reply, ID, S#state{subscriptions = [ID | SUBS]}};
handle_call({create_publisher, raw, Topic}, _, #state{publishers = PUBS} = S) ->
    ID = h_create_raw_publisher(raw, Topic, S),
    {reply, ID, S#state{publishers = [ID | PUBS]}};
handle_call({create_publisher, MsgModule, TopicName}, _, #state{publishers = PUBS} = S) ->
    ID = h_create_publisher(MsgModule, put_topic_prefix(TopicName), #qos_profile{}, S),
    {reply, ID, S#state{publishers = [ID | PUBS]}};
handle_call({create_publisher, MsgModule, TopicName, QoS}, _, #state{publishers = PUBS} = S) ->
    ID = h_create_publisher(MsgModule, put_topic_prefix(TopicName), QoS, S),
    {reply, ID, S#state{publishers = [ID | PUBS]}};
handle_call({create_client, Service, CallbackHandler}, _, #state{clients = Clients} = S) ->
    ID = h_create_client(Service, CallbackHandler, S),
    {reply, ID, S#state{clients = [ID | Clients]}};
handle_call({create_service, Service, CallbackHandler}, _, #state{services = SRVs} = S) ->
    ID = h_create_service(Service, CallbackHandler, S),
    {reply, ID, S#state{services = [ID | SRVs]}};
handle_call({create_service, Service, QoSProfile, CallbackHandler}, _, #state{services = SRVs} = S) ->
    ID = h_create_service_qos(Service, QoSProfile, CallbackHandler, S),
    {reply, ID, S#state{services = [ID | SRVs]}};
handle_call(get_name, _, #state{name = N} = S) ->
    {reply, N, S};
handle_call({on_client_request, {_, Msg}}, _, S) ->
    io:format("ROS_NODE: REQUEST ~p\n", [Msg]),
    {Result, NewState} = h_parameter_request(Msg, S),
    {reply, Result, NewState};
handle_call(
    get_all_dds_entities,
    _,
    #state{
        publishers = PUBS,
        subscriptions = SUBS,
        clients = CLIENTS,
        services = SERVICES
    } = S
) ->
    % io:format("Services: ~p\n",[SERVICES]),
    Entities =
        [ros_publisher:get_all_dds_entities(P) || P <- PUBS] ++
            [ros_subscription:get_all_dds_entities(P) || P <- SUBS] ++
            [ros_client:get_all_dds_entities(P) || P <- CLIENTS] ++
            [ros_service:get_all_dds_entities(P) || P <- SERVICES],
    % io:format("~p\n",[Entities]),
    {Writers, Readers} = lists:unzip(Entities),
    {reply, {lists:flatten(Writers), lists:flatten(Readers)}, S}.

handle_cast({on_topic_msg, Msg}, S) ->
    case Msg of
        %#rmw_dds_common_participant_entities_info{} -> io:format("ROS_NODE: TOPIC ~p\n",[Msg]);
        #rcl_interfaces_log{} -> io:format("ROS_NODE: ROSOUT ~p\n", [Msg]);
        #rcl_interfaces_parameter_event{} -> io:format("ROS_NODE: PARAM_EVENT ~p\n", [Msg]);
        _ -> ok
    end,
    {noreply, S}.

% HELPERS

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

h_declare_parameter(ParamName, ParamValue, #state{parameters = Map} = S) ->
    Type = find_param_type(ParamValue),
    NewParam = {
        #rcl_interfaces_parameter_descriptor{name = ParamName, type = Type},
        build_parameter_value(ParamValue, Type)
    },
    case Type of
        invalid -> {invalid_type, S};
        _ -> {{ParamName, ParamValue, Type}, S#state{parameters = Map#{ParamName => NewParam}}}
    end.

h_undeclare_parameter(ParamName, #state{parameters = Map} = S) ->
    case lists:member(ParamName, maps:keys(Map)) of
        true ->
            case maps:get(ParamName, Map) of
                {#rcl_interfaces_parameter_descriptor{read_only = true}, _} ->
                    {parameter_immutable, S};
                _ ->
                    {ok, S#state{parameters = maps:remove(ParamName, Map)}}
            end;
        false ->
            {parameter_not_declared, S}
    end.

param_type_is_unset({Desc,Value}) ->
    (Desc#rcl_interfaces_parameter_descriptor.type == ?PARAMETER_NOT_SET) or
    (Value#rcl_interfaces_parameter_value.type == ?PARAMETER_NOT_SET).

simplified_parameter_view({Desc,Value}) ->
    #ros_parameter{name = Desc#rcl_interfaces_parameter_descriptor.name,
                    type = Desc#rcl_interfaces_parameter_descriptor.type,
                    value = extract_parameter_value(Value)}.


h_get_parameters(ParamNameList, #state{options = 
    #ros_node_options{allow_undeclared_parameters=ALLOW_UNDECLARED}, 
                    parameters=P}) -> 
    Parameters = get_parameters_from_map(ParamNameList,P),
    case not ALLOW_UNDECLARED and lists:any(fun param_type_is_unset/1, Parameters) of 
        true -> parameter_not_declared_exception;
        false -> lists:map(fun simplified_parameter_view/1, Parameters)
    end.

set_parameter_in_map( #ros_parameter{name = N , value = V, type = T}, 
        #state{ options = #ros_node_options{allow_undeclared_parameters = ALLOW_UNDECLARED},
                parameters = Pmap}= S) -> 
    case lists:member(N, maps:keys(Pmap)) of
        true -> {Desc,_} = maps:get(N,Pmap),
                maps:put(N, {Desc#rcl_interfaces_parameter_descriptor{type = T}, 
                            build_parameter_value(V, T)},
                            Pmap);
        false -> case ALLOW_UNDECLARED of
                    true -> NewS = h_declare_parameter(N, V, S), 
                            NewS#state.parameters;
                    false -> undeclared
                end
    end.

h_set_parameters(ParamList, S) ->
    h_set_parameters(ParamList, [], S).

h_set_parameters([], Results, S) ->
    {Results, S};
h_set_parameters([Param|TL], Results, S) ->
    case set_parameter_in_map(Param, S) of
        undeclared ->  {parameter_not_declared_exception, S};
        failed ->  h_set_parameters(TL, [ failed | Results], S);
        NewP when is_map(NewP) -> h_set_parameters(TL, [ success | Results], S#state{parameters = NewP})
    end.

h_describe_parameters(ParamNameList, #state{
                options = #ros_node_options{allow_undeclared_parameters=ALLOW_UNDECLARED}, 
                parameters=P} = S) ->
    Parameters = get_parameters_from_map(ParamNameList,P),
    case not ALLOW_UNDECLARED and lists:any(fun param_type_is_unset/1, Parameters) of 
        true -> parameter_not_declared_exception;
        false -> [ D || {D,V} <- Parameters]
    end.

update_existing_param_desc(N, NewDescriptor, #state{parameters=P} = S) ->
    {_,V} = maps:get(N,P),
    { extract_parameter_value(V), S#state{parameters = maps:put(N,{NewDescriptor#rcl_interfaces_parameter_descriptor{name = N}, V},P)}}.
    
update_existing_param_desc_and_val(N, NewDescriptor, AltVal, #state{parameters=P} = S) ->
    V = build_parameter_value(AltVal, NewDescriptor#rcl_interfaces_parameter_descriptor.type),
    { AltVal, S#state{parameters = maps:put(N,{NewDescriptor#rcl_interfaces_parameter_descriptor{name = N}, V},P)}}.

implicit_declare_param_with_desc(N, NewDescriptor, #state{parameters=P} = S) ->
    {_,V} = maps:get(N,P),
    { extract_parameter_value(V), S#state{parameters = maps:put(N,{NewDescriptor#rcl_interfaces_parameter_descriptor{name = N}, V},P)}}.

implicit_declare_param_with_desc_and_val(N, NewDescriptor, AltVal, #state{parameters=P} = S) ->
    V = build_parameter_value(AltVal, NewDescriptor#rcl_interfaces_parameter_descriptor.type),
    { AltVal, S#state{parameters = maps:put(N,{NewDescriptor#rcl_interfaces_parameter_descriptor{name = N}, V},P)}}.


h_set_descriptor( ParamName, NewDescriptor, AltVal, #state{
                options = #ros_node_options{allow_undeclared_parameters=ALLOW_UNDECLARED}, 
                parameters=Pmap} = S) ->
    ParamDeclared = lists:member(ParamName, maps:keys(Pmap)),
    {IsOldParamReadOnly, OldValCompatibleWithNewDesc }= case ParamDeclared of
        true -> 
                [{OldD,OldV}|_] = get_parameters_from_map([ParamName],Pmap),
                {OldD#rcl_interfaces_parameter_descriptor.read_only, 
                OldV#rcl_interfaces_parameter_value.type == NewDescriptor#rcl_interfaces_parameter_descriptor.type};
        false -> false
    end,
    AltValType = find_param_type(AltVal),
    AltValTypeMatchesDescriptionType = (NewDescriptor#rcl_interfaces_parameter_descriptor.type == AltValType) and (AltValType /= invalid),
    case {ParamDeclared, IsOldParamReadOnly, OldValCompatibleWithNewDesc, AltValTypeMatchesDescriptionType, ALLOW_UNDECLARED, AltVal}   of
        {true,true,_,_,_,_} ->  {parameter_read_only_exception, S};
        {false,_,_,_,false,_} ->  {parameter_not_declared_exception, S};
        {_,_,false,_,_,none} ->  {parameter_value_exception, S};
        {_,_,_,false,_,AltVal} when AltVal /= none->  {parameter_value_exception, S};
        {true,false,true,_,_,none} -> update_existing_param_desc(ParamName, NewDescriptor, S);
        {true,false,_,true,_,AltVal} -> update_existing_param_desc_and_val(ParamName, NewDescriptor, AltVal, S);
        {false,_,_,_,true,none} -> implicit_declare_param_with_desc(ParamName, NewDescriptor, S);
        {false,_,_,_,true,AltVal} -> implicit_declare_param_with_desc_and_val(ParamName, NewDescriptor, AltVal, S)
    end.


% ros endpoints creation

put_topic_prefix(N) ->
    "rt/" ++ N.

h_create_subscription(raw, #dds_user_topic{name = TopicName} = Topic, CallbackHandler, #state{
    name = Name
}) ->
    {ok, _} =
        supervisor:start_child(ros_subscriptions_sup, [
            raw, {ros_node, Name}, Topic, CallbackHandler
        ]),
    ros_context:update_ros_discovery(),
    {ros_subscription, {ros_node, Name}, TopicName};
h_create_subscription(MsgModule, TopicName, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_subscriptions_sup, [
            MsgModule, {ros_node, Name}, TopicName, CallbackHandler
        ]),
    ros_context:update_ros_discovery(),
    {ros_subscription, {ros_node, Name}, TopicName}.

h_create_raw_publisher(raw, #dds_user_topic{name = TopicName} = Topic, #state{name = Name}) ->
    {ok, _} = supervisor:start_child(ros_publishers_sup, [raw, {ros_node, Name}, Topic]),
    ros_context:update_ros_discovery(),
    {ros_publisher, {ros_node, Name}, TopicName}.

h_create_publisher(MsgModule, TopicName, QoS, #state{name = Name}) ->
    {ok, _} = supervisor:start_child(ros_publishers_sup, [
        MsgModule, {ros_node, Name}, TopicName, QoS
    ]),
    ros_context:update_ros_discovery(),
    {ros_publisher, {ros_node, Name}, TopicName}.

h_create_client({Service, Prefix}, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(
            ros_clients_sup,
            [{ros_node, Name}, {Service, Prefix}, CallbackHandler]
        ),
    ros_context:update_ros_discovery(),
    {ros_client, {ros_node, Name}, Service};
h_create_client(Service, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_clients_sup, [{ros_node, Name}, Service, CallbackHandler]),
    ros_context:update_ros_discovery(),
    {ros_client, {ros_node, Name}, Service}.

h_create_service(Service, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_services_sup, [{ros_node, Name}, Service, CallbackHandler]),
    ros_context:update_ros_discovery(),
    {ros_service, {ros_node, Name},
        case Service of
            {S, _} -> S;
            _ -> Service
        end}.

h_create_service_qos(Service, QoSProfile, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [{ros_node, Name}, Service, QoSProfile, CallbackHandler]
        ),
    ros_context:update_ros_discovery(),
    {ros_service, {ros_node, Name},
        case Service of
            {S, _} -> S;
            _ -> Service
        end}.

start_up_rosout(NodeID) ->
    Qos_profile = #qos_profile{history = {?KEEP_ALL_HISTORY_QOS, -1}},
    {ok, _} =
        supervisor:start_child(
            ros_publishers_sup,
            [
                rcl_interfaces_log_msg,
                NodeID,
                put_topic_prefix("rosout"),
                Qos_profile
            ]
        ),
    {ros_publisher, NodeID, put_topic_prefix("rosout")}.

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
                {?MODULE, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_get_parameter_types_srv, NodeNamePrefix},
                Qos_profile,
                {?MODULE, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_get_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {?MODULE, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_list_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {?MODULE, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_set_parameters_srv, NodeNamePrefix},
                Qos_profile,
                {?MODULE, NodeID}
            ]
        ),
    {ok, _} =
        supervisor:start_child(
            ros_services_sup,
            [
                NodeID,
                {rcl_interfaces_set_parameters_atomically_srv, NodeName ++ "/"},
                Qos_profile,
                {?MODULE, NodeID}
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

mark_set_rq({Key, NEWV}, Map) ->
    case get_parameters_from_map([Key], Map) of
        [{D, V}] when
            (V#rcl_interfaces_parameter_value.type /= ?PARAMETER_NOT_SET) and
                (NEWV#rcl_interfaces_parameter_value.type /= ?PARAMETER_NOT_SET) and
                (V#rcl_interfaces_parameter_value.type == NEWV#rcl_interfaces_parameter_value.type)
        ->
            {true, {Key, NEWV}};
        _ ->
            {false, "type mismatch or param \"" ++ Key ++ "\" undefined"}
    end.

put_new_vals_for_params([], Map) ->
    Map;
put_new_vals_for_params([{Key, NEWV} | TL], Map) ->
    {D, _} = maps:get(Key, Map),
    put_new_vals_for_params(TL, Map#{Key => {D, NEWV}}).

h_parameter_request(
    #rcl_interfaces_set_parameters_rq{parameters = Params}, #state{parameters = P} = S
) ->
    K_NEWV = [{N, V} || #rcl_interfaces_parameter{name = N, value = V} <- Params],
    MarkedRequests = lists:map(fun({N, V}) -> mark_set_rq({N, V}, P) end, K_NEWV),
    LegalRequests = [DATA || {R, DATA} <- MarkedRequests, R],
    NewParamMap = put_new_vals_for_params(LegalRequests, P),
    {
        #rcl_interfaces_set_parameters_rp{
            results = [
                #rcl_interfaces_set_parameters_result{
                    successful = R,
                    reason =
                        case R of
                            false -> Reason;
                            _ -> ""
                        end
                }
             || {R, Reason} <- MarkedRequests
            ]
        },
        S#state{parameters = NewParamMap}
    };
h_parameter_request(
    #rcl_interfaces_set_parameters_atomically_rq{parameters = Params}, #state{parameters = P} = S
) ->
    {
        #rcl_interfaces_set_parameters_atomically_rp{
            result = #rcl_interfaces_set_parameters_result{
                successful = false, reason = "Not implemented by ROSIE node"
            }
        },
        S
    };
h_parameter_request(
    #rcl_interfaces_describe_parameters_rq{names = Names}, #state{parameters = P} = S
) ->
    {
        #rcl_interfaces_describe_parameters_rp{
            descriptors = [D || {D, _} <- get_parameters_from_map(Names, P)]
        },
        S
    };
h_parameter_request(
    #rcl_interfaces_list_parameters_rq{prefixes = Prefs, depth = D}, #state{parameters = P} = S
) ->
    {
        #rcl_interfaces_list_parameters_rp{
            result = #rcl_interfaces_list_parameters_result{
                names = maps:keys(P)
            }
        },
        S
    };
h_parameter_request(
    #rcl_interfaces_get_parameter_types_rq{names = Names}, #state{parameters = P} = S
) ->
    Parameters = get_parameters_from_map(Names, P),
    {
        #rcl_interfaces_get_parameter_types_rp{
            types = [T || {_, #rcl_interfaces_parameter_value{type = T}} <- Parameters]
        },
        S
    };
h_parameter_request(#rcl_interfaces_get_parameters_rq{names = Names}, #state{parameters = P} = S) ->
    {
        #rcl_interfaces_get_parameters_rp{
            values = [Value || {_, Value} <- get_parameters_from_map(Names, P)]
        },
        S
    }.
