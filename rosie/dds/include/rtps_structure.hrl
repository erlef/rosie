-ifndef(RTPS_STRUCT_HRL).

-define(RTPS_STRUCT_HRL, true).

% RTPS types
-record(guidPrefix, {hostId, appId, instanceId}).
-record(entityId, {key, kind}).
-record(version, {major, minor}).
-record(guId, {prefix, entityId = #entityId{}}).
-record(cacheChange,
        {kind, writerGuid, instanceHandle, sequenceNumber, inlineQoS = [], data}).
-record(parameter, {id, length, value}).
-record(time, {seconds, fraction}). % // franction is: sec/2^32
-record(locator, {kind, ip, port}).
-record(reader_locator,
        {
         locator = #locator{},
         requested_changes = [],
         unsent_changes = [],
         expectsInlineQos = false}).
-record(change_for_reader, {change_key, status, is_relevant = true}).

% status can be:
% UNSENT, UNACKNOWLEDGED, REQUESTED, ACKNOWLEDGED, UNDERWAY

-record(change_from_writer, {change_key, status=unknown, is_relevant = true}).

% status can be:
% LOST, MISSING, RECEIVED, UNKNOWN

-record(gap,
        {writerGUID = #guId{},
         readerGUID = #guId{},
         sn_set}).
-record(acknack,
        {writerGUID = #guId{}, 
        readerGUID = #guId{}, 
        final_flag, 
        sn_range, 
        count}).
-record(heartbeat,
        {writerGUID = #guId{},
         min_sn,
         max_sn,
         final_flag = not_set,
         readerGUID = #guId{},
         count}).
-record(reader_proxy,
        {guid,
         ready= false,
         expectsInlineQos = false,
         unicastLocatorList = [],
         multicastLocatorList = [],
         changes_for_reader = []}).
-record(writer_proxy,
        {guid,
         unicastLocatorList = [],
         multicastLocatorList = [],
         changes_from_writer = []}).        %remoteGroupEntityId = #entityId{}
-record(subMessageHeader, {kind, length, flags}).
-record(messageReceiver,
        {sourceVersion,
         sourceVendorId,
         sourceGuidPrefix = #guidPrefix{},
         destGuidPrefix = #guidPrefix{},
         unicastReplyLocatorList = [],
         multicastReplyLocatorList = [],
         haveTimestamp,
         timestamp}).
%-RTPS Entityes
-record(participant,
        {domainId,
         guid = #guId{},
         protocolVersion,
         vendorId,
         defaultUnicastLocatorList = [],
         defaultMulticastLocatorList = []}).
-record(endPoint,
        {guid = #guId{},
         reliabilityLevel = reliable,
         topicKind = 1, % NO_KEY
         unicastLocatorList = [],
         multicastLocatorList = []}).
%% BUILT-IN entities by RTPS
-record(spdp_builtinParticipantReader,
        {unicastLocatorList = [], multicastLocatorList = [], reliabilityLevel, topicKind}).
-record(spdp_builtinParticipantWriter,
        {unicastLocatorList = [],
         multicastLocatorList = [],
         reliabilityLevel,
         topicKind,
         resendPeriod,
         readerLocators = []}).
-record(spdp_disc_part_data,
        {domainId,
         domainTag,
         protocolVersion,
         guidPrefix,
         vendorId,
         expectsInlineQos = false,
         default_uni_locator_l = [], % at least 1
         default_multi_locator_l = [],
         meta_uni_locator_l = [],
         meta_multi_locator_l = [],
         manualLivelinessCount,
         availableBuiltinEndpoints, % bitmask
         builtinEndpointQos = false, % for best_effort data-reader
         key,
         user_data,
         leaseDuration,
         status_qos = 0}).
-record(sedp_disc_endpoint_data,
        {dst_reader_id = #entityId{},
         endpointGuid = #guId{},
         topic_type,
         topic_name,
         protocolVersion,
         vendorId,
         durability_qos = 0, % volatile
         reliability_qos = 2, % reliable as default
         history_qos = {0, 1}, % keep_last depth 1
         status_qos = 0}).
-record(sedp_endpoint_state, {guid, status_flags}).
-record(spdp_participant_state, {guid, status_flags}).

-endif.
