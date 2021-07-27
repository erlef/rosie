-module(add_two_ints_srv).

-export([get_name/0, get_type/0, serialize_request/2, serialize_reply/2, parse_request/1, parse_reply/1]).

% GENERAL
get_name() -> 
        "add_two_ints".

get_type() -> 
        "example_interfaces::srv::dds_::AddTwoInts_".

% CLIENT
serialize_request(Client_ID,{A,B}) -> 
        <<Client_ID:8/binary, 1:64/little, A:64/signed-little, B:64/signed-little>>.


parse_reply(<<Client_ID:8/binary, 1:64/little, R:64/signed-little>>) ->
        {Client_ID, R}.

% SERVER        
serialize_reply(Client_ID,R) -> 
        <<Client_ID:8/binary, 1:64/little, R:64/signed-little>>.

parse_request(<<Client_ID:8/binary, 1:64/little, A:64/signed-little, B:64/signed-little>>) ->        
        {Client_ID,{A,B}}.
