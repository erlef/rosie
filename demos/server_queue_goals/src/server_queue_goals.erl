-module(server_queue_goals).
-export([start_link/0]).

-behaviour(gen_action_server_listener).
-export([
    on_execute_goal/2, 
    on_cancel_goal_request/2,
    on_cancel_goal/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("example_interfaces/src/_rosie/example_interfaces_fibonacci_action.hrl").

-record(state, {
    ros_node, 
    action_server, 
    current_goal_id = none,
    pending_goals
}).

-define(LOCAL_SRV, action_client).

start_link() ->
    gen_server:start_link({local, ?LOCAL_SRV}, ?MODULE, #state{pending_goals = queue:new()}, []).

% callbacks for gen_action_server_listener
on_execute_goal(Pid, Goal) ->
    gen_server:cast(Pid, {on_execute_goal, Goal}).

on_cancel_goal_request(Pid, Goal) ->
    gen_server:call(Pid, {on_cancel_goal_request, Goal}).

on_cancel_goal(Pid, Goal) ->
    gen_server:cast(Pid, {on_cancel_goal, Goal}).

% callbacks for gen_server
init(S) ->
    Node = ros_context:create_node("server_single_action"),

    ActionServer =
        ros_context:create_action_server(Node,
                                         example_interfaces_fibonacci_action,
                                         {?MODULE, self()}),

    {ok, S#state{ros_node = Node, action_server = ActionServer}}.


handle_call({on_cancel_goal_request, #action_msgs_cancel_goal_rq{goal_info = #action_msgs_goal_info{goal_id = UUID}}}, _, S) ->
    io:format("Accepting cancel request for ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    {reply, accept, S};
handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({on_execute_goal,
             #example_interfaces_fibonacci_send_goal_rq{goal_id = UUID, order = ORDER}},
            #state{current_goal_id = none} = S) ->
    io:format("Executing goal: ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    erlang:send_after(1000, self(), {next_step, UUID, [1, 0], ORDER - 2}),
    {noreply, S#state{current_goal_id = UUID}};
handle_cast({on_execute_goal,
             #example_interfaces_fibonacci_send_goal_rq{goal_id = UUID, order = ORDER}},
             #state{pending_goals = QUEUE} = S) ->
    io:format("Postponing execution of goal: ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    {noreply, S#state{pending_goals = queue:in({UUID,ORDER},QUEUE)}};

handle_cast({on_cancel_goal, UUID}, #state{action_server = AS, current_goal_id = UUID} = S) ->
    ros_action_server:cancel_goal(AS, UUID),
    io:format("Goal ~p was canceled during execution.\n",[UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    {noreply, S#state{current_goal_id = none}};
handle_cast({on_cancel_goal, UUID}, #state{action_server = AS, current_goal_id = _ANOTHER, pending_goals = QUEUE} = S) ->
    ros_action_server:cancel_goal(AS, UUID),
    io:format("Goal ~p was canceled, removed from queue.\n",[UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    {noreply, S#state{pending_goals = queue:delete(UUID,QUEUE)}};
handle_cast(_, S) ->
    {noreply, S}.

handle_info({next_step, UUID, L, Counter}, #state{action_server = AS, pending_goals = QUEUE} = S) when Counter < 0 ->
    List = lists:reverse(L),
    io:format("Returning result: ~p\n", [List]),
    ros_action_server:publish_result(AS, UUID, #example_interfaces_fibonacci_get_result_rp{goal_status = 4, sequence = List}),
    case queue:out(QUEUE) of
        {{value, {NEXT_UUID,ORDER}}, Q2} ->
            io:format("Resuming executiuon of queued goal: ~p\n",[NEXT_UUID#unique_identifier_msgs_u_u_i_d.uuid]),
            erlang:send_after(1000, self(), {next_step,  NEXT_UUID, [1,0], ORDER - 2}),
            {noreply, S#state{current_goal_id = NEXT_UUID, pending_goals = Q2}};
        {empty, _}  ->
            {noreply, S#state{current_goal_id = none}}
    end;
handle_info({next_step, UUID,[Last_1, Last_2 | _] = L, Counter}, #state{action_server = AS} = S) ->
    Step = [Last_1 + Last_2 | L],
    List = lists:reverse(Step),
    io:format("Publishing feedback: ~p\n", [List]),
    ros_action_server:publish_feedback(AS, #example_interfaces_fibonacci_feedback_message{goal_id = UUID, sequence = List}),
    erlang:send_after(1000, self(), {next_step,  UUID, [Last_1 + Last_2 | L], Counter - 1}),
    {noreply, S}.
