-module(ros_client).
-export([start_link/3,send_request/2,on_data_available/2]).
-export([init/1,handle_call/3,handle_cast/2]).

-behaviour(gen_server).

-behaviour(gen_data_reader_listener).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,{node, 
        service_handle, user_callback, 
        dds_data_writer, 
        dds_data_reader}).

start_link(Node, Service, Callback) -> 
        gen_server:start_link(?MODULE, #state{node=Node,service_handle=Service,user_callback = Callback}, []).
send_request(Name, Request) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{send_request, Request}).
on_data_available(Name, {Reader, ChangeKey}) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_data_available, {Reader, ChangeKey}}).


%callbacks
% 
init(#state{service_handle = Service}=S) ->
        pg:join({?MODULE,Service}, self()),
        % A client publishes to the request topic
        SpawnRequest_name = "rq/" ++ Service:get_name() ++ "Request",
        SpawnRequest_type = Service:get_type() ++ "Request_",
        SpawnRequest = #user_topic{name = SpawnRequest_name,type_name = SpawnRequest_type},

        Pub = dds_domain_participant:get_default_publisher(dds), 
        DW = dds_publisher:create_datawriter(Pub, SpawnRequest),

        % Then it also listens to the reply topic
        SpawnReply_name = "rr/" ++ Service:get_name() ++ "Reply",
        SpawnReply_type = Service:get_type() ++ "Response_",
        SpawnReply = #user_topic{name = SpawnReply_name,type_name = SpawnReply_type},

        SUB = dds_domain_participant:get_default_subscriber(dds),
        DR = dds_subscriber:create_datareader(SUB, SpawnReply),
        dds_data_r:set_listener(DR, {{?MODULE,Service}, ?MODULE}),
        {ok,S#state{dds_data_writer=DW, dds_data_reader = DR}}.

handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({send_request, Request}, #state{dds_data_writer = DW,service_handle = Service} = S) -> 
        Serialized = Service:serialize_request(Request),
        dds_data_w:write(DW, Serialized),
        {noreply,S};
handle_cast({on_data_available, { Reader, ChangeKey}},
                #state{user_callback = UserCall, service_handle = Service} = S) -> 
        Change = dds_data_r:read(Reader, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        UserCall(Service:parse_reply(SerializedPayload)),
        {noreply,S};
handle_cast(_,S) -> {noreply,S}.

