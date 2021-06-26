-module(ros_publisher).
-export([create/3,publish/2]).
-export([init/1,handle_call/3,handle_cast/2]).

-behaviour(gen_server).

-include("ros_commons.hrl").
-include("rmw_dds_msg.hrl").
-include("../dds/dds_types.hrl").
-include("../protocol/rtps_constants.hrl").

-record(state,{node,
                topic,
                dds_domain_participant,
                dds_publisher,
                dds_data_writer,
                job_list = []}).

create(Node,DP,Topic) -> gen_server:start_link(?MODULE, 
                        #state{node=Node,dds_domain_participant=DP,topic=Topic}, []).
publish(Pid,Msg) -> gen_server:cast(Pid,{publish,Msg}).
%callbacks
% 
init(#state{dds_domain_participant=DP,topic=Topic}=S) ->
        Pub = dds_domain_participant:get_default_publisher(DP), 
        DW = dds_publisher:create_datawriter(Pub, Topic),
        {ok,S#state{dds_publisher=Pub, dds_data_writer= DW}}.

handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({publish,Msg},S) -> h_publish(Msg,S), {noreply,S};
handle_cast(_,S) -> {noreply,S}.


% HELPERS
% 
h_publish(Msg,#state{dds_data_writer=DW}) ->
        Serialized = serialize_string(Msg) ,
        dds_data_w:write(DW, Serialized).

serialize_string(S) -> 
        L = length(S),
        <<(L+1):32/little,(list_to_binary(S))/binary,0>>.