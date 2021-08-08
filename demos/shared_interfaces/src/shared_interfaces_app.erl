-module(shared_interfaces_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    interface_compile:file("AddTwoInts.srv"),
    dummy_sup:start_link().

stop(_State) ->
    ok.

%% internal functions

