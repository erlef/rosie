-module(ros_client).
-export([start_link/3,wait_for_service/2,service_is_ready/1,call/2,cast/2,on_data_available/2]).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2]).

-behaviour(gen_server).

-behaviour(gen_data_reader_listener).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,{node, 
        service_handle, 
        name_prefix = "",
        user_process, 
        client_id,
        dds_data_writer, 
        dds_data_reader,
        waiting_caller = none }).

start_link(Node, {Service, NamePrefix}, CallbackHandler) -> 
        gen_server:start_link(?MODULE, #state{node=Node,service_handle=Service, name_prefix = NamePrefix, user_process = CallbackHandler}, []);
start_link(Node, Service, CallbackHandler) -> 
        gen_server:start_link(?MODULE, #state{node=Node,service_handle=Service, user_process = CallbackHandler}, []).

wait_for_service(Name,Timeout) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{wait_for_service,Timeout}).
service_is_ready(Name) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,service_is_ready).
call(Name, Request) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{send_request_and_wait, Request}).
cast(Name, Request) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{send_request_async, Request}).
on_data_available(Name, {Reader, ChangeKey}) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_data_available, {Reader, ChangeKey}}).


%callbacks
% 
init(#state{service_handle = Service, name_prefix = NP}=S) ->
        pg:join({?MODULE,Service}, self()),
        % A client publishes to the request topic
        SpawnRequest_name = "rq/" ++ NP ++ Service:get_name() ++ "Request",
        SpawnRequest_type = Service:get_type() ++ "Request_",
        SpawnRequest = #user_topic{name = SpawnRequest_name,type_name = SpawnRequest_type},

        Pub = dds_domain_participant:get_default_publisher(dds), 
        DW = dds_publisher:create_datawriter(Pub, SpawnRequest),

        % Then it also listens to the reply topic
        SpawnReply_name = "rr/" ++ NP ++ Service:get_name() ++ "Reply",
        SpawnReply_type = Service:get_type() ++ "Response_",
        SpawnReply = #user_topic{name = SpawnReply_name,type_name = SpawnReply_type},

        SUB = dds_domain_participant:get_default_subscriber(dds),
        DR = dds_subscriber:create_datareader(SUB, SpawnReply),
        dds_data_r:set_listener(DR, {{?MODULE,Service}, ?MODULE}),
        {ok,S#state{dds_data_writer=DW, dds_data_reader = DR , client_id = <<(crypto:strong_rand_bytes(8))/binary>>}}.


        
handle_call({wait_for_service,Timeout}, {Caller,_}, S) -> 
        self() ! {wait_for_service_loop, Caller, Timeout, now()},
        {reply,ok,S};
handle_call(service_is_ready, _, #state{dds_data_writer=DW, dds_data_reader=DR} = S) ->
        {reply, h_service_is_ready(S), S};
handle_call({send_request_and_wait, Request}, From, #state{dds_data_writer = DW,service_handle = Service, client_id=ID} = S) -> 
        Serialized = Service:serialize_request(ID,Request),
        dds_data_w:write(DW, Serialized),
        {noreply,S#state{waiting_caller = From}};
handle_call(_,_,S) -> {reply,ok,S}.

handle_cast({send_request_async, Request}, #state{dds_data_writer = DW,service_handle = Service, client_id=ID} = S) -> 
        Serialized = Service:serialize_request(ID,Request),
        dds_data_w:write(DW, Serialized),
        {noreply,S};
handle_cast({on_data_available, { Reader, ChangeKey}},
                #state{client_id = Client_ID, waiting_caller = Caller, service_handle = Service} = S) when Caller /= none -> 
        Change = dds_data_r:read(Reader, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        case Service:parse_reply(SerializedPayload) of 
                {Client_ID, Reply} -> gen_server:reply(Caller, Reply), {noreply,S#state{waiting_caller = none}};
                _ -> {noreply,S}
        end;
handle_cast({on_data_available, { Reader, ChangeKey}},
                #state{client_id = Client_ID, user_process = {M,Pid}, service_handle = Service} = S) -> 
        Change = dds_data_r:read(Reader, ChangeKey),

        SerializedPayload = Change#cacheChange.data,
        case Service:parse_reply(SerializedPayload) of 
                {Client_ID, Reply} -> M:on_service_reply(Pid,Reply), {noreply,S};
                _ -> {noreply,S}
        end;
handle_cast(_,S) -> {noreply,S}.

handle_info({wait_for_service_loop,Caller,Timeout,Start},S) ->
        case (timer:now_diff(now(), Start) div 1000) < Timeout of
                true -> case h_service_is_ready(S) of
                                true ->  erlang:send_after(300, Caller,ros_service_ready);
                                false -> erlang:send_after(10, self(), {wait_for_service_loop,Caller,Timeout,Start})
                        end;
                false ->Caller ! ros_timeout
        end,
        {noreply,S};
handle_info(_,S) ->
        {noreply,S}.

h_service_is_ready(#state{dds_data_writer=DW, dds_data_reader=DR} = S) ->
        Pubs = dds_data_r:get_matched_publications(DR), %io:format("~p\n",[Pubs]),
        Subs = dds_data_w:get_matched_subscriptions(DW), %io:format("~p\n",[Subs]),
        (length(Pubs) > 0) and (length(Subs) > 0).