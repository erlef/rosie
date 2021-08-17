-module(ros_publisher).
-export([start_link/3,publish/2]).
-export([init/1,handle_call/3,handle_cast/2]).

-behaviour(gen_server).

-include_lib("dds/include/dds_types.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").

-record(state,{node, msg_module, topic_name, dds_topic, dds_data_writer}).

start_link(Node,MsgModule,TopicName) -> 
        gen_server:start_link(?MODULE, #state{node=Node,msg_module=MsgModule,topic_name=TopicName}, []).
publish(Name,Msg) ->
        [Pid| _ ] = pg:get_members(Name),
        gen_server:cast(Pid,{publish,Msg}).
%callbacks
% 
init(#state{msg_module=MsgModule,topic_name=TopicName}=S) ->
        pg:join({?MODULE,TopicName}, self()),        
        Pub = dds_domain_participant:get_default_publisher(dds), 
        DDS_Topic = #user_topic{type_name= MsgModule:get_type() , name=TopicName},
        DW = dds_publisher:create_datawriter(Pub, DDS_Topic),
        {ok,S#state{dds_topic= DDS_Topic,dds_data_writer= DW}}.

handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({publish,Msg},S) -> h_publish(Msg,S), {noreply,S};
handle_cast(_,S) -> {noreply,S}.


% HELPERS
% 
h_publish(Msg,#state{msg_module=MsgModule, dds_data_writer=DW}) ->
        Serialized = MsgModule:serialize(Msg),%serialize_ros_msg(Msg,T) ,
        dds_data_w:write(DW, Serialized).

% serialize_ros_msg(Msg,#user_topic{type_name = ?msg_string_topic_type}) -> serialize_string(Msg);
% serialize_ros_msg(Msg,#user_topic{type_name = ?msg_twist_topic_type}) -> serialize_twist(Msg).


% serialize_twist(#twist{linear=#vector3{x=LX,y=LY,z=LZ},
%                         angular=#vector3{x=AX,y=AY,z=AZ}}) -> 
%         <<LX/float-little,LY/float-little,LZ/float-little,
%                 AX/float-little,AY/float-little,AZ/float-little>>.
% serialize_string(S) -> 
%         L = length(S),
%         <<(L+1):32/little,(list_to_binary(S))/binary,0>>.