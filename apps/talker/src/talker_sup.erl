-module(talker_sup).

-behaviour(supervisor).
-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 0,
                 period => 1},
    ChildSpecs = [],

    talker:start_link(),

    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
