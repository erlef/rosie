-module(ros_subscription).

-export([start_link/4, start_link/5, destroy/1]).

-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3, handle_cast/2]).

-behaviour(gen_dds_entity_owner).
-export([get_all_dds_entities/1]).

-behaviour(gen_data_reader_listener).
-export([on_data_available/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").

-record(state,
        {msg_module,
         node,
         topic,
         dds_data_reader,
         user_process}).

start_link(MsgModule, Node, TopicName, QoSProfile, CallbackHandler) ->
    gen_server:start_link(?MODULE,
                          #state{msg_module = MsgModule,
                                 node = Node,
                                 topic = #dds_user_topic{name = TopicName,
                                                        type_name = MsgModule:get_type(),
                                                        qos_profile=QoSProfile},
                                 user_process = CallbackHandler},
                          []).
start_link(raw, Node, Topic, CallbackHandler) ->
    gen_server:start_link(?MODULE,
                          #state{msg_module = raw,
                                node = Node,
                                 topic = Topic,
                                 user_process = CallbackHandler},
                          []);
start_link(MsgModule, Node, TopicName, CallbackHandler) ->
    gen_server:start_link(?MODULE,
                          #state{msg_module = MsgModule,
                                node = Node,
                                 topic = #dds_user_topic{name=TopicName,
                                                            type_name = MsgModule:get_type()},
                                 user_process = CallbackHandler},
                          []).
destroy(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:stop(Pid).

get_all_dds_entities(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_dds_entities).

on_data_available(Name, {Reader, ChangeKey}) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_data_available, {Reader, ChangeKey}}).

%callbacks

init(#state{node = Node,
            topic= #dds_user_topic{name=TopicName} = Topic} =
         S) ->
    Subscription = {?MODULE, Node, TopicName},
    pg:join(Subscription, self()),
    SUB = dds_domain_participant:get_default_subscriber(dds),
    DR = dds_subscriber:create_datareader(SUB, Topic),
    dds_data_r:set_listener(DR, {?MODULE, Subscription}),
    {ok, S#state{dds_data_reader = DR}}.

terminate(_, #state{dds_data_reader = DR} = S) ->
    Sub = dds_domain_participant:get_default_subscriber(dds),
    dds_subscriber:delete_datareader(Sub, DR),
    ok.

handle_call(get_all_dds_entities, _, #state{dds_data_reader= DR}=S) ->
    {reply, {[],[DR]}, S}.

handle_cast({on_data_available, {Reader, ChangeKey}}, S) ->
    h_handle_data(Reader, ChangeKey, S),
    {noreply, S}.

% HELPERS

h_handle_data(Reader, ChangeKey, #state{msg_module = MsgModule, user_process = {M, Pid}}) ->
    case {dds_data_r:read(Reader, ChangeKey), MsgModule} of
        {not_found, _} -> 
            io:format("[ROS_SUBSCRIPTION]: could not find change in cache!\n");
        {Change, raw} ->
            SerializedPayload = Change#cacheChange.data,
            M:on_topic_msg(Pid, SerializedPayload);
        {Change, _} ->
            SerializedPayload = Change#cacheChange.data,
            {Parsed, _} = MsgModule:parse(SerializedPayload),
            M:on_topic_msg(Pid, Parsed)
    end.
