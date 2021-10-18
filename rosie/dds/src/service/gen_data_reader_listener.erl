-module(gen_data_reader_listener).

-callback on_data_available(Listener :: pid(),
                            {DataReader :: pid(), ChangeKey :: term()}) ->
                               term().
