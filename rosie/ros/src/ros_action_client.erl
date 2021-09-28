-module(ros_action_client).

-export([start_link/3,wait_for_server/2,send_goal/2,get_result/2]).

-behaviour(gen_client_listener).
-export([on_service_reply/2]).
-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2]).


-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/dds_types.hrl").

-record(state,{node,
        % module holding interface infos
        action_interface, 
        % ros clients to serve this action
        request_goal_client,        
        cancel_goal_client,
        get_result_client,
        % ros subscription to remote topics for this action
        feed_subscription,        
        status_subscription,
        % user callbacks
        callback_handler
}).

start_link(Node, Action, {CallbackModule,Pid}) -> 
        gen_server:start_link(?MODULE, #state{node = Node, 
                action_interface = Action,
                callback_handler = {CallbackModule,Pid}}, []).

wait_for_server(Name,Timeout) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{wait_for_server,Timeout}).
send_goal(Name, GoalRequest) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{send_goal, GoalRequest}).
get_result(Name,ResultRequest) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{get_result,ResultRequest}).


on_service_reply(Name, Msg) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {on_service_reply, Msg}).

on_topic_msg(Name, Msg) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {on_topic_msg, Msg}).

%callbacks
init(#state{node = Node, action_interface = Action,
                        callback_handler = CallbackHandler}=S) ->
        Name = {?MODULE,Action},
        pg:join(Name, self()),

        %customized by the user
        RequestGoalClient = ros_node:create_client(Node, Action:get_goal_srv_module(), {?MODULE,Name}),        
        GetResultClient = ros_node:create_client(Node, Action:get_result_srv_module(), {?MODULE,Name}),        
        FeedbackSub = ros_node:create_subscription(Node, Action:get_feedback_msg_module(), Action:get_feedback_topic_name(), {?MODULE,Name}),
        
        % equal to any action
        StatusSub = ros_node:create_subscription(Node, goal_status_array_msg,  Action:get_status_topic_name(), {?MODULE,Name}),
        %% TODO cancel srv has generic type but name is specific!!! must add "action_name/_action/" to the srv name
        %CancelGoalClient = ros_node:create_client(Node, cancel_goal_srv, fun test_cancel/1),

        {ok,S#state{
        request_goal_client = RequestGoalClient,        
        %cancel_goal_client,
        get_result_client = GetResultClient,
        % ros subscription to remote topics for this action
        feed_subscription = FeedbackSub,        
        status_subscription =StatusSub
}}.

handle_call({wait_for_server,Timeout}, {Caller,_}, S) -> 
        self() ! {wait_for_server_loop, Caller, Timeout, now()},
        {reply,ok,S};
handle_call({send_goal,GoalRequest},_,S) -> 
        h_send_goal(GoalRequest,S),
        {reply,ok,S};
handle_call({get_result,ResultRequest},_,S) ->
        h_get_result(ResultRequest,S),
        {reply,ok,S};
handle_call(_,_,S) -> {reply,ok,S}.

        
handle_cast({on_service_reply,Msg},#state{action_interface= AI, callback_handler={M,Pid}}=S) -> 
        case AI:identify_msg(Msg) of
                send_goal_rp -> M:on_send_goal_reply(Pid,Msg);
                get_result_rp -> M:on_get_result_reply(Pid,Msg);
                _ -> io:format("[ROS_ACTION]: BAD MSG RECEIVED FROM SERVICE\n")
        end,
        {noreply,S};
handle_cast({on_topic_msg,Msg},#state{action_interface= AI, callback_handler={M,Pid}}=S) ->
        case AI:identify_msg(Msg) of
                goal_status_array -> {noreply, h_handle_status_update(Msg,S)};
                feedback_message -> M:on_feedback_message(Pid,Msg), {noreply,S};
                unknow_record -> {noreply,S}
        end;
handle_cast(_,S) -> {noreply,S}.

handle_info({wait_for_server_loop, Caller, Timeout, Start},S) ->
        case (timer:now_diff(now(), Start) div 1000) < Timeout of
                true -> case h_server_is_ready(S) of
                                true ->  erlang:send_after(300, Caller, ros_action_server_ready);
                                false -> erlang:send_after(10, self(), {wait_for_server_loop,Caller,Timeout,Start})
                        end;
                false -> Caller ! ros_timeout
        end,
        {noreply,S};
handle_info(_,S) ->
        {noreply,S}.

h_server_is_ready(#state{request_goal_client = RequestGoalClient,        
                        %cancel_goal_client,
                        get_result_client = GetResultClient}) -> 
        ros_client:service_is_ready(RequestGoalClient) and
        ros_client:service_is_ready(GetResultClient).

h_send_goal(GoalRequest,#state{ action_interface = ActionModule, request_goal_client = RequestGoalClient}) -> 
        ros_client:cast(RequestGoalClient, GoalRequest).

h_get_result(ResultRequest,#state{ get_result_client = GetResultClient}) -> 
        ros_client:cast(GetResultClient, ResultRequest).


h_handle_status_update(GoalStatusArrayMsg, S) -> 
        io:format("[ROS_ACTION_CLIENT]: received goal states update\n"),
        S.