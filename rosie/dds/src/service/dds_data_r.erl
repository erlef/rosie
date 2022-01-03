-module(dds_data_r).


-export([start_link/1, read/2, get_matched_publications/1, read_all/1,
         on_change_available/2, on_change_removed/2, set_listener/2, remote_writer_add/2,
         remote_writer_remove/2, match_remote_writers/2]).
        
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state,
        {topic, listener = not_set, rtps_reader, matched_data_writers = [], history_cache}).

start_link(Setup) ->
    gen_server:start_link(?MODULE, Setup, []).

get_matched_publications(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_matched_publications).

on_change_available(Name, ChangeKey) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {on_change_available, ChangeKey}).

on_change_removed(Name, ChangeKey) ->
    % DO NOTHING
    % As a dds_reader we do not notify (for now), the event cming from the cache
    ok.

set_listener(Name, Listener) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {set_listener, Listener}).

read(Name, Change) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, {read, Change}).

read_all(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, read_all).

match_remote_writers(Name, Writers) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {match_remote_writers, Writers}).

remote_writer_add(Name, W) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {remote_writer_add, W}).

remote_writer_remove(Name, W) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {remote_writer_remove, W}).

%callbacks
init({Topic, #participant{guid = ID}, GUID}) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    pg:join({data_r_of, GUID}, self()),
    rtps_history_cache:set_listener({cache_of, GUID}, {?MODULE, {data_r_of, GUID}}),
    % [P|_] = pg:get_members(ID),
    % R = rtps_participant:create_full_reader(P,ReaderConfig,Cache),
    {ok,
     #state{topic = Topic,
            rtps_reader = GUID,
            history_cache = {cache_of, GUID}}}.

handle_call(get_matched_publications, _, #state{matched_data_writers = Matched} = S) ->
    {reply, Matched, S};
handle_call({read, ChangeKey}, _, #state{history_cache = C} = S) ->
    {reply, rtps_history_cache:get_change(C, ChangeKey), S};
handle_call(read_all, _, #state{history_cache = C} = S) ->
    {reply, rtps_history_cache:get_all_changes(C), S};
handle_call({set_listener, L}, _, State) ->
    {reply, ok, State#state{listener = L}};
handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({on_change_available, _}, #state{listener = L} = S) when L == not_set ->
    {noreply, S};
handle_cast({on_change_available, ChangeKey},
            #state{rtps_reader = GUID, listener = {Module, Name}} = S) ->
    Module:on_data_available(Name, {{data_r_of, GUID}, ChangeKey}),
    {noreply, S};
handle_cast({match_remote_writers, Writers},
            #state{matched_data_writers = DW, rtps_reader = Reader} = S) ->
    rtps_full_reader:update_matched_writers(Reader, Writers),
    {noreply, S#state{matched_data_writers = [G || #writer_proxy{guid = G} <- Writers]}};
handle_cast({remote_writer_add, W},
            #state{matched_data_writers = DW, rtps_reader = Reader} = S) ->
    rtps_full_reader:matched_writer_add(Reader, W),
    {noreply, S#state{matched_data_writers = [W#writer_proxy.guid | DW]}};
handle_cast({remote_writer_remove, Writer},
            #state{matched_data_writers = DW, rtps_reader = Reader} = S) ->
    rtps_full_reader:matched_writer_remove(Reader, Writer),
    {noreply, S#state{matched_data_writers = [W || W <- DW, W /= Writer]}};
handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.
