-module(gen_action_server_listener).


-callback on_new_goal_request(Listener :: pid(), Msg :: term()) -> term().

-callback on_execute_goal(Listener :: pid(), Goal :: term()) -> term().

-callback on_cancel_goal_request(Listener :: pid(), Goal :: term()) -> term().