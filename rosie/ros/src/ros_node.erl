-module(ros_node).

-export([start_link/1, get_name/1, create_subscription/4, create_publisher/3,
         create_publisher/4, create_client/3, create_service/3, create_service/4]).

-behaviour(gen_subscription_listener).

-export([on_topic_msg/2]).


-behaviour(gen_service_listener).
-export([on_client_request/2]).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("rmw_dds_common/src/_rosie/rmw_dds_common_participant_entities_info_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_list_parameters_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_get_parameter_types_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_get_parameters_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_set_parameters_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_set_parameters_atomically_srv.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_parameter_type_msg.hrl").
-include_lib("rcl_interfaces/src/_rosie/rcl_interfaces_describe_parameters_srv.hrl").

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").

% -include_lib("dds/include/rtps_constants.hrl").

-record(state, {
    name, 
    discovery_pub, 
    discovery_sub, 
    parameters = #{ 
        "use_sim_time" => {
            #rcl_interfaces_parameter_descriptor{name="use_sim_time",type=?PARAMETER_BOOL},
            #rcl_interfaces_parameter_value{type=?PARAMETER_BOOL,bool_value=false}
        }}
}).

start_link(Name) ->
    gen_server:start_link(?MODULE, Name, []).

get_name(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_name).

create_subscription(Name, MsgModule, TopicName, Callback) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {create_subscription, MsgModule, TopicName, Callback}).

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


%callbacks
%
init(NodeName) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    NodeID = {ros_node, NodeName},
    pg:join(NodeID, self()),
    Qos_profile =
        #qos_profile{durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
                     history = {?KEEP_ALL_HISTORY_QOS, -1}},

    {ok, _} = supervisor:start_child(ros_subscriptions_sup,
                               [rmw_dds_common_participant_entities_info_msg,
                                "ros_discovery_info",
                                Qos_profile,
                                 {?MODULE, NodeID}]),
    {ok, _} = supervisor:start_child(ros_publishers_sup, [
                                    rmw_dds_common_participant_entities_info_msg,
                                    Qos_profile,
                                    "ros_discovery_info"]),

    start_up_default_ros2_topics_and_services(NodeID),

    update_ros_discovery(NodeName),
    {ok,
     #state{name = NodeName,
            discovery_pub = {ros_publisher, "ros_discovery_info"},
            discovery_sub = {ros_subscription, "ros_discovery_info"}}}.

handle_call({create_subscription, MsgModule, TopicName, CallbackHandler}, _, S) ->
    {reply,
     h_create_subscription(MsgModule, put_topic_prefix(TopicName), CallbackHandler, S),
     S};
handle_call({create_publisher, MsgModule, TopicName}, _, S) ->
    {reply, h_create_publisher(MsgModule, put_topic_prefix(TopicName), S), S};
handle_call({create_publisher, MsgModule, TopicName, QoS}, _, S) ->
    {reply, h_create_publisher_qos(MsgModule, put_topic_prefix(TopicName), QoS, S), S};
handle_call({create_client, Service, CallbackHandler}, _, S) ->
    {reply, h_create_client(Service, CallbackHandler, S), S};
handle_call({create_service, Service, CallbackHandler}, _, S) ->
    {reply, h_create_service(Service, CallbackHandler, S), S};
handle_call({create_service, Service, QoSProfile, CallbackHandler}, _, S) ->
    {reply, h_create_service_qos(Service, QoSProfile, CallbackHandler, S), S};
