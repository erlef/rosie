-ifndef(DDS_TYPES_HRL).

-define(DDS_TYPES_HRL, true).
-define(DDS_PUB_READER, dds_pub_reader).
-define(DDS_SUB_WRITER, dds_sub_writer).
%QOS
-define(BEST_EFFORT_RELIABILITY_QOS, 1).
-define(RELIABLE_RELIABILITY_QOS, 2).
-define(VOLATILE_DURABILITY_QOS, 0).
-define(TRANSIENT_LOCAL_DURABILITY_QOS, 1).
-define(TRANSIENT_DURABILITY_QOS, 2).
-define(PERSISTENT_DURABILITY_QOS, 3).
-define(KEEP_LAST_HISTORY_QOS, 0).
-define(KEEP_ALL_HISTORY_QOS, 1).

-record(qos_profile,
        {durability = ?VOLATILE_DURABILITY_QOS,
         reliability = ?RELIABLE_RELIABILITY_QOS,
         history = {?KEEP_LAST_HISTORY_QOS, 1}}).
-record(dds_user_topic, {type_name, name, qos_profile = #qos_profile{}}).

-endif.
