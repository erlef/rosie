-module(ros_node).
-export([start_link/1,get_name/1,create_subscription/3,create_publisher/2,create_client/3]).
-export([init/1,handle_call/3,handle_cast/2]).

-behaviour(gen_server).

-include_lib("ros/include/rmw_dds_msg.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,{name}).

start_link(Name) -> gen_server:start_link(?MODULE, Name, []).
get_name(Name) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,get_name).
create_subscription(Name,Topic,Callback) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_subscription,Topic,Callback}).
create_publisher(Name,Topic) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_publisher,Topic}).
create_client(Name, ServiceName, Callback) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{create_client, ServiceName, Callback}).

%callbacks
% 
init(Name) ->
        %io:format("~p.erl STARTED!\n",[?MODULE]),
        pg:join({ros_node,Name}, self()),
        RosDiscoveryTopic = #user_topic{type_name=?ros_discovery_info_topic_type , 
                                name=?ros_discovery_info_topic_name,
                                qos_profile = #qos_profile{
                                                durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
                                                history= {?KEEP_ALL_HISTORY_QOS,-1}
                                        }
                                },
        ProcSpecs = #{  id => ros_discovery_listener,
                        start => {ros_discovery_listener, start_link, []},
                        type => worker},
        {ok, _} = supervisor:start_child(ros_node_workers_sup, ProcSpecs),
        h_create_subscription(RosDiscoveryTopic, {ros_discovery_listener, ros_discovery_listener}),
        {ok,#state{name=Name}}.

handle_call({create_subscription,Topic, Callback},_,S) -> 
        {reply,h_create_subscription(put_topic_prefix(Topic),Callback),S};
handle_call({create_publisher,Topic},_,S) -> 
        {reply,h_create_publisher(put_topic_prefix(Topic),S),S};
handle_call({create_client, ServiceName, Callback},_,S) -> 
        {reply,h_create_client( ServiceName, Callback,S),S};
handle_call(get_name,_,#state{name=N}=S) -> {reply,N,S};
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.


% HELPERS
% 
put_topic_prefix(#user_topic{name=N}=Topic) ->
        Topic#user_topic{name= "rt/" ++ N}.
h_create_subscription(Topic,{Name, Module}) ->
        SUB = dds_domain_participant:get_default_subscriber(dds),
        DR = dds_subscriber:create_datareader(SUB, Topic),
        dds_data_r:set_listener(DR, {Name, Module});
h_create_subscription(Topic,Callback) ->
        SUB = dds_domain_participant:get_default_subscriber(dds),
        DR = dds_subscriber:create_datareader(SUB, Topic),
        ProcSpecs = #{  id => ros_msg_listener,
                        start => {ros_msg_listener, start_link, [Callback]},
                        type => worker},
        {ok, _} = supervisor:start_child(ros_node_workers_sup, ProcSpecs),
        dds_data_r:set_listener(DR, {{ros_msg_listener,Callback}, ros_msg_listener}).

h_create_publisher(Topic,#state{name=Name}) ->
        ProcSpecs = #{  id => ros_publisher,
                        start => {ros_publisher, start_link, [{ros_node,Name}, Topic]},
                        type => worker},
        {ok, _} = supervisor:start_child(ros_node_workers_sup, ProcSpecs),
        {ros_publisher,Topic}.

h_create_client(Service, Callback,#state{name=Name}) -> 
        ProcSpecs = #{  id => ros_client,
        start => {ros_client, start_link, [{ros_node,Name}, Service, Callback]},
        type => worker},
        {ok, _} = supervisor:start_child(ros_node_workers_sup, ProcSpecs),
        {ros_client,Service}.

% sub_to_discovery(#state{name=Name, dds_domain_participant=DP}=S) -> 
%         % Subscribe to the ros discovery topic
%         RosDiscoveryTopic = #user_topic{type_name=?ros_discovery_info_topic_type , 
%                                 name=?ros_discovery_info_topic_name,
%                                 qos_profile = #qos_profile{
%                                                 durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
%                                                 history= {?KEEP_ALL_HISTORY_QOS,-1}
%                                         }
%                                 },
%         {ok,Listener} = ros_discovery_listener:start_link(),
%         h_create_subscription(RosDiscoveryTopic,{Listener, ros_discovery_listener},S).


% h_execute_all_jobs(#state{job_list=[]}=S) ->
%         S#state{job_list=[]};
% h_execute_all_jobs(#state{job_list=[{sub,Topic,Handler}|TL]}=S) ->
%         h_create_subscription(Topic, Handler,S),
%         S#state{job_list=TL}.