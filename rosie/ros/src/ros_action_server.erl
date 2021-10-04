-module(ros_action_server).

-export([start_link/3,publish_feedback/2,publish_result/3]).

-behaviour(gen_service_listener).
-export([on_client_request/2]).

-behaviour(gen_server).
-export([init/1,handle_call/3,handle_cast/2]).

-include_lib("dds/include/dds_types.hrl").
-include_lib("action_msgs/src/_rosie/cancel_goal_srv.hrl").

-record(state,{node,
        % module holding interface infos
        action_interface, 
        % ros services to serve this action
        request_goal_service,        
        cancel_goal_service,
        get_result_service,
        % ros publishers to topics for this action
        feed_publisher,        
        status_publisher,
        % user callbacks
        callback_handler,
        goals_accepted = [],
        goals_with_requested_results = [],
        cached_goal_results = []
}).

start_link(Node, Action, {CallbackModule,Pid}) -> 
        gen_server:start_link(?MODULE, #state{node = Node, 
                action_interface = Action,
                callback_handler = {CallbackModule,Pid}}, []).

publish_feedback(Name, Msg) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid, {publish_feedback, Msg}).

publish_result(Name, GoalID, Result) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid, {publish_result, GoalID, Result}).

on_client_request(Name, Request) ->
        [Pid|_] = pg:get_members(Name),
        gen_server:call(Pid, {on_client_request, Request}).

%callbacks
init(#state{node = Node, action_interface = Action,
                        callback_handler = CallbackHandler}=S) ->
        Name = {?MODULE,Action},
        pg:join(Name, self()),

        %customized by the user
        RequestGoalService = ros_node:create_service(Node, Action:get_goal_srv_module(), {?MODULE,Name}),        
        GetResultService = ros_node:create_service(Node, Action:get_result_srv_module(), {?MODULE,Name}),        
        FeedbackPub = ros_node:create_publisher(Node, Action:get_feedback_msg_module(), Action:get_action_name()++"/_action/feedback"),
        
        %standard but names must be specialized for this action instance
        CancelGoalService = ros_node:create_service(Node, {cancel_goal_srv, Action:get_action_name()++"/_action/"}, {?MODULE,Name}),
        % status topic cannot be left with volatile durability
        StatusTopicsProfile = #qos_profile{durability = ?TRANSIENT_LOCAL_DURABILITY_QOS},
        StatusPub = ros_node:create_publisher(Node, goal_status_array_msg,  Action:get_action_name()++"/_action/status",StatusTopicsProfile),

        {ok,S#state{
        request_goal_service = RequestGoalService,        
        cancel_goal_service = CancelGoalService,
        get_result_service = GetResultService,
        % ros subscription to remote topics for this action
        feed_publisher = FeedbackPub,        
        status_publisher = StatusPub
        }}.

handle_call({publish_feedback,Feed}, _, #state{action_interface= AI, feed_publisher=FeedbackPub}=S) -> 
        ros_publisher:publish(FeedbackPub,Feed),
        {reply,ok,S};
handle_call({publish_result, GoalID, Result}, _, #state{action_interface = AI, 
        goals_with_requested_results = GRR, 
        get_result_service = GetResultService,
        cached_goal_results = Cached}=S) -> 
        case [ {ClientID,RN} || {ClientID,RN,ID,_} <- GRR, ID == GoalID] of
                [] -> {reply,ok,S#state{cached_goal_results= [Result|Cached]}};
                RRL -> [ ros_service:send_response(GetResultService, { ClientID, RN, Result}) || {ClientID,RN} <- RRL],
                        {reply,ok,discard_goal_with_id(GoalID,S)}
        end;
handle_call({on_client_request,{{ClientId,RequestNumber},Msg}}, _, #state{action_interface= AI, callback_handler={M,Pid}}=S) -> 
        case AI:identify_msg(Msg) of
                send_goal_rq -> h_manage_goal_request(Msg,S);
                get_result_rq ->  h_manage_result_request(ClientId,RequestNumber,Msg,S);
                cancel_goal_rq -> M:on_cancel_goal_request(Pid,Msg), {reply,ok,S};
                _ -> io:format("[ROS_ACTION_SERVER]: BAD MSG RECEIVED FROM CLIENT\n"), {reply,ok,S}
        end.

        
handle_cast(_,S) -> {noreply,S}.

h_manage_goal_request(Msg,#state{action_interface= AI, callback_handler={M,Pid}, goals_accepted=GA}=S) -> 
        Reply = M:on_new_goal_request(Pid,Msg),
        case AI:get_responce_code(Reply) of
                0 -> {reply,Reply,S};
                1 -> M:on_execute_goal(Pid,Msg), {reply,Reply,S#state{goals_accepted=[{AI:get_goal_id(Msg), put_time_here} | GA]}}
        end.
discard_goal_with_id(OLD_ID,#state{action_interface=AI,
                                goals_accepted=GA,
                                goals_with_requested_results=GRQ,
                                cached_goal_results = CachedResults}=S) ->
        S#state{goals_accepted=[ A || {ID,_}=A <- GA, ID /= OLD_ID],
                goals_with_requested_results=[ A || {_,ID,_}=A <- GRQ, ID /= OLD_ID],
                cached_goal_results = [ R || R <- CachedResults, AI:get_goal_id(R) /= OLD_ID]}.

h_manage_result_request(ClientID, RequestNumber, Msg, #state{action_interface= AI, 
                callback_handler={M,Pid}, 
                goals_accepted=GA,
                goals_with_requested_results=GRQ,
                cached_goal_results = CachedResults}=S) ->
        case [ ID || {ID,_} <- GA, ID == AI:get_goal_id(Msg)] of
                [] -> io:format("[ROS_ACTION_SERVER]: result requested but goal not found.\n"), {reply,ros_service_noreply,S};
                [ID|_] -> case [ R || R <- CachedResults, ID == AI:get_goal_id(Msg)] of
                                [] -> {reply, ros_service_noreply, S#state{goals_with_requested_results=[{ClientID, RequestNumber, AI:get_goal_id(Msg), put_time_here} | GRQ]}};
                                [R|_] -> {reply, R, discard_goal_with_id(AI:get_goal_id(R),S)}
                        end
        end.