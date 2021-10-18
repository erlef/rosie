-module(dds_sup).

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
    SupFlags =
        #{strategy => one_for_all,
          intensity => 0,
          period => 1},
    PG = #{id => pg,
           start => {pg, start_link, []},
           restart => permanent,
           shutdown => 5000,
           type => worker},
    RTPS_Participant =
        #{id => rtps_part,
          start => {rtps_participant, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    WIRE =
        #{id => wire,
          start => {rtps_wire_sup, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => supervisor},
    PUB_SUP =
        #{id => pub_sup,
          start => {dds_publisher_sup, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => supervisor},
    SUB_SUP =
        #{id => sub_sup,
          start => {dds_subscriber_sup, start_link, []},
          restart => permanent,
          shutdown => 5000,
          type => supervisor},
    DomainParticipant =
        #{id => dds_part,
          start => {dds_domain_participant, start_link, [self()]},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    ChildSpecs = [PG, RTPS_Participant, SUB_SUP, PUB_SUP, WIRE, DomainParticipant],

    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
