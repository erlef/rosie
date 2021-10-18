-module(minimal_client).

-export([start_link/0, ask/1, ask_async/1]).

-behaviour(gen_client_listener).

-export([on_service_reply/2]).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are going to use AddTwoInts.msg, so we include its header to use its record definition.
-include_lib("example_interfaces/src/_rosie/example_interfaces_add_two_ints_srv.hrl").

-record(state, {ros_node, add_client}).

-define(LOCAL_SRV, client).

start_link() ->
    gen_server:start_link({local, ?LOCAL_SRV}, ?MODULE, [], []).

on_service_reply(Pid, Msg) ->
    gen_server:cast(Pid, {on_service_reply, Msg}).

ask(Info) ->
    gen_server:call(?LOCAL_SRV, {ask, Info}).

ask_async(Info) ->
    gen_server:cast(?LOCAL_SRV, {ask_async, Info}).

init(_) ->
    Node = ros_context:create_node("minimal_client"),

    Client =
        ros_node:create_client(Node, example_interfaces_add_two_ints_srv, {?MODULE, self()}),

    ros_client:wait_for_service(Client, 1000),

    {ok, #state{ros_node = Node, add_client = Client}}.

handle_call({ask, {A, B}}, _, #state{add_client = C} = S) ->
    case ros_client:service_is_ready(C) of
        true ->
            #example_interfaces_add_two_ints_rp{sum = R} =
                ros_client:call(C, #example_interfaces_add_two_ints_rq{a = A, b = B}),
            {reply, R, S};
        false ->
            {reply, service_unavailable, S}
    end;
handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({ask_async, {A, B}}, #state{add_client = C} = S) ->
    ros_client:cast(C, #example_interfaces_add_two_ints_rq{a = A, b = B}),
    {noreply, S};
handle_cast({on_service_reply, #example_interfaces_add_two_ints_rp{sum = R}}, S) ->
    io:format("Result: ~p\n", [R]),
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

handle_info(ros_service_ready, #state{add_client = C} = S) ->
    io:format("Server detected...\n"),
    ros_client:cast(C, #example_interfaces_add_two_ints_rq{a = 1, b = 2}),
    {noreply, S};
handle_info(ros_timeout, #state{add_client = C} = S) ->
    io:format("Service not found... trying again...\n"),
    ros_client:wait_for_service(C, 1000),
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.
