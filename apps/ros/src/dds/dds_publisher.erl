-module(dds_publisher).

-behaviour(gen_server).

-export([start_link/1,create_datawriter/2,lookup_datawriter/2]).%,suspend_publications/1,resume_pubblications/1]).
-export([init/1, handle_call/3, handle_cast/2,handle_info/2]).

-include("../protocol/rtps_constants.hrl").
-include("../protocol/rtps_structure.hrl").

-record(state,{
        domain_participant,
        rtps_participant_info=#participant{},
        builtin_sub_announcer,
        data_writers = #{},
        incremental_key=1}).

start_link(Setup) -> gen_server:start_link( ?MODULE, Setup,[]).

create_datawriter(Pid,Topic) -> gen_server:call(Pid,{create_datawriter,Topic}).
lookup_datawriter(Pid,Topic) -> gen_server:call(Pid,{lookup_datawriter,Topic}).

%callbacks 
init({DP, P_info}) ->  
        % the Subscription-writer(aka announcer) will forward my willing to listen to defined topics
        EntityID = ?ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER,        
        {ok,DW} = dds_data_w:start_link({builtin_sub_announcer,P_info,self(),EntityID}),
        {ok,#state{domain_participant=DP, rtps_participant_info=P_info, builtin_sub_announcer = DW}}.

handle_call({create_datawriter,Topic}, _, #state{rtps_participant_info=I,data_writers=Writers, incremental_key = K}=S) -> 
        EntityID = #entityId{kind=?EKIND_USER_Writer_NO_Key,key = <<K:24>>},        
        {ok,DW} = dds_data_w:start_link({Topic,I,self(),EntityID}),
        {reply, DW, S#state{data_writers = Writers#{EntityID => DW}, incremental_key = K+1 }};

handle_call({lookup_datawriter,builtin_sub_announcer}, _, State) -> {reply,State#state.builtin_sub_announcer,State};
handle_call({lookup_datawriter,Topic}, _, State) -> {reply,ok,State};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast(_, State) -> {noreply,State}.

handle_info(_,State) -> {noreply,State}.