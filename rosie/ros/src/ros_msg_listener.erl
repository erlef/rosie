-module(ros_msg_listener).

-behaviour(gen_server).
-behaviour(gen_data_reader_listener).


-export([start_link/2,on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state, {msg_module, callback}).

start_link(MsgModule,Callback) -> 
        gen_server:start_link(?MODULE, #state{msg_module=MsgModule,callback=Callback}, []).
on_data_available(Name, {Reader, ChangeKey}) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_data_available, {Reader, ChangeKey}}).


init(#state{callback=Callback}=S) -> 
        pg:join({?MODULE,Callback}, self()), 
        {ok,S}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({on_data_available, { Reader, ChangeKey}},#state{msg_module=MsgModule,callback=Callback}=S) -> 
        Change = dds_data_r:read(Reader, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        Callback(MsgModule:parse(SerializedPayload)),
        {noreply,S};
handle_cast(_,S) -> {noreply,S}.