handle_call(get_name, _, #state{name = N} = S) ->
    {reply, N, S};
handle_call({on_client_request, {_ , Msg}}, _, S) ->
    io:format("ROS_NODE: REQUEST ~p\n",[Msg]),
    {Result, NewState} = h_parameter_request(Msg,S),
    {reply, Result, NewState}.

handle_cast({on_topic_msg, Msg}, S) ->
    %io:format("ROS_NODE: TOPIC ~p\n",[Msg]),
    {noreply, S}.

% HELPERS
%
%
%

put_topic_prefix(N) ->
    "rt/" ++ N.

% h_create_subscription(MsgModule,TopicName,{Name, Module}) ->
%         SUB = dds_domain_participant:get_default_subscriber(dds),
%         Topic = #user_topic{type_name= MsgModule:get_type() , name=TopicName},
%         DR = dds_subscriber:create_datareader(SUB, Topic),
%         dds_data_r:set_listener(DR, {Name, Module});

guid_to_gid(#guId{prefix = PREFIX, entityId = #entityId{key = KEY, kind = KIND}}) ->
    #rmw_dds_common_gid{data = binary_to_list(<<PREFIX/binary, KEY/binary, KIND, 0:64>>)}.

update_ros_discovery(NodeName) ->
    PUB = dds_domain_participant:get_default_publisher(dds),
    SUB = dds_domain_participant:get_default_subscriber(dds),

    Wgids =
        [guid_to_gid(GUID)
         || {_, _, {data_w_of, GUID}} <- dds_publisher:get_all_data_writers(PUB)],
    Rgids =
        [guid_to_gid(GUID)
         || {_, _, {data_r_of, GUID}} <- dds_subscriber:get_all_data_readers(SUB)],

    #participant{guid = P_GUID} = rtps_participant:get_info(participant),
    P_GID = guid_to_gid(P_GUID),
    NodeEntity =
        #rmw_dds_common_node_entities_info{node_namespace = "/",
                                           node_name = NodeName,
                                           reader_gid_seq = Rgids,
                                           writer_gid_seq = Wgids},
    Msg = #rmw_dds_common_participant_entities_info{gid = P_GID,
                                                    node_entities_info_seq = [NodeEntity]},
    ros_publisher:publish({ros_publisher, "ros_discovery_info"}, Msg).

