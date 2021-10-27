-module(gen_service_listener).

-callback on_client_request(Listener :: term(), Msg :: term()) -> term().
