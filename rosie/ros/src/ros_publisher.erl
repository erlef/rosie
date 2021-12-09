-module(ros_publisher).

% API
-export([ 
    publish/2,
    get_subscription_count/1
]).

% Internal use
-export([start_link/4, start_link/3, destroy/1]).

-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3, handle_cast/2]).

-behaviour(gen_dds_entity_owner).
-export([get_all_dds_entities/1]).

-include_lib("dds/include/dds_types.hrl").

-record(state,
        {msg_module, 
        node, 
        topic, 
        dds_data_writer}).

start_link(MsgModule, Node, TopicName, QoSProfile) ->
    gen_server:start_link(?MODULE,
                          #state{msg_module = MsgModule,
                                node = Node, 
                                 topic= #dds_user_topic{name = TopicName,
                                                type_name = MsgModule:get_type(),
                                                qos_profile = QoSProfile}},
                          []).

start_link(raw, Node, Topic) ->
    gen_server:start_link(?MODULE,
                          #state{
                            msg_module = raw, 
                            node = Node, 
                            topic = Topic},
                          []);
start_link(MsgModule, Node, TopicName) ->
    gen_server:start_link(?MODULE,
                          #state{
                            msg_module = MsgModule, 
                            node = Node, 
                            topic = #dds_user_topic{name = TopicName,
                                                type_name = MsgModule:get_type()}},
                          []).
destroy(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:stop(Pid).

get_all_dds_entities(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_dds_entities).

publish(Name, Msg) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {publish, Msg}).

get_subscription_count(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_subscription_count).

%callbacks
%
init(#state{ node = Node, 
            topic = #dds_user_topic{name= TopicName}=Topic} = S) ->
    pg:join({?MODULE, Node, TopicName}, self()),
    Pub = dds_domain_participant:get_default_publisher(dds),
    DW = dds_publisher:create_datawriter(Pub, Topic),
    {ok, S#state{dds_data_writer = DW}}.

terminate(_, #state{dds_data_writer = DW} = S) ->
    Pub = dds_domain_participant:get_default_publisher(dds),
    dds_publisher:delete_datawriter(Pub, DW),
    ok.

    
handle_call(get_subscription_count, _, #state{dds_data_writer= DW}=S) ->    
    {reply, length(dds_data_w:get_matched_subscriptions(DW)), S};
handle_call(get_all_dds_entities, _, #state{dds_data_writer= DW}=S) ->
    {reply, {[DW],[]}, S}.

handle_cast({publish, Msg}, S) ->
    h_publish(Msg, S),
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

% HELPERS
%
h_publish(BinaryMsg, #state{msg_module = raw, dds_data_writer = DW}) ->
    dds_data_w:write(DW, BinaryMsg);
h_publish(Msg, #state{msg_module = MsgModule, dds_data_writer = DW}) ->
    Serialized = MsgModule:serialize(Msg),%serialize_ros_msg(Msg,T) ,
    dds_data_w:write(DW, Serialized).
