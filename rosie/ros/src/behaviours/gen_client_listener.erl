-module(gen_client_listener).

-callback on_service_reply(Listener :: pid(), Msg :: term()) -> term().
