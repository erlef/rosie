-module(ros_discovery_listener).

-behaviour(gen_server).
-behaviour(gen_data_reader_listener).


-export([start_link/0,on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("ros/include/rmw_dds_msg.hrl").

start_link() -> gen_server:start_link(?MODULE, [], []).
on_data_available(Name, {ReaderPid, ChangeKey}) -> 
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid,{on_data_available, {ReaderPid, ChangeKey}}).

init(S) -> 
        %io:format("~p.erl STARTED!\n",[?MODULE]),
        pg:join(?MODULE, self()),
        {ok,S}.
handle_call(_,_,S) -> {reply,ok,S}.
handle_cast({on_data_available, { ReaderPid, ChangeKey}},S) -> 
        Change = dds_data_r:read(ReaderPid, ChangeKey),
        SerializedPayload = Change#cacheChange.data,
        io:format("ROS: notified of new discovery data:\n"),
        Info = parse_ros_discovery_info(SerializedPayload),
        %io:format("ROS: Participant GID: ~p\n",[Info#participant_entities_info.gid]),
        %io:format("ROS: found ~p nodes:\n",[ erlang:length(Info#participant_entities_info.node_entities_info_seq)]),
        %[io:format("ROS: ~s~s\n",[NNS,NN]) || #node_entities_info{node_namespace=NNS,node_name=NN}  <- Info#participant_entities_info.node_entities_info_seq],
        {noreply,S};
handle_cast(_,S) -> {noreply,S}.


parse_ros_discovery_info(<<GID:16/binary, _:8/binary, 0:32/little>>) -> 
        #participant_entities_info{
                gid = GID
        };
parse_ros_discovery_info(<<GID:16/binary, _:8/binary, NodesNumber:32/little,Seq/binary>>) -> 
        #participant_entities_info{
                gid = GID,        
                node_entities_info_seq = parse_node_list(NodesNumber,Seq,[])
        }.

parse_node_list(0, _, NodesInfos) -> NodesInfos;
parse_node_list(NodesNumber, <<Namespace_L:32/little, Namespace:(Namespace_L-1)/binary, _:( 4 - (Namespace_L-1) rem 4)/binary,
                NodeName_L:32/little, NodeName:(NodeName_L-1)/binary, _:( 4 - (NodeName_L-1) rem 4)/binary,
                MessageSequenceNumber:32/little, Entities/binary>>, NodesInfos) ->
        Node = #node_entities_info{
                node_namespace = Namespace,
                node_name = NodeName
        },
        parse_node_list(0, Entities, NodesInfos ++ [Node]).