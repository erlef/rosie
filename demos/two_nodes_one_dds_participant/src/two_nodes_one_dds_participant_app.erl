-module(two_nodes_one_dds_participant_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    two_nodes_one_dds_participant_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
