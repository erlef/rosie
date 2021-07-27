-module(spawn_srv).

-export([get_name/0, get_type/0, serialize_request/2, serialize_reply/2, parse_request/1, parse_reply/1]).

% GENERAL
get_name() -> "spawn".

get_type() -> "turtlesim::srv::dds_::Spawn_".

% CLIENT
serialize_request(Client_ID, {X,Y,Theta,Name}) ->
        L= length(Name),
        <<Client_ID:8/binary,1:64/little, X:32/float-little, Y:32/float-little,Theta:32/float-little, 
                (L+1):32/little,(list_to_binary(Name))/binary,0:8>>.


parse_reply(<<Client_ID:8/binary,1:32/little, 0:32, L:32/little, Name:(L-1)/binary, _/binary>>) ->
        {Client_ID, binary_to_list(Name)}.

% SERVER        
serialize_reply(Client_ID, Name) -> 
        L= length(Name),
        <<Client_ID:8/binary, 1:64/little, (L+1):32/little,(list_to_binary(Name))/binary,0:8>>.

parse_request(<<Client_ID:8/binary, 1:64/little, X:32/float-little, Y:32/float-little, 
                Theta:32/float-little, L:32/little, Name:(L-1)/binary,0:8>>) ->
        {Client_ID,{X,Y,Theta,Name}}.
