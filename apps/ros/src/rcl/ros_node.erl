-module(ros_node).
-export([create/1,get_name/1,create_subscription/3,create_publisher/2,execute_all_jobs/1]).
-export([init/1,handle_call/3,handle_cast/2]).

-behaviour(gen_server).

-include("ros_commons.hrl").
-include("rmw_dds_msg.hrl").
-include("../dds/dds_types.hrl").
-include("../protocol/rtps_constants.hrl").

-record(state,{name,
                dds_domain_participant,
                job_list = []}).

create(Name) -> gen_server:start_link(?MODULE, Name, []).
get_name(Pid) -> gen_server:call(Pid,get_name).
create_subscription(Pid,Topic,Callback) -> gen_server:call(Pid,{create_subscription,Topic,Callback}).
create_publisher(Pid,Topic) -> gen_server:call(Pid,{create_publisher,Topic}).
execute_all_jobs(Pid) -> gen_server:call(Pid, execute_all_jobs).

%callbacks
% 
init(Name) ->
        DP = rcl:get_dds_domain_participant(?ROS_CONTEXT),

        RosDiscoveryTopic = #user_topic{type_name=?ros_discovery_info_topic_type , 
                                name=?ros_discovery_info_topic_name,
                                qos_profile = #qos_profile{
                                                durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
                                                history= {?KEEP_ALL_HISTORY_QOS,-1}
                                        }
                                },
        {ok,Listener} = ros_discovery_listener:start_link(),
        J = [{sub,RosDiscoveryTopic,{Listener,ros_discovery_listener}}],
        {ok,#state{name=Name, dds_domain_participant=DP, job_list = J}}.

handle_call({create_subscription,Topic, Callback},_,S) -> 
        {reply,h_create_subscription(put_topic_prefix(Topic),Callback,S),S};
handle_call({create_publisher,Topic},_,S) -> 
        {reply,h_create_publisher(put_topic_prefix(Topic),S),S};
handle_call(execute_all_jobs,_,S) -> {reply,ok,h_execute_all_jobs(S)};
handle_call(get_name,_,#state{name=N}=S) -> {reply,N,S};
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.


% HELPERS
% 
put_topic_prefix(#user_topic{name=N}=Topic) ->
        Topic#user_topic{name= "rt/" ++ N}.
h_create_subscription(Topic,{Pid, Module},#state{dds_domain_participant=DP}) ->
        SUB = dds_domain_participant:get_default_subscriber(DP),
        DR = dds_subscriber:create_datareader(SUB, Topic),
        dds_data_r:set_listener(DR, {Pid, Module});
h_create_subscription(Topic,Callback,#state{dds_domain_participant=DP}) ->
        SUB = dds_domain_participant:get_default_subscriber(DP),
        DR = dds_subscriber:create_datareader(SUB, Topic),
        {ok,Listener} = ros_msg_listener:start_link(Callback),
        dds_data_r:set_listener(DR, {Listener, ros_msg_listener}).

h_create_publisher(Topic,#state{dds_domain_participant=DP}) ->
        {ok,Pub} = ros_publisher:create(self(),DP,Topic),
        Pub.

sub_to_discovery(#state{name=Name, dds_domain_participant=DP}=S) -> 
        % Subscribe to the ros discovery topic
        RosDiscoveryTopic = #user_topic{type_name=?ros_discovery_info_topic_type , 
                                name=?ros_discovery_info_topic_name,
                                qos_profile = #qos_profile{
                                                durability = ?TRANSIENT_LOCAL_DURABILITY_QOS,
                                                history= {?KEEP_ALL_HISTORY_QOS,-1}
                                        }
                                },
        {ok,Listener} = ros_discovery_listener:start_link(),
        h_create_subscription(RosDiscoveryTopic,{Listener, ros_discovery_listener},S).


h_execute_all_jobs(#state{job_list=[]}=S) ->
        S#state{job_list=[]};
h_execute_all_jobs(#state{job_list=[{sub,Topic,Handler}|TL]}=S) ->
        h_create_subscription(Topic, Handler,S),
        S#state{job_list=TL}.