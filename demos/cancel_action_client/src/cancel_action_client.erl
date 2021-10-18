-module(cancel_action_client).

-export([start_link/0]).

-behaviour(gen_action_client_listener).

-export([on_send_goal_reply/2, on_get_result_reply/2, on_feedback_message/2,
         on_cancel_goal_reply/2]).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are going to use Fibonacci.action, so we include its header to use record definitions of all its components.
-include_lib("example_interfaces/src/_rosie/example_interfaces_fibonacci_action.hrl").

-record(state, {ros_node, action_client, goal_info}).

-define(LOCAL_SRV, action_client).

start_link() ->
    gen_server:start_link({local, ?LOCAL_SRV}, ?MODULE, [], []).

% callbacks for gen_action_client
on_send_goal_reply(Pid, Msg) ->
    gen_server:cast(Pid, {on_send_goal_reply, Msg}).

on_get_result_reply(Pid, Msg) ->
    gen_server:cast(Pid, {on_get_result_reply, Msg}).

on_cancel_goal_reply(Pid, Msg) ->
    gen_server:cast(Pid, {on_cancel_goal_reply, Msg}).

on_feedback_message(Pid, Msg) ->
    gen_server:cast(Pid, {on_feedback_message, Msg}).

% callbacks for gen_server
init(_) ->
    Node = ros_context:create_node("cancel_action_client"),

    % The action uses our Node to create it's services and topics
    ActionClient =
        ros_context:create_action_client(Node,
                                         example_interfaces_fibonacci_action,
                                         {?MODULE, self()}),

    ros_action_client:wait_for_server(ActionClient, 1000),

    {ok, #state{ros_node = Node, action_client = ActionClient}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({on_send_goal_reply,
             #example_interfaces_fibonacci_send_goal_rp{responce_code = Responce, timestamp = T}},
            #state{goal_info = #action_msgs_goal_info{goal_id = GOAL_ID}} = S) ->
    case Responce of
        1 ->
            io:format("Goal accepted :)\n"),
            erlang:send_after(3000, self(), send_cancel_goal);
        _ ->
            io:format("Goal rejected with code ~p\n", [Responce])
    end,
    {noreply, S#state{goal_info = #action_msgs_goal_info{goal_id = GOAL_ID, stamp = T}}};
handle_cast({on_get_result_reply,
             #example_interfaces_fibonacci_get_result_rp{sequence = Seq}},
            S) ->
    io:format("Result received: ~p\n", [Seq]),
    {noreply, S};
handle_cast({on_cancel_goal_reply,
             #action_msgs_cancel_goal_rp{return_code = Code, goals_canceling = Seq}},
            S) ->
    io:format("Cancel operation returned: ~p \nGoals that are being cancelled:\n", [Code]),
    [io:format("\t~p\n", [ID])
     || #action_msgs_goal_info{goal_id = #unique_identifier_msgs_u_u_i_d{uuid = ID}} <- Seq],
    {noreply, S};
handle_cast({on_feedback_message,
             #example_interfaces_fibonacci_feedback_message{sequence = Seq}},
            S) ->
    io:format("Received feedback: ~p\n", [Seq]),
    {noreply, S};
handle_cast(_, S) ->
    {noreply, S}.

handle_info(ros_action_server_ready, #state{action_client = C} = S) ->
    io:format("Action Server detected...\n"),
    Goal = example_interfaces_fibonacci_action:goal(),
    ros_action_client:send_goal(C,
                                Goal#example_interfaces_fibonacci_send_goal_rq{order = 10}),
    {noreply,
     S#state{goal_info =
                 #action_msgs_goal_info{goal_id =
                                            Goal#example_interfaces_fibonacci_send_goal_rq.goal_id}}};
handle_info(ros_timeout, #state{action_client = C} = S) ->
    io:format("Action Server not found... trying again...\n"),
    ros_action_client:wait_for_server(C, 1000),
    {noreply, S};
handle_info(send_cancel_goal,
            #state{action_client = C, goal_info = #action_msgs_goal_info{goal_id = UUID}} = S) ->
    io:format("Asking server to cancel goal: ~p\n",
              [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    % We send only the goal_id, sending the time will have the server cancel also all previous goals
    ros_action_client:cancel_goal(C,
                                  #action_msgs_cancel_goal_rq{goal_info =
                                                                  #action_msgs_goal_info{goal_id =
                                                                                             UUID}}),
    {noreply, S}.
