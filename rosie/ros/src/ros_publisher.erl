-module(ros_publisher).
-export([start_link/2,publish/2]).
-export([init/1,handle_call/3,handle_cast/2]).

-behaviour(gen_server).

-include_lib("dds/include/dds_types.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").

-record(state,{node, topic, dds_data_writer}).

start_link(Node,Topic) -> 
        gen_server:start_link(?MODULE, #state{node=Node,topic=Topic}, []).
publish(Name,Msg) ->
        [Pid| _ ] = pg:get_members(Name),
        gen_server:cast(Pid,{publish,Msg}).
%callbacks
% 
init(#state{topic=Topic}=S) ->
        pg:join({?MODULE,Topic}, self()),
        Pub = dds_domain_participant:get_default_publisher(dds), 
        DW = dds_publisher:create_datawriter(Pub, Topic),
        {ok,S#state{dds_data_writer= DW}}.

handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({publish,Msg},S) -> h_publish(Msg,S), {noreply,S};
handle_cast(_,S) -> {noreply,S}.


% HELPERS
% 
h_publish(Msg,#state{dds_data_writer=DW,topic=T}) ->
        Serialized = serialize_ros_msg(Msg,T) ,
        dds_data_w:write(DW, Serialized).

serialize_ros_msg(Msg,#user_topic{type_name = ?msg_string_topic_type}) -> serialize_string(Msg);
serialize_ros_msg(Msg,#user_topic{type_name = ?msg_twist_topic_type}) -> serialize_twist(Msg).


serialize_twist(#twist{linear=#vector3{x=LX,y=LY,z=LZ},
                        angular=#vector3{x=AX,y=AY,z=AZ}}) -> 
        <<LX/float-little,LY/float-little,LZ/float-little,
                AX/float-little,AY/float-little,AZ/float-little>>.
serialize_string(S) -> 
        L = length(S),
        <<(L+1):32/little,(list_to_binary(S))/binary,0>>.