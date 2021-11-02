-module(gen_dds_entity_owner).

-callback get_all_dds_entities(ProcName::term()) -> { DataWriters::list(), DataReaders::list()}.
