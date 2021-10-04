-module(ros_node).

-export([start_link/1,get_name/1,create_subscription/4,create_publisher/3,create_publisher/4,create_client/3,create_service/3,create_service/4]).

-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2]).


-include_lib("rmw_dds_common/src/_rosie/participant_entities_info_msg.hrl").
-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").
% -include_lib("dds/include/rtps_constants.hrl").

-record(state,
        {name,
        discovery_pub,
        discovery_sub
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
create_publisher(Name,MsgModule, TopicName, QoS) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_publisher,MsgModule, TopicName, QoS}).
create_client(Name, Service, CallbackHandler) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_client, Service, CallbackHandler}).
create_service(Name, Service, Callback) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_service, Service, Callback}).
create_service(Name, Service, QoSProfile, Callback) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_service, Service, QoSProfile, Callback}).

on_topic_msg(Name, Msg) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_topic_msg, Msg}).

%callbacks
% 
init(Name) ->
        %io:format("~p.erl STARTED!\n",[?MODULE]),
        pg:join({ros_node,Name}, self()),
        Qos_profile = #qos_profile{durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
                                   history= {?KEEP_ALL_HISTORY_QOS,-1}
                                },

        {ok, _} = supervisor:start_child(ros_subscriptions_sup, [participant_entities_info_msg,"ros_discovery_info",Qos_profile,{?MODULE, {ros_node,Name}}]),
        %{ok, _} = supervisor:start_child(ros_publishers_sup, [participant_entities_info_msg,Qos_profile,"ros_discovery_info"]),

        %update_ros_discovery(Name),

        {ok,#state{name=Name, discovery_pub={ros_publisher,"ros_discovery_info"}, discovery_sub={ros_subscription,"ros_discovery_info"}}}.

handle_call({create_subscription, MsgModule, TopicName, CallbackHandler},_,S) -> 
        {reply, h_create_subscription(MsgModule, put_topic_prefix(TopicName), CallbackHandler, S),S};
handle_call({create_publisher, MsgModule, TopicName},_,S) -> 
        {reply,h_create_publisher(MsgModule, put_topic_prefix(TopicName), S),S};
handle_call({create_publisher, MsgModule, TopicName, QoS},_,S) -> 
        {reply,h_create_publisher_qos(MsgModule, put_topic_prefix(TopicName), QoS, S),S};

handle_call({create_client, Service, CallbackHandler},_,S) -> 
        {reply,h_create_client( Service, CallbackHandler,S),S};
handle_call({create_service, Service, CallbackHandler},_,S) -> 
        {reply,h_create_service( Service, CallbackHandler,S),S};
handle_call({create_service, Service, QoSProfile, CallbackHandler},_,S) -> 
        {reply,h_create_service_qos( Service, QoSProfile, CallbackHandler, S),S};

handle_call(get_name,_,#state{name=N}=S) -> {reply,N,S};
handle_call(_,_,S) -> {reply,ok,S}.

handle_cast({on_topic_msg,Msg},S) -> 
        %io:format("ROS_DISCOVERY: ~p\n",[Msg]),                   
        {noreply,S};
handle_cast(_,S) -> {noreply,S}.


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

guid_to_gid(#guId{prefix=PREFIX,entityId=#entityId{key=KEY,kind=KIND}}) -> 
        #gid{data=binary_to_list(<<PREFIX/binary, KEY/binary, KIND, 0:64>>) }.

update_ros_discovery(NodeName) -> 

        PUB = dds_domain_participant:get_default_publisher(dds),
        SUB = dds_domain_participant:get_default_subscriber(dds),

        Wgids = [ guid_to_gid(GUID) || {_,_,{data_w_of, GUID}} <- dds_publisher:get_all_data_writers(PUB)],
        Rgids = [ guid_to_gid(GUID) || {_,_,{data_r_of, GUID}} <- dds_subscriber:get_all_data_readers(SUB)],
                
        #participant{guid=P_GUID} = rtps_participant:get_info(participant),
        P_GID = guid_to_gid(P_GUID),
        NodeEntity = #node_entities_info{
                node_namespace="/",
                node_name=NodeName,
                reader_gid_seq= Rgids,
                writer_gid_seq= Wgids},
        Msg = #participant_entities_info{
                gid=P_GID,
                node_entities_info_seq=[NodeEntity]},
        ros_publisher:publish({ros_publisher,"ros_discovery_info"}, Msg).

h_create_subscription(MsgModule,TopicName,CallbackHandler, #state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_subscriptions_sup, [MsgModule,TopicName,CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_subscription,TopicName}.

h_create_publisher(MsgModule, TopicName, #state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_publishers_sup, [MsgModule, TopicName]),
        %update_ros_discovery(Name),
        {ros_publisher,TopicName}.

h_create_publisher_qos(MsgModule, TopicName, QoS, #state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_publishers_sup, [MsgModule, QoS, TopicName]),
        %update_ros_discovery(Name),
        {ros_publisher,TopicName}.

h_create_client({Service,Prefix}, CallbackHandler,#state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_clients_sup, [{ros_node,Name}, {Service,Prefix}, CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_client,Service};
h_create_client(Service, CallbackHandler,#state{name=Name}) ->
        {ok, _} = supervisor:start_child(ros_clients_sup, [{ros_node,Name}, Service, CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_client,Service}.

h_create_service({Service,Prefix}, CallbackHandler,#state{name=Name}) -> 
        {ok, _} = supervisor:start_child(ros_services_sup, [{ros_node,Name}, {Service,Prefix}, CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_service,Service};
h_create_service(Service, CallbackHandler,#state{name=Name}) -> 
        {ok, _} = supervisor:start_child(ros_services_sup, [{ros_node,Name}, Service, CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_service,Service}.

h_create_service_qos({Service,Prefix},QoSProfile, CallbackHandler,#state{name=Name}) -> 
        {ok, _} = supervisor:start_child(ros_services_sup, [{ros_node,Name}, {Service,Prefix}, QoSProfile, CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_service,Service};
h_create_service_qos(Service, QoSProfile, CallbackHandler, #state{name=Name}) -> 
        {ok, _} = supervisor:start_child(ros_services_sup, [{ros_node,Name}, Service, QoSProfile, CallbackHandler]),
        %update_ros_discovery(Name),
        {ros_service,Service}.

