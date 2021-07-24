-module(spawn_interface).

-export([get_name/0, get_type/0, serialize_request/1, parse_reply/1]).

get_name() -> "spawn".

get_type() -> "turtlesim::srv::dds_::Spawn_".

serialize_request({X,Y,Theta,_}) ->
        <<X/float-little, Y/float-little, Theta/float-little>>.

parse_reply(Payload) ->
        ok.