-ifndef(RTPS_CONSTANTS_HRL).

-define(RTPS_CONSTANTS_HRL, true).
% RTPS custom impl
-define(RTPS, "RTPS").
-define(V_MAJOR, 2).
-define(V_MINOR, 4).
-define(VendorId_0, 16#01).
-define(VendorId_1, 16#99).
%  Default Values
-define(GUIDPREFIX_UNKNOWN, << 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 , 0 >>).
-define(ENTITYID_UNKNOWN, #entityId{ key = << 0 , 0 , 0 >> , kind = 0 }).
-define(GUID_UNKNOWN,
        #guId{ prefix = ?GUIDPREFIX_UNKNOWN , entityId = ?ENTITYID_UNKNOWN }).
-define(TIME_ZERO, #time{ seconds = 16#00000000 , fraction = 16#00000000 }).
-define(TIME_INVALID, #time{ seconds = 16#ffffffff , fraction = 16#ffffffff }).
-define(TIME_INFINITE, #time{ seconds = 16#ffffffff , fraction = 16#fffffffe }).
% Locator Kinds
-define(LOCATOR_KIND_INVALID, - 1).
-define(LOCATOR_KIND_RESERVED, 0).
-define(LOCATOR_KIND_UDPv4, 1).
-define(LOCATOR_KIND_UDPv6, 2).
-define(LOCATOR_PORT_INVALID, 0).
-define(LOCATOR_ADDRESS_INVALID, ?LOCATOR_PORT_INVALID).
% Built-in Entity Kinds
-define(EKIND_BUILTIN_unknown, 16#c0).
-define(EKIND_BUILTIN_Participant, 16#c1).
-define(EKIND_BUILTIN_Writer_WITH_Key, 16#c2).
-define(EKIND_BUILTIN_Writer_NO_Key, 16#c3).
-define(EKIND_BUILTIN_Reader_NO_Key, 16#c4).
-define(EKIND_BUILTIN_Reader_WITH_Key, 16#c7).
-define(EKIND_BUILTIN_Writer_Group, 16#c8).
-define(EKIND_BUILTIN_Reader_Group, 16#c9).
% User Entity Kinds
-define(EKIND_USER_unknown, 16#00 , 16#00).
-define(EKIND_USER_Writer_WITH_Key, 16#02).
-define(EKIND_USER_Writer_NO_Key, 16#03).
-define(EKIND_USER_Reader_NO_Key, 16#04).
-define(EKIND_USER_Reader_WITH_Key, 16#07).
-define(EKIND_USER_Writer_Group, 16#08).
-define(EKIND_USER_Reader_Group, 16#09).
% Predefined Entity IDS
-define(ENTITYID_PARTICIPANT, #entityId{ key = << 00 , 00 , 01 >> , kind = 16#c1 }).
-define(ENTITYID_SEDP_BUILTIN_TOPICS_ANNOUNCER,
        #entityId{ key = << 00 , 00 , 02 >> , kind = 16#c2 }).
-define(ENTITYID_SEDP_BUILTIN_TOPICS_DETECTOR,
        #entityId{ key = << 00 , 00 , 02 >> , kind = 16#c7 }).
-define(ENTITYID_SEDP_BUILTIN_PUBLICATIONS_ANNOUNCER,
        #entityId{ key = << 00 , 00 , 03 >> , kind = 16#c2 }).
-define(ENTITYID_SEDP_BUILTIN_PUBLICATIONS_DETECTOR,
        #entityId{ key = << 00 , 00 , 03 >> , kind = 16#c7 }).
-define(ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_ANNOUNCER,
        #entityId{ key = << 00 , 00 , 04 >> , kind = 16#c2 }).
-define(ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_DETECTOR,
        #entityId{ key = << 00 , 00 , 04 >> , kind = 16#c7 }).
-define(ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER,
        #entityId{ key = << 00 , 01 , 00 >> , kind = 16#c2 }).
-define(ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER,
        #entityId{ key = << 00 , 01 , 00 >> , kind = 16#c7 }).
-define(ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER,
        #entityId{ key = << 00 , 02 , 00 >> , kind = 16#c2 }).
-define(ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_READER,
        #entityId{ key = << 00 , 02 , 00 >> , kind = 16#c7 }).
% Built-in Endpoints BIT_MASKS
-define(DISC_BUILTIN_ENDPOINT_PARTICIPANT_ANNOUNCER, 1).
-define(DISC_BUILTIN_ENDPOINT_PARTICIPANT_DETECTOR, ( 1 bsl 1 )).
-define(DISC_BUILTIN_ENDPOINT_PUBLICATIONS_ANNOUNCER, ( 1 bsl 2 )).
-define(DISC_BUILTIN_ENDPOINT_PUBLICATIONS_DETECTOR, ( 1 bsl 3 )).
-define(DISC_BUILTIN_ENDPOINT_SUBSCRIPTIONS_ANNOUNCER, ( 1 bsl 4 )).
-define(DISC_BUILTIN_ENDPOINT_SUBSCRIPTIONS_DETECTOR, ( 1 bsl 5 )).
% The following have been deprecated in version 2.4 of the
% specification. These bits should not be used by versions of the
% protocol equal to or newer than the deprecated version unless
% they are used with the same meaning as in versions prior to the
% deprecated version.
% @position(6) DISC_BUILTIN_ENDPOINT_PARTICIPANT_PROXY_ANNOUNCER,
% @position(7) DISC_BUILTIN_ENDPOINT_PARTICIPANT_PROXY_DETECTOR,
% @position(8) DISC_BUILTIN_ENDPOINT_PARTICIPANT_STATE_ANNOUNCER,
% @position(9) DISC_BUILTIN_ENDPOINT_PARTICIPANT_STATE_DETECTOR,
-define(BUILTIN_ENDPOINT_PARTICIPANT_MESSAGE_DATA_WRITER, ( 1 bsl 10 )).
-define(BUILTIN_ENDPOINT_PARTICIPANT_MESSAGE_DATA_READER, ( 1 bsl 11 )).
% Bits 12-15 have been reserved by the DDS-Xtypes 1.2 Specification and future revisions thereof.
% Bits 16-27 have been reserved by the DDS-Security 1.1 Specification and future revisions thereof.
-define(DISC_BUILTIN_ENDPOINT_TOPICS_ANNOUNCER, ( 1 bsl 28 )).
-define(DISC_BUILTIN_ENDPOINT_TOPICS_DETECTOR, ( 1 bsl 29 )).
% Parameter Ids for built-in Entities
-define(PID_PAD, 16#0000).   % N/A
-define(PID_SENTINEL, 16#0001).   % N/A
-define(PID_USER_DATA, 16#002c).   % UserDataQosPolicy
-define(PID_TOPIC_NAME, 16#0005).   % string<256>
-define(PID_TYPE_NAME, 16#0007).   % string<256>
-define(PID_GROUP_DATA, 16#002d).   % GroupDataQosPolicy
-define(PID_TOPIC_DATA, 16#002e).   % TopicDataQosPolicy
-define(PID_DURABILITY, 16#001d).   % DurabilityQosPolicy
-define(PID_DURABILITY_SERVICE, 16#001e).   % DurabilityServiceQosPolicy
-define(PID_DEADLINE, 16#0023).   % DeadlineQosPolicy
-define(PID_LATENCY_BUDGET, 16#0027).   % LatencyBudgetQosPolicy
-define(PID_LIVELINESS, 16#001b).   % LivelinessQosPolicy
-define(PID_RELIABILITY, 16#001a).   % ReliabilityQosPolicy3
-define(PID_LIFESPAN, 16#002b).   % LifespanQosPolicy
-define(PID_DESTINATION_ORDER, 16#0025).   % DestinationOrderQosPolicy
-define(PID_CONTENT_FILTER_INFO, 16#0055). % ContentFilterInfo_t
-define(PID_COHERENT_SET, 16#0056). % SequenceNumber_t
-define(PID_DIRECTED_WRITE, 16#0057). % GUID_t4
-define(PID_ORIGINAL_WRITER_INFO, 16#0061). % OriginalWriterInfo_t
-define(PID_GROUP_COHERENT_SET, 16#0063). % SequenceNumber_t
-define(PID_GROUP_SEQ_NUM, 16#0064). % SequenceNumber_t
-define(PID_WRITER_GROUP_INFO, 16#0065). % WriterGroupInfo_t
-define(PID_SECURE_WRITER_GROUP_INFO, 16#0066). % WriterGroupInfo_t
-define(PID_KEY_HASH, 16#0070). % KeyHash_t
-define(PID_STATUS_INFO, 16#0071). % StatusInfo_t
-define(PID_HISTORY, 16#0040).   % HistoryQosPolicy
-define(PID_RESOURCE_LIMITS, 16#0041).   % ResourceLimitsQosPolicy
-define(PID_OWNERSHIP, 16#001f).   % OwnershipQosPolicy
-define(PID_OWNERSHIP_STRENGTH, 16#0006).   % OwnershipStrengthQosPolicy
-define(PID_PRESENTATION, 16#0021).   % PresentationQosPolicy
-define(PID_PARTITION, 16#0029).   % PartitionQosPolicy
-define(PID_TIME_BASED_FILTER, 16#0004).   % TimeBasedFilterQosPolicy
-define(PID_TRANSPORT_PRIORITY, 16#0049).   % TransportPriorityQoSPolicy
-define(PID_DOMAIN_ID, 16#000f).   % DomainId_t
-define(PID_DOMAIN_TAG, 16#4014).   % string<256>
-define(PID_PROTOCOL_VERSION, 16#0015).   % ProtocolVersion_t
-define(PID_VENDOR_ID, 16#0016).   % VendorId_t
-define(PID_UNICAST_LOCATOR, 16#002f).   % Locator_t
-define(PID_MULTICAST_LOCATOR, 16#0030).   % Locator_t
-define(PID_DEFAULT_UNICAST_LOCATOR, 16#0031). % Locator_t
-define(PID_DEFAULT_MULTICAST_LOCATOR, 16#0048). % Locator_t
-define(PID_METATRAFFIC_UNICAST_LOCATOR, 16#0032). % Locator_t
-define(PID_METATRAFFIC_MULTICAST_LOCATOR, 16#0033). % Locator_t
-define(PID_EXPECTS_INLINE_QOS, 16#0043). % boolean
-define(PID_PARTICIPANT_MANUAL_LIVELINESS_COUNT, 16#0034). % Count_t
-define(PID_PARTICIPANT_LEASE_DURATION, 16#0002). % Duration_t
-define(PID_CONTENT_FILTER_PROPERTY, 16#0035). % ContentFilterProperty_t
-define(PID_PARTICIPANT_GUID, 16#0050). % GUID_t
-define(PID_GROUP_GUID, 16#0052). % GUID_t
-define(PID_BUILTIN_ENDPOINT_SET, 16#0058). % BuiltinEndpointSet_t
-define(PID_BUILTIN_ENDPOINT_QOS, 16#0077). % BuiltinEndpointQos_t
-define(PID_PROPERTY_LIST, 16#0059). % sequence<Property_t>
-define(PID_TYPE_MAX_SIZE_SERIALIZED, 16#0060). % long
-define(PID_ENTITY_NAME, 16#0062). % EntityName_t
-define(PID_ENDPOINT_GUID, 16#005a). % GUID_t
% Macros for built-in discovery protocols (SPDP & SEDP)
-define(PB, 7400).
-define(DG, 250).
-define(PG, 2).
-define(D0, 0).
-define(D1, 10).
-define(D2, 1).
-define(D3, 11).

-define( SPDP_WELL_KNOWN_MULTICAST_PORT( DomainId ) , ?PB + ?DG * DomainId + ?D0 ) .
-define( SPDP_WELL_KNOWN_UNICAST_PORT( DomainId , ParticipantId ) , ?PB + ?DG * DomainId + ?D1 + ?PG * ParticipantId ) .
-define(DEFAULT_MULTICAST_IP, { 239 , 255 , 0 , 1 }).

-define( DEFAULT_MULTICAST_LOCATOR( DomainID ) , #locator{ kind = ?LOCATOR_KIND_UDPv4 , ip = ?DEFAULT_MULTICAST_IP , port = ?PB + ?D0 + ( ?DG * DomainID ) } ) .
                                                    % DomainId should be 0 for iteroperability

-define(ANY_IPV4_LOCATOR,
        #locator{ kind = ?LOCATOR_KIND_UDPv4 , ip = { 0 , 0 , 0 , 0 } , port = 0 }).
% Message Kinds
-define(SUB_MSG_KIND_PAD, 01). % Pad */
-define(SUB_MSG_KIND_ACKNACK, 06). % AckNack */
-define(SUB_MSG_KIND_HEARTBEAT, 07). % Heartbeat */
-define(SUB_MSG_KIND_GAP, 08). % Gap */
-define(SUB_MSG_KIND_INFO_TS, 09). % InfoTimestamp */
-define(SUB_MSG_KIND_INFO_SRC, 16#0c). % InfoSource */
-define(SUB_MSG_KIND_INFO_REPLY_IP4, 16#0d). % InfoReplyIp4 */
-define(SUB_MSG_KIND_INFO_DST, 16#0e). % InfoDestination */
-define(SUB_MSG_KIND_INFO_REPLY, 16#0f). % InfoReply */
-define(SUB_MSG_KIND_NACK_FRAG, 16#12). % NackFrag */
-define(SUB_MSG_KIND_HEARTBEAT_FRAG, 16#13). % HeartbeatFrag */
-define(SUB_MSG_KIND_DATA, 16#15). % Data */
-define(SUB_MSG_KIND_DATA_FRAG, 16#16). % DataFrag */
-define(PARTICIPANT_MESSAGE_DATA_KIND_UNKNOWN, << 00 , 00 , 00 , 00 >>).
-define(PARTICIPANT_MESSAGE_DATA_KIND_AUTOMATIC_LIVELINESS_UPDATE,
        << 00 , 00 , 00 , 01 >>).
-define(PARTICIPANT_MESSAGE_DATA_KIND_MANUAL_LIVELINESS_UPDATE, << 00 , 00 , 00 , 02 >>).
% Serialized data rappresentations
-define(CDR_BE, << 16#00 : 8 , 16#00 : 8 >>).
-define(CDR_LE, << 16#00 : 8 , 16#01 : 8 >>).
-define(PL_CDR_BE, << 16#00 : 8 , 16#02 : 8 >>).
-define(PL_CDR_LE, << 16#00 : 8 , 16#03 : 8 >>).
-define(CDR2_BE, << 16#00 : 8 , 16#10 : 8 >>).
-define(CDR2_LE, << 16#00 : 8 , 16#11 : 8 >>).
-define(PL_CDR2_BE, << 16#00 : 8 , 16#12 : 8 >>).
-define(PL_CDR2_LE, << 16#00 : 8 , 16#13 : 8 >>).
-define(D_CDR_BE, << 16#00 : 8 , 16#14 : 8 >>).
-define(D_CDR_LE, << 16#00 : 8 , 16#15 : 8 >>).
-define(XML, << 16#00 : 8 , 16#04 : 8 >>).

% TOPIC kinds

-define(NO_KEY, 0).
-define(WITH_KEY, 1).
% Endpoints PID_STATUS_INFO BIT-MASKS
-define(STATUS_INFO_UNREGISTERED, ( 1 bsl 0 )).
-define(STATUS_INFO_DISPOSED, ( 1 bsl 1 )).

-define( ENDPOINT_LEAVING( S ) , S == ( ?STATUS_INFO_UNREGISTERED bor ?STATUS_INFO_DISPOSED ) ) .
-endif.
