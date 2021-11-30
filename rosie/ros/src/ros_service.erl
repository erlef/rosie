-module(ros_service).
-export([start_link/4, start_link/3, send_response/2, destroy/1]).

-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3, handle_cast/2]).

-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_dds_entity_owner).
-export([get_all_dds_entities/1]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,
        {node,
         service_interface,
         name_prefx = "",
         user_process,
         qos_profile = #qos_profile{},
         request_subscription,
         responce_publication}).

start_link(Node, {Service, NamePrefix}, CustomQoSProfile, {Module, Pid}) ->
    gen_server:start_link(?MODULE,
                          #state{node = Node,
                                 service_interface = Service,
                                 name_prefx = NamePrefix,
                                 qos_profile = CustomQoSProfile,
                                 user_process = {Module, Pid}},
                          []);
start_link(Node, Service, CustomQoSProfile, {Module, Pid}) ->
    gen_server:start_link(?MODULE,
                          #state{node = Node,
                                 service_interface = Service,
                                 qos_profile = CustomQoSProfile,
                                 user_process = {Module, Pid}},
                          []).

start_link(Node, {Service, NamePrefix}, {Module, Pid}) ->
    gen_server:start_link(?MODULE,
                          #state{node = Node,
                                 service_interface = Service,
                                 name_prefx = NamePrefix,
                                 user_process = {Module, Pid}},
                          []);
start_link(Node, Service, {Module, Pid}) ->
    gen_server:start_link(?MODULE,
                          #state{node = Node,
                                 service_interface = Service,
                                 user_process = {Module, Pid}},
                          []).
destroy(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:stop(Pid).

%This second start-link is for internal use by the action modules
send_response(Name, Response) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {send_response, Response}).

get_all_dds_entities(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_dds_entities).

on_topic_msg(Name, BinaryMsg) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_topic_msg, BinaryMsg}).

%callbacks
%
init(#state{node = Node,
            service_interface = Service,
            qos_profile = QoSProfile,
            name_prefx = NP} =
         S) ->
    ServiceName = {?MODULE, Node, Service},
    pg:join(ServiceName, self()),

    % A Service listens to the request topic
    Request_name = "rq/" ++ NP ++ Service:get_name() ++ "Request",
    Request_type = Service:get_type() ++ "Request_",
    Request = #dds_user_topic{name = Request_name,
                    type_name = Request_type,
                    qos_profile = QoSProfile},

    {ok, _} = supervisor:start_child(ros_subscriptions_sup, [raw, Node, Request, {?MODULE, ServiceName}]),
    RS_id = {ros_subscription, Node, Request_name},

    % And publishes to the reply topic
    Reply_name = "rr/" ++ NP ++ Service:get_name() ++ "Reply",
    Reply_type = Service:get_type() ++ "Response_",
    Reply = #dds_user_topic{name = Reply_name,
                    type_name = Reply_type,
                    qos_profile = QoSProfile},

    {ok, _} = supervisor:start_child(ros_publishers_sup, [raw, Node, Reply]),
    RP_id = {ros_publisher, Node, Reply_name},
    {ok, S#state{
        request_subscription = RS_id,
        responce_publication = RP_id}}.

terminate( _, #state{ request_subscription = SUB,
                                responce_publication = PUB} = S) ->
    ros_subscription:destroy(SUB),
    ros_publisher:destroy(PUB),
    ok.

handle_call(get_all_dds_entities, _, #state{request_subscription = RS, responce_publication = RP}=S) ->
    {[DW],_} = ros_publisher:get_all_dds_entities(RP),
    {_,[DR]} = ros_subscription:get_all_dds_entities(RS),
    {reply, {[DW],[DR]}, S}.

handle_cast({send_response, {Client_ID, RequestNumber, Response}},
            #state{responce_publication = RP, service_interface = Service} = S) ->
    Serialized = Service:serialize_reply(Client_ID, RequestNumber, Response),
    ros_publisher:publish(RP, Serialized),
    {noreply, S};
handle_cast({on_topic_msg, Binary},
            #state{node = Node, user_process = {M, Pid}, service_interface = Service} = S) ->
    {Client_ID, RequestNumber, Request} = Service:parse_request(Binary),
    Response = M:on_client_request(Pid, {{Client_ID, RequestNumber}, Request}),
    case Response of
        ros_service_noreply ->
            ok;
        _ ->
            ros_service:send_response({?MODULE, Node, Service}, {Client_ID, RequestNumber, Response})
    end,
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.
