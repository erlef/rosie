-module(dds_datawriters_pool_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional

init([]) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    SupFlags =
        #{strategy => simple_one_for_one,
          intensity => 0,
          period => 1},

    ChildSpecs =
        [#{id => dds_endpoint_sup,
           start => {dds_endpoint_sup, start_link, []},
           restart => transient,
           shutdown => 5000,
           type => supervisor}],

    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
