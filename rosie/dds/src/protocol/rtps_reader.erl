% Best-effort Stateless RTPS reader independent from any writer,
% it's not paired and is fully passive.
-module(rtps_reader).

-behaviour(gen_server).

-export([start_link/2, receive_data/2, get_cache/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-include_lib("dds/include/rtps_structure.hrl").

-record(state, {participant = #participant{}, entity = #endPoint{}, history_cache}).

%API
start_link(Participant, ReaderConfig) ->
    gen_server:start_link(%{local, ?E_ATOM(ReaderConfig#endPoint.endPointId#entityId.key)},
                          ?MODULE,
                          {Participant, ReaderConfig},
                          []).

get_cache(Name) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:call(Pid, get_cache).

receive_data(Name, Data) ->
    [Pid | _] = pg:get_members(Name),
    gen_server:cast(Pid, {receive_data, Data}).

% callbacks
init({Participant, ReaderConfig}) ->
    %io:format("~p.erl STARTED!\n",[?MODULE]),
    pg:join(ReaderConfig#endPoint.guid, self()),
    {ok,
     #state{participant = Participant,
            entity = ReaderConfig,
            history_cache = {cache_of, ReaderConfig#endPoint.guid}}}.

handle_call(get_cache, _, State) ->
    {reply, State#state.history_cache, State};
handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({receive_data, Data}, #state{history_cache = Cache} = State) ->
    %io:format("READER: Saving: ~p\n",[Data]),
    rtps_history_cache:add_change(Cache, data_to_cache_change(Data)),
    {noreply, State};
handle_cast(_, State) ->
    {noreply, State}.

%helpers
data_to_cache_change({Writer, SN, Data}) ->
    #cacheChange{writerGuid = Writer,
                 sequenceNumber = SN,
                 data = Data}.
