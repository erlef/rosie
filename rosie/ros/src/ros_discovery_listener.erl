-module(ros_discovery_listener).

-behaviour(gen_server).
-behaviour(gen_data_reader_listener).

-export([start_link/0, on_data_available/2]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("rmw_dds_common/src/_rosie/rmw_dds_common_participant_entities_info_msg.hrl").

start_link() ->
    gen_server:start_link(?MODULE, [], []).

on_data_available(Name, {ReaderPid, ChangeKey}) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_data_available, {ReaderPid, ChangeKey}}).

init(S) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    pg:join(?MODULE, self()),
    {ok, S}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({on_data_available, {ReaderPid, ChangeKey}}, S) ->
    Change = dds_data_r:read(ReaderPid, ChangeKey),
    SerializedPayload = Change#cacheChange.data,
    %io:format("ROS: notified of new discovery data:\n"),
    {Info, _} = participant_entities_info_msg:parse(SerializedPayload),
    %Info = parse_ros_discovery_info(SerializedPayload),
    io:format("ROS: Participant GID: ~p\n",
              [Info#rmw_dds_common_participant_entities_info.gid]),
    io:format("ROS: found ~p nodes:\n",
              [erlang:length(Info#rmw_dds_common_participant_entities_info.node_entities_info_seq)]),
    [print_node_info(I)
     || I <- Info#rmw_dds_common_participant_entities_info.node_entities_info_seq],
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

print_node_info(#rmw_dds_common_node_entities_info{node_namespace = Namespace,
                                                   node_name = NodeName,
                                                   reader_gid_seq = EntitiesR,
                                                   writer_gid_seq = EntitiesW}) ->
    io:format("ROS: ~s~s\n", [Namespace, NodeName]),
    io:format("\tReaders -> ~p\n", [EntitiesR]),
    io:format("\tWriters -> ~p\n", [EntitiesW]).

% parse_ros_discovery_info(<<GID:16/binary, _:8/binary, 0:32/little>>) ->
%         #participant_entities_info{
%                 gid = GID
%         };
% parse_ros_discovery_info(<<GID:16/binary, _:8/binary, NodesNumber:32/little,Seq/binary>>) ->
%         #participant_entities_info{
%                 gid = GID,
%                 node_entities_info_seq = parse_node_list(NodesNumber,Seq,[])
%         }.

% parse_entity_list(Payload) ->
%         parse_entity_list([],Payload).

% parse_entity_list(GIDS,<<GID:16/binary,_:8/binary,Other/binary>>) ->
%         parse_entity_list([GID|GIDS], Other);
% parse_entity_list(GIDS,<<>>) ->
%         GIDS.

% parse_node_list(0, _, NodesInfos) -> NodesInfos;
% parse_node_list(NodesNumber, <<Namespace_L:32/little, Namespace:(Namespace_L-1)/binary, _:( 4 - (Namespace_L-1) rem 4)/binary,
%                 NodeName_L:32/little, NodeName:(NodeName_L-1)/binary, _:( 4 - (NodeName_L-1) rem 4)/binary,
%                 W_L:32/little, W_List:(W_L*24)/binary,R_L:32/little, R_List:(R_L*24)/binary,
%                 Rest/binary>>, NodesInfos) ->
%         %io:format("ROS: ~p --  ~p\n",[MessageSequenceNumber,Rest]),
%         Node = #node_entities_info{
%                 node_namespace = Namespace,
%                 node_name = NodeName,
%                 reader_gid_seq = parse_entity_list(R_List),
%                 writer_gid_seq = parse_entity_list(W_List)
%         },
%         parse_node_list(NodesNumber-1, Rest, NodesInfos ++ [Node]).
