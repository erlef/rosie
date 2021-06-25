-module(ros_msg_listener).

-behaviour(gen_server).
-behaviour(gen_data_reader_listener).


-export([start_link/1,on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-include("../../ros/src/protocol/rtps_constants.hrl").
-include("../../ros/src/protocol/rtps_structure.hrl").
-include("../../ros/src/dds/dds_types.hrl").
-include("../../ros/src/rcl/rmw_dds_msg.hrl").


start_link(Callback) -> gen_server:start_link(?MODULE, Callback, []).
on_data_available(Pid, {ReaderPid, ChangeKey}) -> gen_server:cast(Pid,{on_data_available, {ReaderPid, ChangeKey}}).


init(Callback) -> {ok,Callback}.
handle_call(_,_,Callback) -> {reply,ok,Callback}.
handle_cast({on_data_available, { ReaderPid, ChangeKey}},Callback) -> 
        Change = dds_data_r:read(ReaderPid, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        Callback(parse_string(SerializedPayload)),
        {noreply,Callback};
handle_cast(_,S) -> {noreply,S}.



% helpers
% 
parse_string(<<L:32/little,String:(L-1)/binary,_/binary>>) -> String.
