-module(ros_sup).

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
    SupFlags = #{strategy => one_for_all,
                intensity => 0,
                period => 1},

    ROS_NODES_POOL =  #{id => ros_nodes_pool_sup,
            start => {ros_nodes_pool_sup,start_link,[]},
            restart => permanent,  
            shutdown => 5000,
            type => supervisor},
    ROS_CONTEXT =  #{id => ros_context,
            start => {ros_context,start_link,[]},
            restart => permanent,  
            shutdown => 5000,
            type => worker},
            
    ChildSpecs = [ROS_NODES_POOL,ROS_CONTEXT],

    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
