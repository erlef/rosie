-module(spawn_interface).

-export([get_name/0, get_type/0, serialize_request/1, serialize_reply/1, parse_request/1, parse_reply/1]).

get_name() -> "spawn".

get_type() -> "turtlesim::srv::dds_::Spawn_".

serialize_request({X,Y,Theta,_}) ->
        <<X/float-little, Y/float-little, Theta/float-little>>.

serialize_reply(Name) ->
        <<Name/binary>>.

parse_request(<<X/float-little, Y/float-little, Theta/float-little>>) ->
        {X,Y,Theta}.

parse_reply(Payload) ->
        Payload.