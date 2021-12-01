-module(ros_context).
% internal
-export([start_link/0]).
% API
-export([
    create_node/1, 
    destroy_node/1, 
    create_action_client/3, 
    create_action_server/3,
    update_ros_discovery/0]).

-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("rmw_dds_common/src/_rosie/rmw_dds_common_participant_entities_info_msg.hrl").
-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").
-include_lib("ros/include/ros_commons.hrl").

-record(node_entry, { action_clients = [], action_servers = []}).

-record(state, {
    ros_nodes = #{},
    discovery_publisher,
    discovery_subscriber
}).

%API

start_link() ->
    gen_server:start_link({local, ?ROS_CONTEXT}, ?MODULE, #state{}, []).

create_node(Name) ->
    gen_server:call(?ROS_CONTEXT, {create_node, Name, #ros_node_options{}}).

create_node(Name, OptionRecord) ->
    gen_server:call(?ROS_CONTEXT, {create_node, Name, OptionRecord}).

destroy_node(Name) ->
    gen_server:call(?ROS_CONTEXT, {destroy_node, Name}).

create_action_client(Node, ActionInterface, CallbackHandler) ->
    gen_server:call(?ROS_CONTEXT,
                    {create_action_client, Node, ActionInterface, CallbackHandler}).

create_action_server(Node, ActionInterface, CallbackHandler) ->
    gen_server:call(?ROS_CONTEXT,
                    {create_action_server, Node, ActionInterface, CallbackHandler}).

on_topic_msg(Name, Msg) ->
    gen_server:cast(?ROS_CONTEXT, {on_topic_msg, Msg}).

update_ros_discovery() ->
    gen_server:cast(?ROS_CONTEXT, update_ros_discovery).

% callbacks
init(S) ->
    process_flag(trap_exit, true),

    Qos_profile = #qos_profile{
        durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
        history = {?KEEP_ALL_HISTORY_QOS, -1}
    },

    {ok, _} = supervisor:start_child(
       ros_subscriptions_sup,
       [
           rmw_dds_common_participant_entities_info_msg,
           ?ROS_CONTEXT,
           "ros_discovery_info",
           Qos_profile,
           {?MODULE, ?ROS_CONTEXT}
       ]
    ),
    {ok, _} = supervisor:start_child(ros_publishers_sup, 
        [
            rmw_dds_common_participant_entities_info_msg,
            ?ROS_CONTEXT,
            "ros_discovery_info",
            Qos_profile
        ]
    ),

    {ok, S#state{
        discovery_publisher = {ros_publisher, ?ROS_CONTEXT, "ros_discovery_info"},
        discovery_subscriber = {ros_subscription, ?ROS_CONTEXT, "ros_discovery_info"}
    }}.


terminate(Reason, #state{ros_nodes = NODES,
                        discovery_publisher = DP,
                        discovery_subscriber = DS} = S) ->
    [ begin 
        [ros_action_client:destroy(C) || C <- AC],
        [ros_action_server:destroy(S) || S <- AS]
    end || #node_entry{action_clients=AC, action_servers= AS} <- maps:values(NODES)],
    [ ros_node:destroy(N) || N <- maps:keys(NODES)],
    h_update_ros_discovery(S#state{ros_nodes= #{}}),
    ros_subscription:destroy(DS),
    ros_publisher:destroy(DP),
    ok.

handle_call({create_node, Name, Options}, _, #state{ros_nodes=NODES} = S) ->
    {ok, _} = supervisor:start_child(ros_node_sup, [Name, Options]),
    ros_context:update_ros_discovery(),
    {reply, {ros_node, Name}, S#state{ros_nodes = maps:put({ros_node, Name}, #node_entry{}, NODES) }};
handle_call({destroy_node, Name}, _, #state{ros_nodes=NODES} = S) ->
    #node_entry{action_clients=AC, action_servers= AS} = maps:get(Name, NODES),
    [ros_action_client:destroy(C) || C <- AC],
    [ros_action_server:destroy(S) || S <- AS],
    ros_node:destroy(Name),
    ros_context:update_ros_discovery(),
    {reply, ok, S#state{ros_nodes = maps:remove(Name, NODES) } };
handle_call({create_action_client, Node, ActionInterface, CallbackHandler}, _, S) ->
    {reply, h_create_action_client(Node, ActionInterface, CallbackHandler), S};
handle_call({create_action_server, Node, ActionInterface, CallbackHandler}, _, S) ->
    {reply, h_create_action_server(Node, ActionInterface, CallbackHandler), S}.

handle_cast(update_ros_discovery, S) ->
    h_update_ros_discovery(S), 
    {noreply, S};
handle_cast({on_topic_msg, Msg}, S) ->    
    {noreply, h_on_topic_msg(Msg,S)}.

handle_info(_, S) ->
    {noreply, S}.

h_create_action_client(Node, ActionInterface, CallbackHandler) ->
    {ok, _} =
        supervisor:start_child(ros_action_clients_sup, [Node, ActionInterface, CallbackHandler]),
    {ros_action_client, Node, ActionInterface}.

h_create_action_server(Node, ActionInterface, CallbackHandler) ->
    {ok, _} =
        supervisor:start_child(ros_action_servers_sup, [Node, ActionInterface, CallbackHandler]),
    {ros_action_server, Node, ActionInterface}.

h_on_topic_msg(Msg,S) ->
    S.

guid_to_gid(#guId{prefix = PREFIX, entityId = #entityId{key = KEY, kind = KIND}}) ->
    #rmw_dds_common_gid{data = binary_to_list(<<PREFIX/binary, KEY/binary, KIND, 0:64>>)}.

build_node_entity_info({NodeName, {Writers, Readers}}) ->
    Wgids = [ guid_to_gid(GUID) || {data_w_of, GUID} <- Writers],
    Rgids = [ guid_to_gid(GUID) || {data_r_of, GUID} <- Readers],

    #rmw_dds_common_node_entities_info{
            node_namespace = "/",
            node_name = NodeName,
            reader_gid_seq = Rgids,
            writer_gid_seq = Wgids
    }.

h_update_ros_discovery(#state{ ros_nodes= NODES, discovery_publisher = DP}) ->
    NodesEntities = [ {Name, ros_node:get_all_dds_entities(N)} || 
           {ros_node, Name} = N <- maps:keys(NODES)],
    NodeEntitiesInfos = lists:map( fun build_node_entity_info/1, NodesEntities),
    
    #participant{guid = P_GUID} = rtps_participant:get_info(participant),
    P_GID = guid_to_gid(P_GUID),

    Msg = #rmw_dds_common_participant_entities_info{
        gid = P_GID,
        node_entities_info_seq = NodeEntitiesInfos
    },
    ros_publisher:publish(DP, Msg).
