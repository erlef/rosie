-module(ros_service).

-export([start_link/4, start_link/3, send_response/2, on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-behaviour(gen_server).
-behaviour(gen_data_reader_listener).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,
        {node,
         service_interface,
         name_prefx = "",
         user_process,
         qos_profile = #qos_profile{},
         dds_data_writer,
         dds_data_reader}).

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

%This second start-link is for internal use by the action modules
send_response(Name, Response) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {send_response, Response}).

on_data_available(Name, {Reader, ChangeKey}) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_data_available, {Reader, ChangeKey}}).

%callbacks
%
init(#state{service_interface = Service,
            qos_profile = QoSProfile,
            name_prefx = NP} =
         S) ->
    pg:join({?MODULE, Service}, self()),

    % A Service listens to the request topic
    SpawnRequest_name = "rq/" ++ NP ++ Service:get_name() ++ "Request",
    SpawnRequest_type = Service:get_type() ++ "Request_",
    SpawnRequest =
        #user_topic{name = SpawnRequest_name,
                    type_name = SpawnRequest_type,
                    qos_profile = QoSProfile},

    SUB = dds_domain_participant:get_default_subscriber(dds),
    DR = dds_subscriber:create_datareader(SUB, SpawnRequest),
    dds_data_r:set_listener(DR, {{?MODULE, Service}, ?MODULE}),

    % And publishes to the reply topic
    SpawnReply_name = "rr/" ++ NP ++ Service:get_name() ++ "Reply",
    SpawnReply_type = Service:get_type() ++ "Response_",
    SpawnReply =
        #user_topic{name = SpawnReply_name,
                    type_name = SpawnReply_type,
                    qos_profile = QoSProfile},

    Pub = dds_domain_participant:get_default_publisher(dds),
    DW = dds_publisher:create_datawriter(Pub, SpawnReply),

    {ok, S#state{dds_data_writer = DW, dds_data_reader = DR}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({send_response, {Client_ID, RequestNumber, Response}},
            #state{dds_data_writer = DW, service_interface = Service} = S) ->
    Serialized = Service:serialize_reply(Client_ID, RequestNumber, Response),
    dds_data_w:write(DW, Serialized),
    {noreply, S};
handle_cast({on_data_available, {Reader, ChangeKey}},
            #state{user_process = {M, Pid}, service_interface = Service} = S) ->
    Change = dds_data_r:read(Reader, ChangeKey),
    SerializedPayload = Change#cacheChange.data,
    {Client_ID, RequestNumber, Request} = Service:parse_request(SerializedPayload),
    Response = M:on_client_request(Pid, {{Client_ID, RequestNumber}, Request}),
    case Response of
        ros_service_noreply ->
            ok;
        _ ->
            ros_service:send_response({?MODULE, Service}, {Client_ID, RequestNumber, Response})
    end,
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.