h_create_subscription(MsgModule, TopicName, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_subscriptions_sup, [MsgModule, TopicName, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_subscription, TopicName}.

h_create_publisher(MsgModule, TopicName, #state{name = Name}) ->
    {ok, _} = supervisor:start_child(ros_publishers_sup, [MsgModule, TopicName]),
    update_ros_discovery(Name),
    {ros_publisher, TopicName}.

h_create_publisher_qos(MsgModule, TopicName, QoS, #state{name = Name}) ->
    {ok, _} = supervisor:start_child(ros_publishers_sup, [MsgModule, QoS, TopicName]),
    update_ros_discovery(Name),
    {ros_publisher, TopicName}.

h_create_client({Service, Prefix}, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_clients_sup,
                               [{ros_node, Name}, {Service, Prefix}, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_client, Service};
h_create_client(Service, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_clients_sup, [{ros_node, Name}, Service, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_client, Service}.

h_create_service({Service, Prefix}, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [{ros_node, Name}, {Service, Prefix}, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_service, Service};
h_create_service(Service, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_services_sup, [{ros_node, Name}, Service, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_service, Service}.

h_create_service_qos({Service, Prefix},
                     QoSProfile,
                     CallbackHandler,
                     #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [{ros_node, Name}, {Service, Prefix}, QoSProfile, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_service, Service};
h_create_service_qos(Service, QoSProfile, CallbackHandler, #state{name = Name}) ->
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [{ros_node, Name}, Service, QoSProfile, CallbackHandler]),
    update_ros_discovery(Name),
    {ros_service, Service}.



start_up_default_ros2_topics_and_services({ros_node,NodeName}=NodeID) ->
    Qos_profile = #qos_profile{ history = {?KEEP_ALL_HISTORY_QOS, -1}},
    % Topics
    {ok, _} =
        supervisor:start_child(ros_publishers_sup,
                                [rcl_interfaces_parameter_event_msg,
                                Qos_profile,                                
                                put_topic_prefix("parameter_events")]),
    {ok, _} =
        supervisor:start_child(ros_publishers_sup,
                                [rcl_interfaces_log_msg,
                                Qos_profile,                                
                                put_topic_prefix("rosout")]),
    % ROS_PARAMETERS -> Service Servers
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [NodeID, 
                               {rcl_interfaces_describe_parameters_srv, NodeName++"/"}, 
                               Qos_profile, 
                               {?MODULE, NodeID}]),
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [NodeID, 
                               {rcl_interfaces_get_parameter_types_srv, NodeName++"/"}, 
                               Qos_profile, 
                               {?MODULE, NodeID}]),
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [NodeID, 
                               {rcl_interfaces_get_parameters_srv, NodeName++"/"}, 
                               Qos_profile, 
                               {?MODULE, NodeID}]),
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [NodeID, 
                               {rcl_interfaces_list_parameters_srv, NodeName++"/"}, 
                               Qos_profile, 
                               {?MODULE, NodeID}]),
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [NodeID, 
                               {rcl_interfaces_set_parameters_srv, NodeName++"/"}, 
                               Qos_profile, 
                               {?MODULE, NodeID}]),
    {ok, _} =
        supervisor:start_child(ros_services_sup,
                               [NodeID, 
                               {rcl_interfaces_set_parameters_atomically_srv, NodeName++"/"}, 
                               Qos_profile, 
                               {?MODULE, NodeID}]),
    ok.

get_parameters(Names,Map) ->
    [ maps:get(N, Map, { 
        #rcl_interfaces_parameter_descriptor{name=N,type=?PARAMETER_NOT_SET},
        #rcl_interfaces_parameter_value{type=?PARAMETER_NOT_SET}
    }) || N <- Names].

mark_set_rq({Key, NEWV}, Map) -> 
    case get_parameters([Key],Map) of
        [{D,V}] when 
                (V#rcl_interfaces_parameter_value.type /= ?PARAMETER_NOT_SET) and
                (NEWV#rcl_interfaces_parameter_value.type /= ?PARAMETER_NOT_SET) and
                (V#rcl_interfaces_parameter_value.type == NEWV#rcl_interfaces_parameter_value.type) -> {true, {Key, NEWV}};
        _  -> {false, "type mismatch or param \""++Key++"\" undefined"}
    end.

put_new_vals_for_params([], Map) ->
    Map;
put_new_vals_for_params([{Key, NEWV}| TL], Map) ->
    {D,_} = maps:get(Key, Map),
    put_new_vals_for_params(TL, Map#{Key => {D, NEWV}}).

h_parameter_request(#rcl_interfaces_set_parameters_rq{parameters=Params},#state{parameters=P}=S) ->    
    K_NEWV = [ { N, V} || #rcl_interfaces_parameter{name=N,value=V} <- Params],
    MarkedRequests = lists:map(fun({N, V}) -> mark_set_rq({N, V},P) end, K_NEWV),
    LegalRequests = [ DATA || {R, DATA} <- MarkedRequests, R ],
    NewParamMap = put_new_vals_for_params(LegalRequests,P),
    {#rcl_interfaces_set_parameters_rp{
        results= [ #rcl_interfaces_set_parameters_result{successful=R, reason= case R of false -> Reason; _ -> "" end} 
                    || {R,Reason} <- MarkedRequests]
    }, S#state{parameters=NewParamMap}};
h_parameter_request(#rcl_interfaces_set_parameters_atomically_rq{parameters=Params},#state{parameters=P}=S) ->
    %io:format("~p\n",[[ D || {D,_} <- get_parameters(Names,P)]]),
    {#rcl_interfaces_set_parameters_atomically_rp{
        result= #rcl_interfaces_set_parameters_result{successful=false,reason="Not implemented by ROSIE node"}
    },S};
h_parameter_request(#rcl_interfaces_describe_parameters_rq{names=Names},#state{parameters=P}=S) ->
    %io:format("~p\n",[[ D || {D,_} <- get_parameters(Names,P)]]),
    {#rcl_interfaces_describe_parameters_rp{
        descriptors= [ D || {D,_} <- get_parameters(Names,P)]
    },S};
h_parameter_request(#rcl_interfaces_list_parameters_rq{prefixes=Prefs,depth=D},#state{parameters=P}=S) ->
    {#rcl_interfaces_list_parameters_rp{
        result=#rcl_interfaces_list_parameters_result{
                names=maps:keys(P)
            }
    },S};
h_parameter_request(#rcl_interfaces_get_parameter_types_rq{names=Names},#state{parameters=P}=S) ->
    Parameters = get_parameters(Names,P),
    {#rcl_interfaces_get_parameter_types_rp{
        types=[ T || {_,#rcl_interfaces_parameter_value{type=T}} <- Parameters]
    },S};
h_parameter_request(#rcl_interfaces_get_parameters_rq{names=Names},#state{parameters=P}=S) ->
    {#rcl_interfaces_get_parameters_rp{
        values=[ Value || {_,Value} <- get_parameters(Names,P)]
    },S}.