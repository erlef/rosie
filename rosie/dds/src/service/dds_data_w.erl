-module(dds_data_w).


-export([start_link/1, write/2, get_matched_subscriptions/1, remote_reader_add/2, is_sample_acknowledged/2,
         remote_reader_remove/2, match_remote_readers/2, wait_for_acknoledgements/1,
         flush_all_changes/1]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state, {topic, rtps_writer, history_cache}).

start_link(Setup) ->
    gen_server:start_link(?MODULE, Setup, []).

get_matched_subscriptions(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_matched_subscriptions).

match_remote_readers(Name, R) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {match_remote_readers, R}).

remote_reader_add(Name, R) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {remote_reader_add, R}).

remote_reader_remove(Name, R) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {remote_reader_remove, R}).

write(Name, MSG) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {write, MSG}).

is_sample_acknowledged(Name, ChangeKey) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {is_sample_acknowledged, ChangeKey}).

wait_for_acknoledgements(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, wait_for_acknoledgements).

flush_all_changes(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, flush_all_changes).

%callbacks
init({Topic, #participant{guid = ID}, GUID}) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    pg:join({data_w_of, GUID}, self()),
    %[P|_] = pg:get_members(ID),
    %W = rtps_participant:create_full_writer(P, WriterConfig, Cache),% rtps_full_writer:create({P, WriterConfig, Cache}),
    {ok,
     #state{topic = Topic,
            rtps_writer = GUID,
            history_cache = {cache_of, GUID}}}.

handle_call(get_matched_subscriptions, _, #state{rtps_writer = W} = S) ->
    Matched = [ P#reader_proxy.guid || #reader_proxy{ready=Ready}=P <- rtps_full_writer:get_matched_readers(W), Ready],
    {reply, Matched, S};
handle_call({is_sample_acknowledged, ChangeKey}, _, #state{rtps_writer = W} = S) ->
    {reply, rtps_full_writer:is_acked_by_all(W,ChangeKey), S};
handle_call(wait_for_acknoledgements, _, #state{rtps_writer = W} = S) ->
    % not implemented
    io:format("DDS_DATA_W: wait_for_acknoledgements Not implemented\n"),
    {reply, ok, S};
handle_call(flush_all_changes, _, #state{rtps_writer = W} = S) ->
    rtps_full_writer:flush_all_changes(W),
    {reply, ok, S};
handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({match_remote_readers, R}, #state{rtps_writer = W} = S) ->
    rtps_full_writer:update_matched_readers(W, R),
    {noreply, S};
handle_cast({remote_reader_add, R}, #state{rtps_writer = W} = S) ->
    rtps_full_writer:matched_reader_add(W, R),
    {noreply, S};
handle_cast({remote_reader_remove, Reader}, #state{ rtps_writer = W} = S) ->
    rtps_full_writer:matched_reader_remove(W, Reader),
    {noreply, S};
handle_cast({write, Msg}, #state{history_cache = Cache, rtps_writer = W} = S) ->
    %io:format("Writing: ~p\n",[Msg]),
    Change = rtps_full_writer:new_change(W, Msg),
    rtps_history_cache:add_change(Cache, Change),
    {noreply, S};
handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.
