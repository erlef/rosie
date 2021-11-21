-module(dds_endpoint_sup).

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("dds/include/rtps_structure.hrl").

start_link(Args) ->
    supervisor:start_link(?MODULE, Args).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional

init({data_writer, Topic, P_info, Config}) ->
    SupFlags =
        #{strategy => one_for_all,
          intensity => 0,
          period => 1},
    CACHE =
        #{id => writer_cache,
          start => {rtps_history_cache, start_link, [Config#endPoint.guid, Topic#dds_user_topic.qos_profile]},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    RTPS_WRITER =
        #{id => rtps_writer,
          start => {rtps_full_writer, start_link, [{P_info, Config}]},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    DDS_DW =
        #{id => dds_data_writer,
          start => {dds_data_w, start_link, [{Topic, P_info, Config#endPoint.guid}]},
          restart => permanent,
          shutdown => 5000,
          type => worker},

    ChildSpecs = [CACHE, RTPS_WRITER, DDS_DW],

    {ok, {SupFlags, ChildSpecs}};
init({data_reader, Topic, P_info, Config}) ->
    SupFlags =
        #{strategy => one_for_all,
          intensity => 0,
          period => 1},
    CACHE =
        #{id => reader_cache,
          start => {rtps_history_cache, start_link, [Config#endPoint.guid, Topic#dds_user_topic.qos_profile]},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    RTPS_READER =
        #{id => rtps_reader,
          start => {rtps_full_reader, start_link, [{P_info, Config}]},
          restart => permanent,
          shutdown => 5000,
          type => worker},
    DDS_DR =
        #{id => dds_data_reader,
          start => {dds_data_r, start_link, [{Topic, P_info, Config#endPoint.guid}]},
          restart => permanent,
          shutdown => 5000,
          type => worker},

    ChildSpecs = [CACHE, RTPS_READER, DDS_DR],

    {ok, {SupFlags, ChildSpecs}};
init({discovery_writer, P_info, Config, QOS}) ->
    SupFlags =
        #{strategy => one_for_all,
          intensity => 0,
          period => 1},
    CACHE =
        #{id => discovery_writer_cache,
          start => {rtps_history_cache, start_link, [Config#endPoint.guid, QOS]},      % mandatory
          restart => permanent,   % optional
          shutdown => 5000, % optional
          type => worker},   % optional
    RTPS_WRITER =
        #{id => discovery_writer,       % mandatory
          start => {rtps_writer, start_link, [P_info, Config]},      % mandatory
          restart => permanent,   % optional
          shutdown => 5000, % optional
          type => worker},   % optional
    ChildSpecs = [CACHE, RTPS_WRITER],
    {ok, {SupFlags, ChildSpecs}};
init({discovery_reader, P_info, Config, QOS}) ->
    SupFlags =
        #{strategy => one_for_all,
          intensity => 0,
          period => 1},
    CACHE =
        #{id => discovery_reader_cache,       % mandatory
          start => {rtps_history_cache, start_link, [Config#endPoint.guid, QOS]},      % mandatory
          restart => permanent,   % optional
          shutdown => 5000, % optional
          type => worker},   % optional
    RTPS_READER =
        #{id => discovery_reader,       % mandatory
          start => {rtps_reader, start_link, [P_info, Config]},      % mandatory
          restart => permanent,   % optional
          shutdown => 5000, % optional
          type => worker},   % optional
    ChildSpecs = [CACHE, RTPS_READER],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
