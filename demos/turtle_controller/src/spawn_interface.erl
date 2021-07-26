-module(spawn_interface).

-export([get_name/0, get_type/0, serialize_request/1, serialize_reply/1, parse_request/1, parse_reply/1]).

% GENERAL
get_name() -> "spawn".

get_type() -> "turtlesim::srv::dds_::Spawn_".

% CLIENT
serialize_request({X,Y,Theta,Name}) ->
        L= length(Name),
        <<"12345678",1:32/little, 0:32, X:32/float-little, Y:32/float-little,Theta:32/float-little, 
                (L+1):32/little,(list_to_binary(Name))/binary,0:8>>.


parse_reply(<<_:8/binary,1:32/little, 0:32, L:32/little, Name:(L-1)/binary, _/binary>>) ->
        binary_to_list(Name).

% SERVER        
serialize_reply(Info) -> 
        <<Info>>.

parse_request(<<X/float-little, Y/float-little, Theta/float-little>>) ->
        {X,Y,Theta}.
