-module(gen_subscription_listener).

-callback on_topic_msg(Listener :: pid(), Msg :: term()) -> term().
