-module(gen_action_client_listener).

-callback on_send_goal_reply(Listener :: pid(), Msg :: term()) -> term().
-callback on_get_result_reply(Listener :: pid(), Msg :: term()) -> term().
-callback on_cancel_goal_reply(Listener :: pid(), Msg :: term()) -> term().
-callback on_feedback_message(Listener :: pid(), Msg :: term()) -> term().

-optional_callbacks([on_cancel_goal_reply/2,on_feedback_message/2]).
