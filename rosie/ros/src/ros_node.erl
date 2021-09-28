-module(ros_node).

-export([start_link/1,get_name/1,create_subscription/4,create_publisher/3,create_client/3,create_service/3]).
-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2]).


-include_lib("rmw_dds_common/src/_rosie/participant_entities_info_msg.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,
        {name,
        incremental_id = 0 % used to compose process ids for the supervisor
        }).

start_link(Name) -> gen_server:start_link(?MODULE, Name, []).
get_name(Name) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,get_name).
create_subscription(Name,MsgModule,TopicName,Callback) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_subscription,MsgModule,TopicName,Callback}).
create_publisher(Name,MsgModule,TopicName) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_publisher,MsgModule,TopicName}).
create_client(Name, ServiceName, CallbackHandler) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_client, ServiceName, CallbackHandler}).
create_service(Name, ServiceName, Callback) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_service, ServiceName, Callback}).
%callbacks
% 
init(Name) ->
        %io:format("~p.erl STARTED!\n",[?MODULE]),
        pg:join({ros_node,Name}, self()),
        RosDiscoveryTopic = #user_topic{type_name=participant_entities_info_msg:get_type(), 
                                name="ros_discovery_info",
                                qos_profile = #qos_profile{
                                                durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
                                                history= {?KEEP_ALL_HISTORY_QOS,-1}
                                        }
                                },
        ProcSpecs = #{  id => ros_discovery_listener,
                        start => {ros_discovery_listener, start_link, []},
                        type => worker},
        % TODO make ros_node implement the listener behaviiour 
        %{ok, _} = supervisor:start_child(ros_node_workers_sup, ProcSpecs),
        %subscribe to discovery
        SUB = dds_domain_participant:get_default_subscriber(dds),
        DR = dds_subscriber:create_datareader(SUB, RosDiscoveryTopic),
        %dds_data_r:set_listener(DR, {ros_discovery_listener, ros_discovery_listener}),

        {ok,#state{name=Name}}.

handle_call({create_subscription, MsgModule, TopicName, CallbackHandler},_,S) -> 
        {reply, h_create_subscription(MsgModule, put_topic_prefix(TopicName), CallbackHandler),S};
handle_call({create_publisher, MsgModule, TopicName},_,S) -> 
        {reply,h_create_publisher(MsgModule, put_topic_prefix(TopicName), S),S};
handle_call({create_client, ServiceName, CallbackHandler},_,S) -> 
        {reply,h_create_client( ServiceName, CallbackHandler,S),S};
handle_call({create_service, ServiceName, CallbackHandler},_,S) -> 
        {reply,h_create_service( ServiceName, CallbackHandler,S),S};

handle_call(get_name,_,#state{name=N}=S) -> {reply,N,S};
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.


% HELPERS
% 
put_topic_prefix(N) ->
        "rt/" ++ N.
% h_create_subscription(MsgModule,TopicName,{Name, Module}) ->
%         SUB = dds_domain_participant:get_default_subscriber(dds),
%         Topic = #user_topic{type_name= MsgModule:get_type() , name=TopicName},
%         DR = dds_subscriber:create_datareader(SUB, Topic),
%         dds_data_r:set_listener(DR, {Name, Module});
h_create_subscription(MsgModule,TopicName,CallbackHandler) ->
        {ok, _} = supervisor:start_child(ros_subscriptions_sup, [MsgModule,TopicName,CallbackHandler]),
        {ros_subscription,TopicName}.

h_create_publisher(MsgModule, TopicName, #state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_publishers_sup, [{ros_node,Name}, MsgModule, TopicName]),
        {ros_publisher,TopicName}.

h_create_client(Service, CallbackHandler,#state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_clients_sup, [{ros_node,Name}, Service, CallbackHandler]),
        {ros_client,Service}.

h_create_service(Service, CallbackHandler,#state{name=Name}) -> 
        {ok, _} = supervisor:start_child(ros_services_sup, [{ros_node,Name}, Service, CallbackHandler]),
        {ros_service,Service}.


% h_create_action_client( ActionName, GoalCallback, FeedbackCallback, ResultCallback,#state{name=Name}) -> 
%         ProcSpecs = #{  id => ros_action_client,
%                         start => {ros_action_client, start_link, [{ros_node,Name}, ActionName, GoalCallback, FeedbackCallback, ResultCallback]},
%                         type => worker},
%         {ok, _} = supervisor:start_child(ros_node_workers_sup, ProcSpecs),
%         {ros_action_client,ActionName}.