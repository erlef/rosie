-module(ros_client).
-export([start_link/3, wait_for_service/2, service_is_ready/1, call/2, cast/2, destroy/1]).

-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2]).

-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_dds_entity_owner).
-export([get_all_dds_entities/1]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,
        {node,
         service_handle,
         name_prefix = "",
         user_process,
         client_id,
         request_publisher,
         responce_subscription,
         waiting_caller = none}).

start_link(Node, {Service, NamePrefix}, CallbackHandler) ->
    gen_server:start_link(?MODULE,
                          #state{node = Node,
                                 service_handle = Service,
                                 name_prefix = NamePrefix,
                                 user_process = CallbackHandler},
                          []);
start_link(Node, Service, CallbackHandler) ->
    gen_server:start_link(?MODULE,
                          #state{node = Node,
                                 service_handle = Service,
                                 user_process = CallbackHandler},
                          []).
destroy(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:stop(Pid).

wait_for_service(Name, Timeout) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {wait_for_service, Timeout}).

service_is_ready(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, service_is_ready).

call(Name, Request) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {send_request_and_wait, Request}).

cast(Name, Request) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {send_request_async, Request}).

get_all_dds_entities(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_all_dds_entities).

on_topic_msg(Name, BinaryMsg) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_topic_msg, BinaryMsg}).

%callbacks
%
init(#state{node = Node, service_handle = Service, name_prefix = NP} = S) ->
    ClientName = {?MODULE, Node, Service},
    pg:join(ClientName, self()),
    % A client publishes to the request topic
    Request_name = "rq/" ++ NP ++ Service:get_name() ++ "Request",
    Request_type = Service:get_type() ++ "Request_",
    Request = #dds_user_topic{name = Request_name, type_name = Request_type},

    {ok, _} = supervisor:start_child(ros_publishers_sup, [raw, Node, Request]),
    RP_id = {ros_publisher, Node, Request_name},

    % Then it also listens to the reply topic
    Reply_name = "rr/" ++ NP ++ Service:get_name() ++ "Reply",
    Reply_type = Service:get_type() ++ "Response_",
    Reply = #dds_user_topic{name = Reply_name, type_name = Reply_type},

    {ok, _} = supervisor:start_child(ros_subscriptions_sup, [raw, Node, Reply, {?MODULE, ClientName}]),
    RS_id = {ros_subscription, Node, Reply_name},

    {ok,
     S#state{
            request_publisher = RP_id,
            responce_subscription = RS_id,
            client_id = <<(crypto:strong_rand_bytes(8))/binary>>}}.

terminate( _, #state{request_publisher=PUB,
                                responce_subscription= SUB} = S) ->
    ros_publisher:destroy(PUB),
    ros_subscription:destroy(SUB),
    ok.

handle_call({wait_for_service, Timeout}, {Caller, _}, S) ->
    self() ! {wait_for_service_loop, Caller, Timeout, erlang:monotonic_time(millisecond)},
    {reply, ok, S};
handle_call(service_is_ready, _, S) ->
    {reply, h_service_is_ready(S), S};
handle_call({send_request_and_wait, Request},
            From,
            #state{request_publisher = RP,
                   service_handle = Service,
                   client_id = ID} =
                S) ->
    Serialized = Service:serialize_request(ID, 1, Request),
    ros_publisher:publish(RP, Serialized),
    {noreply, S#state{waiting_caller = From}};
handle_call(get_all_dds_entities, _, #state{request_publisher = RP, responce_subscription= RS}=S) ->
    {[DW],_} = ros_publisher:get_all_dds_entities(RP),
    {_,[DR]} = ros_subscription:get_all_dds_entities(RS),
    {reply, {[DW],[DR]}, S}.

handle_cast({send_request_async, Request},
            #state{request_publisher = RP,
                   service_handle = Service,
                   client_id = ID} =
                S) ->
    Serialized = Service:serialize_request(ID, 1, Request),
    ros_publisher:publish(RP, Serialized),
    {noreply, S};
handle_cast({on_topic_msg, Binary},
            #state{client_id = Client_ID,
                   waiting_caller = Caller,
                   service_handle = Service} =
                S)
    when Caller /= none ->
    case Service:parse_reply(Binary) of
        {Client_ID, RequestNumber, Reply} ->
            gen_server:reply(Caller, Reply),
            {noreply, S#state{waiting_caller = none}};
        _ ->
            {noreply, S}
    end;
handle_cast({on_topic_msg, Binary},
            #state{client_id = Client_ID,
                   user_process = {M, Pid},
                   service_handle = Service} =
                S) ->
    case Service:parse_reply(Binary) of
        {Client_ID, RequestNumber, Reply} ->
            M:on_service_reply(Pid, Reply),
            {noreply, S};
        _ ->
            {noreply, S}
    end.

handle_info({wait_for_service_loop, Caller, Timeout, Start}, S) ->
    case (erlang:monotonic_time(millisecond) - Start) < Timeout of
        true ->
            case h_service_is_ready(S) of
                true ->
                    Caller ! ros_service_ready;
                false ->
                    erlang:send_after(10, self(), {wait_for_service_loop, Caller, Timeout, Start})
            end;
        false ->
            Caller ! ros_timeout
    end,
    {noreply, S}.

h_service_is_ready(#state{request_publisher = RP, responce_subscription = RS} = S) ->
    {[DW],_} = ros_publisher:get_all_dds_entities(RP),
    {_,[DR]} = ros_subscription:get_all_dds_entities(RS),
    Pubs = dds_data_r:get_matched_publications(DR), %io:format("~p\n",[Pubs]),
    Subs = dds_data_w:get_matched_subscriptions(DW), %io:format("~p\n",[Subs]),
    DEF_PUB = dds_domain_participant:get_default_publisher(dds),
    (length(Pubs) > 0) and 
    (length(Subs) > 0) and 
    dds_publisher:endpoint_has_been_acknoledged(DEF_PUB, DR) and
    dds_publisher:endpoint_has_been_acknoledged(DEF_PUB, DW).
