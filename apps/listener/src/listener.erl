-module(listener).

-behaviour(gen_server).


-export([start_link/0,receive_chat/1]).
-export([init/1, handle_call/3, handle_cast/2]).

% -include("../../ros/src/protocol/rtps_constants.hrl").
% -include("../../ros/src/protocol/rtps_structure.hrl").
-include("../../ros/src/dds/dds_types.hrl").
-include("../../ros/src/rcl/rmw_dds_msg.hrl").


start_link() -> gen_server:start_link(?MODULE, [], []).
receive_chat(Msg) -> io:format("~s\n",[Msg]).

init(S) -> 
        rcl:start_link(),

        {ok, Node} = ros_node:create("/listener"),
        
        ChatterTopic = #user_topic{type_name=?msg_string_topic_type , name="chatter"},
        ros_node:create_subscription(Node, ChatterTopic, fun receive_chat/1),

        rcl:spin(Node),
        {ok,S}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast(_,S) -> {noreply,S}.


