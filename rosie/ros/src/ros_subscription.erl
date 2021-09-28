-module(ros_subscription).
-export([start_link/3]).

-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2]).
-behaviour(gen_data_reader_listener).
-export([on_data_available/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").

-record(state,{msg_module, topic_name, dds_topic, dds_data_reader, user_process}).

start_link(MsgModule,TopicName,CallbackHandler) -> 
        gen_server:start_link(?MODULE, 
            #state{ msg_module=MsgModule,
                    topic_name=TopicName,
                    user_process = CallbackHandler}, []).

on_data_available(Name, {Reader, ChangeKey}) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_data_available, {Reader, ChangeKey}}).

%callbacks

init(#state{msg_module=MsgModule,topic_name=TopicName}=S) ->
        Subscription = {?MODULE,TopicName},
        pg:join(Subscription, self()),        
        SUB = dds_domain_participant:get_default_subscriber(dds),
        DDS_Topic = #user_topic{type_name = MsgModule:get_type() , name = TopicName},
        DR = dds_subscriber:create_datareader(SUB, DDS_Topic),
        dds_data_r:set_listener(DR, {Subscription, ?MODULE}),
        {ok,S#state{dds_topic= DDS_Topic, dds_data_reader= DR}}.

handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({on_data_available,{Reader, ChangeKey}},S) -> h_handle_data(Reader, ChangeKey,S), {noreply,S};
handle_cast(_,S) -> {noreply,S}.


% HELPERS
h_handle_data(Reader, ChangeKey, #state{msg_module=MsgModule, user_process= {M, Pid}}) ->
        Change = dds_data_r:read(Reader, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        {Parsed,_} = MsgModule:parse(SerializedPayload),
        M:on_topic_msg(Pid, Parsed).
