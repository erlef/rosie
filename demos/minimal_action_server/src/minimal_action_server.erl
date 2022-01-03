-module(minimal_action_server).

-export([start_link/0]).

-behaviour(gen_action_server_listener).

-export([on_new_goal_request/2, on_execute_goal/2, on_cancel_goal_request/2,
         on_cancel_goal/2]).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are going to use Fibonacci.action, so we include its header to use record definitions of all of its components.
-include_lib("example_interfaces/src/_rosie/example_interfaces_fibonacci_action.hrl").

-record(state, {ros_node, action_server, goal_id = none}).

-define(LOCAL_SRV, action_client).

start_link() ->
    gen_server:start_link({local, ?LOCAL_SRV}, ?MODULE, [], []).

% callbacks for gen_action_server_listener
on_new_goal_request(Pid, Msg) ->
    gen_server:call(Pid, {on_new_goal_request, Msg}).

on_execute_goal(Pid, Goal) ->
    gen_server:cast(Pid, {on_execute_goal, Goal}).

on_cancel_goal_request(Pid, Goal) ->
    gen_server:call(Pid, {on_cancel_goal_request, Goal}).

on_cancel_goal(Pid, Goal) ->
    gen_server:cast(Pid, {on_cancel_goal, Goal}).

% callbacks for gen_server
init(_) ->
    Node = ros_context:create_node("minimal_action_server"),

    % The action uses our Node to create it's services and topics
    ActionServer =
        ros_context:create_action_server(Node,
                                         example_interfaces_fibonacci_action,
                                         {?MODULE, self()}),

    {ok, #state{ros_node = Node, action_server = ActionServer}}.

% This server only accepts one goal at a time, we reject all the others if goal_id is already set
handle_call({on_new_goal_request, #example_interfaces_fibonacci_send_goal_rq{goal_id = UUID}},
            _, #state{goal_id = none} = S) ->
    io:format("Received goal request with id ~p\n",[UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    {reply, #example_interfaces_fibonacci_send_goal_rp{responce_code = 1}, S};
handle_call({on_new_goal_request, #example_interfaces_fibonacci_send_goal_rq{goal_id = UUID}},
            _, S) ->
    io:format("Rejecting goal request with id ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    {reply, #example_interfaces_fibonacci_send_goal_rp{responce_code = 0}, S};
handle_call({on_cancel_goal_request, #action_msgs_cancel_goal_rq{goal_info = #action_msgs_goal_info{goal_id = UUID}}},
            _, S) ->
    io:format("Accepting cancel request for ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    % Accepting will put the action in cancelling state
    {reply, accept, S}; % use 'reject' atom to reject the cancel request
handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({on_execute_goal,
             #example_interfaces_fibonacci_send_goal_rq{goal_id = UUID, order = ORDER}},
            S) ->
    io:format("Executing goal: ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    erlang:send_after(1000, self(), {next_step, [1, 0], ORDER - 2}),
    {noreply, S#state{goal_id = UUID}};
handle_cast({on_cancel_goal, UUID}, #state{action_server = AS} = S) ->
    % Here we can take as much time to stop the action while its in canceling state
    % Once called ros_action_server:cancel_goal the anction is marked as CANCELED
    ros_action_server:cancel_goal(AS, UUID),
    io:format("Goal was canceled.\n"),
    % For simpicity we set the id to none to easly stop the loop
    {noreply, S#state{goal_id = none}};
handle_cast(_, S) ->
    {noreply, S}.

handle_info({next_step, _, _}, #state{goal_id = none} = S) ->
    {noreply, S};
handle_info({next_step, L, Counter}, #state{action_server = AS, goal_id = UUID} = S)
    when Counter < 0 ->
    List = lists:reverse(L),
    io:format("Returning result: ~p\n", [List]),
    ros_action_server:publish_result(AS,
                                     UUID,
                                     #example_interfaces_fibonacci_get_result_rp{goal_status = 4,
                                                                                 sequence = List}),
    {noreply, S#state{goal_id = none}};
handle_info({next_step, [Last_1, Last_2 | _] = L, Counter},
            #state{action_server = AS, goal_id = UUID} = S) ->
    Step = [Last_1 + Last_2 | L],
    List = lists:reverse(Step),
    io:format("Publishing feedback: ~p\n", [List]),
    ros_action_server:publish_feedback(AS,
                                       #example_interfaces_fibonacci_feedback_message{goal_id =
                                                                                          UUID,
                                                                                      sequence =
                                                                                          List}),
    erlang:send_after(1000, self(), {next_step, [Last_1 + Last_2 | L], Counter - 1}),
    {noreply, S}.
