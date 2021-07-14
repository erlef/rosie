-module(ros_msg_listener).

-behaviour(gen_server).
-behaviour(gen_data_reader_listener).


-export([start_link/1,on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/rtps_structure.hrl").


start_link(Callback) -> gen_server:start_link(?MODULE, Callback, []).
on_data_available(Name, {Reader, ChangeKey}) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_data_available, {Reader, ChangeKey}}).


init(Callback) -> 
        pg:join({?MODULE,Callback}, self()), 
        {ok,Callback}.
handle_call(_,_,Callback) -> {reply,ok,Callback}.
handle_cast({on_data_available, { Reader, ChangeKey}},Callback) -> 
        Change = dds_data_r:read(Reader, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        Callback(parse_string(SerializedPayload)),
        {noreply,Callback};
handle_cast(_,S) -> {noreply,S}.



% helpers
% 
parse_string(<<L:32/little,String:(L-1)/binary,_/binary>>) -> String.
