-module(rtps_network_utils).


-export([get_local_ip/0]).


get_ipv4_from_opts([]) ->
        {0, 0, 0, 0};
    get_ipv4_from_opts([{addr, {_1, _2, _3, _4}} | _]) ->
        {_1, _2, _3, _4};
    get_ipv4_from_opts([_ | TL]) ->
        get_ipv4_from_opts(TL).
    
flags_are_ok(Cfg) ->
        [{flags, Flags} | _] = Cfg,
        lists:member(up, Flags)
        and lists:member(running, Flags)
        and not lists:member(loopback, Flags).
    
get_local_ip() ->
        {ok, Interfaces} = inet:getifaddrs(),
        % getting the first interface that is at least up and running and not for loopback
        [Opts | _] = [Cfg || {Name, Cfg} <- Interfaces, flags_are_ok(Cfg)],
        get_ipv4_from_opts(Opts).
    