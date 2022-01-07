-module(server_abort_goals_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    server_abort_goals_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
