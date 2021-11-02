-module(gen_data_reader_listener).

-callback on_data_available(Listener :: term(),
                            {DataReader :: term(), ChangeKey :: term()}) ->
                               term().
