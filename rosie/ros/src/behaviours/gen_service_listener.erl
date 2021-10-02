-module(gen_service_listener).

-callback on_client_request(Listener :: pid(), Msg :: term()) -> term().
