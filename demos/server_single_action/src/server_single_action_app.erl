-module(server_single_action_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    server_single_action_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
