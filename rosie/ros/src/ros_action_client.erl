-module(ros_action_client).

-export([start_link/3,wait_for_server/2,send_goal/2,get_result/2,cancel_goal/2]).

-behaviour(gen_client_listener).
-export([on_service_reply/2]).
-behaviour(gen_subscription_listener).
-export([on_topic_msg/2]).

-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2,handle_info/2]).

-include_lib("action_msgs/src/_rosie/action_msgs_goal_status_array_msg.hrl").
-include_lib("action_msgs/src/_rosie/action_msgs_cancel_goal_srv.hrl").

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

cancel_goal(Name, CancelGoalRequest) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid,{cancel_goal, CancelGoalRequest}).


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
        FeedbackSub = ros_node:create_subscription(Node, Action:get_feedback_msg_module(), Action:get_action_name()++"/_action/feedback", {?MODULE,Name}),
        
        %standard but names must be specialized for this action instance
        CancelGoalClient = ros_node:create_client(Node, {action_msgs_cancel_goal_srv, Action:get_action_name()++"/_action/"}, {?MODULE,Name}),
        StatusSub = ros_node:create_subscription(Node, action_msgs_goal_status_array_msg,  Action:get_action_name()++"/_action/status", {?MODULE,Name}),

        {ok,S#state{
        request_goal_client = RequestGoalClient,        
        cancel_goal_client = CancelGoalClient,
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
handle_call({cancel_goal,CancelGoalRequest},_,S) ->
        h_cancel_goal(CancelGoalRequest,S),
        {reply,ok,S};
handle_call(_,_,S) -> {reply,ok,S}.

        
handle_cast({on_service_reply,Msg},#state{action_interface= AI, callback_handler={M,Pid}}=S) -> 
        case AI:identify_msg(Msg) of
                send_goal_rp -> M:on_send_goal_reply(Pid,Msg);
                get_result_rp -> M:on_get_result_reply(Pid,Msg);
                cancel_goal_rp -> M:on_cancel_goal_reply(Pid,Msg);
                _ -> io:format("[ROS_ACTION_CLIENT]: BAD MSG RECEIVED FROM SERVICE\n")
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

h_cancel_goal(CancelGoalRequest,#state{ cancel_goal_client = CancelGoalClient}) ->
        ros_client:cast(CancelGoalClient, CancelGoalRequest).


s_code_to_str(?STATUS_UNKNOWN) -> "STATUS_UNKNOWN";
s_code_to_str(?STATUS_ACCEPTED)-> "STATUS_ACCEPTED";
s_code_to_str(?STATUS_EXECUTING)-> "STATUS_EXECUTING";
s_code_to_str(?STATUS_CANCELING)-> "STATUS_CANCELING";
s_code_to_str(?STATUS_SUCCEEDED)-> "STATUS_SUCCEEDED";
s_code_to_str(?STATUS_CANCELED)-> "STATUS_CANCELED";
s_code_to_str(?STATUS_ABORTED) -> "STATUS_ABORTED".


h_handle_status_update(GoalStatusArrayMsg, S) -> 
        io:format("[ROS_ACTION_CLIENT]: received goal states update: \n"),
        [ io:format("\t~p -> ~p\n",[UUID,s_code_to_str(N)]) || 
                #action_msgs_goal_status{goal_info=#action_msgs_goal_info{goal_id=#unique_identifier_msgs_u_u_i_d{uuid=UUID}},status=N} <- GoalStatusArrayMsg#action_msgs_goal_status_array.status_list],
        S.