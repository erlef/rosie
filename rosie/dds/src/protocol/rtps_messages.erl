-module(rtps_messages).

-export([header/1, build_message/2, serialize_sub_header/1, serialize_info_dst/1,
         serialize_info_timestamp/0, is_rtps_packet/1, parse_rtps_header/1, parse_submsg_header/1,
         parse_data/2, parse_heartbeat/2, parse_acknack/2, parse_gap/2, parse_param_list/1, serialize_data/2,
         serialize_heatbeat/1, serialize_acknack/1]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

%% produces an RTPS HEADER
header(GuidPrefix) ->
    <<?RTPS, ?V_MAJOR, ?V_MINOR, ?VendorId_0, ?VendorId_1, GuidPrefix/binary>>.

is_rtps_packet(<<?RTPS, _:16, _:16, _:(12 * 8), _/binary>>) ->
    true;
is_rtps_packet(_) ->
    false.

parse_rtps_header(<<?RTPS,
                    Version:16,
                    Vendor:16,
                    GuidPrefix:12/binary,
                    PayLoad/binary>>) ->
    {Version, Vendor, GuidPrefix, PayLoad}.

parse_submsg_header(<<Kind:8, Flags:8, Length:16/little, PayLoad/binary>>) ->
    {Kind, <<Flags>>, Length, PayLoad}.

% attach_binaries(<<B/binary>>) -> <<B/binary>>;
% attach_binaries([<<B/binary>>|TL]) -> attach_binaries(<<B/binary>>,TL).
% attach_binaries(Result , []) -> Result;
% attach_binaries(Result , [B|TL]) -> attach_binaries(<<Result/binary,B/binary>>).
build_message(GuidPrefix, SubMsg_List) ->
    H = header(GuidPrefix),
    Body = erlang:iolist_to_binary(SubMsg_List),
    <<H/binary, Body/binary>>.

serialize_sub_header(SubHeader) ->
    Kind = SubHeader#subMessageHeader.kind,
    Flags = SubHeader#subMessageHeader.flags,
    Length = SubHeader#subMessageHeader.length,
    <<Kind:8, Flags:8/bitstring, Length:16/little>>.

serialize_data_sub_msg(ReaderId, WriterId, WriterSN, Rappresentation_id, Data) ->
    <<0:16,%extra flags not used
      16:16/little,% OctetsToInlineQos
      (ReaderId#entityId.key):3/binary,
      (ReaderId#entityId.kind):8,
      (WriterId#entityId.key):3/binary,
      (WriterId#entityId.kind):8,
      0:32,% usually is all 0
      WriterSN:32/little-signed-integer,
      Rappresentation_id:2/binary,
      0:16,% options usually unused
      Data/binary>>.

serialize_data_sub_msg(ReaderId,
                       WriterId,
                       WriterSN,
                       Rappresentation_id,
                       Inline_QOS,
                       Data) ->
    <<0:16,%extra flags not used
      16:16/little,% OctetsToInlineQos
      (ReaderId#entityId.key):3/binary,
      (ReaderId#entityId.kind):8,
      (WriterId#entityId.key):3/binary,
      (WriterId#entityId.kind):8,
      0:32,% usually is all 0
      WriterSN:32/little-signed-integer,
      Inline_QOS/binary,
      Rappresentation_id:2/binary,
      0:16,% options usually unused
      Data/binary>>.

serialize_info_dst(GuidPrefix) ->
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_INFO_DST,
                                               length = 12,
                                               flags = <<0:6, 0:1, 1:1>>}),
    <<SubHead/binary, GuidPrefix:12/binary>>.

serialize_info_timestamp() ->
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_INFO_TS,
                                               length = 08,
                                               flags = <<0:6, 0:1, 1:1>>}),
    Seconds = erlang:system_time(second),
    NanoSeconds = erlang:system_time(nanosecond),
    <<SubHead/binary, Seconds:32/little, NanoSeconds:32/little>>.

%parameters serialization
serialize_param_list([], PL) ->
    PL;
serialize_param_list([{sentinel, _} | TL], PL) ->
    P = <<?PID_SENTINEL:16/little, 0:16/little>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{status_info, S} | TL], PL) ->
    P = <<?PID_STATUS_INFO:16/little, 4:16/little, S:32/big>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{domain_id, V} | TL], PL) ->
    P = <<?PID_DOMAIN_ID:16/little, 4:16/little, V:32>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{rtps_version, V} | TL], PL) ->
    P = <<?PID_PROTOCOL_VERSION:16/little, 4:16/little, V/binary, 0:16>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{vendor_id, V} | TL], PL) ->
    P = <<?PID_VENDOR_ID:16/little, 4:16/little, V/binary, 0:16>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{participant_lease, V} | TL], PL) ->
    P = <<?PID_PARTICIPANT_LEASE_DURATION:16/little, 8:16/little, V:32/little, 0:32>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{participant_guid, #guId{prefix = Prefix, entityId = ID}} | TL],
                     PL) ->
    Guid = <<Prefix/binary, (ID#entityId.key)/binary, (ID#entityId.kind):8>>,
    P = <<?PID_PARTICIPANT_GUID:16/little, 16:16/little, Guid/binary>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{builtin_endpoint_set, V} | TL], PL) ->
    P = <<?PID_BUILTIN_ENDPOINT_SET:16/little, 4:16/little, V:32/little>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{default_uni_locator,
                       #locator{kind = K,
                                port = Port,
                                ip = {IP_1, IP_2, IP_3, IP_4}}}
                      | TL],
                     PL) ->
    P = <<?PID_DEFAULT_UNICAST_LOCATOR:16/little,
          24:16/little,
          K:32/little-signed,
          Port:32/little,
          0:(8 * 12),
          IP_1:8,
          IP_2:8,
          IP_3:8,
          IP_4:8>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{default_multi_locator,
                       #locator{kind = K,
                                port = Port,
                                ip = {IP_1, IP_2, IP_3, IP_4}}}
                      | TL],
                     PL) ->
    P = <<?PID_DEFAULT_MULTICAST_LOCATOR:16/little,
          24:16/little,
          K:32/little-signed,
          Port:32/little,
          0:(8 * 12),
          IP_1:8,
          IP_2:8,
          IP_3:8,
          IP_4:8>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{meta_uni_locator,
                       #locator{kind = K,
                                port = Port,
                                ip = {IP_1, IP_2, IP_3, IP_4}}}
                      | TL],
                     PL) ->
    P = <<?PID_METATRAFFIC_UNICAST_LOCATOR:16/little,
          24:16/little,
          K:32/little-signed,
          Port:32/little,
          0:(8 * 12),
          IP_1:8,
          IP_2:8,
          IP_3:8,
          IP_4:8>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{meta_multi_locator,
                       #locator{kind = K,
                                port = Port,
                                ip = {IP_1, IP_2, IP_3, IP_4}}}
                      | TL],
                     PL) ->
    P = <<?PID_METATRAFFIC_MULTICAST_LOCATOR:16/little,
          24:16/little,
          K:32/little-signed,
          Port:32/little,
          0:(8 * 12),
          IP_1:8,
          IP_2:8,
          IP_3:8,
          IP_4:8>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{history_qos, {QOS, Depth}} | TL], PL) ->
    P = <<?PID_HISTORY:16/little, 8:16/little, QOS:32/little, Depth:32/little>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{durability_qos, V} | TL], PL) ->
    P = <<?PID_DURABILITY:16/little, 4:16/little, V:32/little>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{reliability_qos, V} | TL], PL) ->
    P = <<?PID_RELIABILITY:16/little, 12:16/little, V:32/little, 0:64>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{topic_name, V} | TL], PL) ->
    L = length(V),
    Pad = 4 - length(V) rem 4 + 4,
    P = <<?PID_TOPIC_NAME:16/little,
          (L + Pad):16/little,
          (L + 1):32/little,
          (list_to_binary(V))/binary,
          0:(Pad * 8)>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{topic_type, V} | TL], PL) ->
    L = length(V),
    Pad = 4 - length(V) rem 4 + 4,
    P = <<?PID_TYPE_NAME:16/little,
          (L + Pad):16/little,
          (L + 1):32/little,
          (list_to_binary(V))/binary,
          0:(Pad * 8)>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([{endpoint_guid, #guId{prefix = Prefix, entityId = ID}} | TL], PL) ->
    Guid = <<Prefix/binary, (ID#entityId.key)/binary, (ID#entityId.kind):8>>,
    P = <<?PID_ENDPOINT_GUID:16/little, 16:16/little, Guid/binary>>,
    serialize_param_list(TL, [P | PL]);
serialize_param_list([_ | TL], PL) ->
    serialize_param_list(TL, PL).

serialize_param_list(PL) ->
    serialize_param_list(PL, []).

key_to_param_payload(#spdp_participant_state{guid = GUID, status_flags = S}) ->
    QL = list_to_binary(serialize_param_list([{sentinel, none}, {status_info, S}])),
    PL = list_to_binary(serialize_param_list([{sentinel, none}, {participant_guid, GUID}])),
    {QL, PL};
key_to_param_payload(#sedp_endpoint_state{guid = GUID, status_flags = S}) ->
    QL = list_to_binary(serialize_param_list([{sentinel, none}, {status_info, S}])),
    PL = list_to_binary(serialize_param_list([{sentinel, none}, {endpoint_guid, GUID}])),
    {QL, PL}.

sedp_data_to_param_payload(#sedp_disc_endpoint_data{protocolVersion = P_VER,
                                                    vendorId = V_ID,
                                                    reliability_qos = R_QOS,
                                                    durability_qos = D_QOS,
                                                    topic_type = TT,
                                                    topic_name = TN,
                                                    endpointGuid = GUID,
                                                    history_qos = H_QOS}) ->
    list_to_binary(serialize_param_list([{sentinel, none},
                                         {endpoint_guid, GUID},
                                         {rtps_version, P_VER},
                                         {vendor_id, V_ID},
                                         {history_qos, H_QOS},
                                         {durability_qos, D_QOS},
                                         {reliability_qos, R_QOS},
                                         {topic_type, TT},
                                         {topic_name, TN}])).

spdp_data_to_param_payload(#spdp_disc_part_data{domainId = D_ID,
                                                protocolVersion = P_VER,
                                                guidPrefix = Prefix,
                                                vendorId = V_ID,
                                                expectsInlineQos = InlineQoS,
                                                default_uni_locator_l = D_UNI_L, % at least 1
                                                default_multi_locator_l = D_MULTI_L,
                                                meta_uni_locator_l = M_UNI_L,
                                                meta_multi_locator_l = M_MULTI_L,
                                                availableBuiltinEndpoints =
                                                    B_IN_MASK, % bitmask 4 byte
                                                builtinEndpointQos =
                                                    B_IN_END_QOS, % for best_effort data-reader
                                                key = Key,
                                                leaseDuration = LEASE}) ->
    list_to_binary(serialize_param_list([{sentinel, none},
                                         {domain_id, D_ID},
                                         {rtps_version, P_VER},
                                         {vendor_id, V_ID},
                                         {participant_guid,
                                          #guId{prefix = Prefix, entityId = ?ENTITYID_PARTICIPANT}},
                                         {builtin_endpoint_set, B_IN_MASK},
                                         {participant_lease, LEASE}]
                                        ++ [{default_uni_locator, L} || L <- D_UNI_L]
                                        ++ [{default_multi_locator, L} || L <- D_MULTI_L]
                                        ++ [{meta_uni_locator, L} || L <- M_UNI_L]
                                        ++ [{meta_multi_locator, L} || L <- M_MULTI_L])).

serialize_data(DST_READER_ID,
               #cacheChange{writerGuid = W,
                            sequenceNumber = SN,
                            data = #spdp_disc_part_data{} = D}) ->
    Payload = spdp_data_to_param_payload(D),
    Body = serialize_data_sub_msg(DST_READER_ID, W#guId.entityId, SN, ?PL_CDR_LE, Payload),
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_DATA,
                                               length = byte_size(Body),
                                               flags = <<0:5, 1:1, 0:1, 1:1>>}),
    <<SubHead/binary, Body/binary>>;
serialize_data(DST_READER_ID,
               #cacheChange{writerGuid = W,
                            sequenceNumber = SN,
                            data = #sedp_disc_endpoint_data{} = D}) ->
    Payload = sedp_data_to_param_payload(D),
    Body = serialize_data_sub_msg(DST_READER_ID, W#guId.entityId, SN, ?PL_CDR_LE, Payload),
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_DATA,
                                               length = byte_size(Body),
                                               flags = <<0:5, 1:1, 0:1, 1:1>>}),
    <<SubHead/binary, Body/binary>>;
serialize_data(DST_READER_ID,
               #cacheChange{writerGuid = W,
                            sequenceNumber = SN,
                            data = #sedp_endpoint_state{} = D}) ->
    {QL, PL} = key_to_param_payload(D),
    Body = serialize_data_sub_msg(DST_READER_ID, W#guId.entityId, SN, ?PL_CDR_LE, QL, PL),
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_DATA,
                                               length = byte_size(Body),
                                               flags =
                                                   <<0:4,
                                                     1:1,
                                                     0:1,
                                                     1:1,
                                                     1:1>>}), % key, no data and in-line QOS
    <<SubHead/binary, Body/binary>>;
serialize_data(DST_READER_ID,
               #cacheChange{writerGuid = W,
                            sequenceNumber = SN,
                            data = #spdp_participant_state{} = D}) ->
    {QL, PL} = key_to_param_payload(D),
    Body = serialize_data_sub_msg(DST_READER_ID, W#guId.entityId, SN, ?PL_CDR_LE, QL, PL),
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_DATA,
                                               length = byte_size(Body),
                                               flags =
                                                   <<0:4,
                                                     1:1,
                                                     0:1,
                                                     1:1,
                                                     1:1>>}), % key, no data and in-line QOS
    <<SubHead/binary, Body/binary>>;
serialize_data(DST_READER_ID,
               #cacheChange{writerGuid = W,
                            sequenceNumber = SN,
                            data = D}) ->
    Payload = D,
    Body = serialize_data_sub_msg(DST_READER_ID, W#guId.entityId, SN, ?CDR_LE, Payload),
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_DATA,
                                               length = byte_size(Body),
                                               flags = <<0:5, 1:1, 0:1, 1:1>>}),
    <<SubHead/binary, Body/binary>>.

serialize_heatbeat(#heartbeat{writerGUID = #guId{entityId = WID},
                              readerGUID = #guId{entityId = RID},
                              final_flag = FF,
                              min_sn = MinSN,
                              max_sn = MaxSN,
                              count = C}) ->
    Body =
        <<(RID#entityId.key):3/binary,
          (RID#entityId.kind):8,
          (WID#entityId.key):3/binary,
          (WID#entityId.kind):8,
          0:32/little,
          MinSN:32/little,
          0:32/little,
          MaxSN:32/little,
          C:32/little>>,
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_HEARTBEAT,
                                               length = byte_size(Body),
                                               flags = <<0:6, FF:1, 1:1>>}),
    %io:format("~p\n",[Body]),
    <<SubHead/binary, Body/binary>>.

serialize_acknack_body(#acknack{writerGUID =
                                    #guId{entityId = #entityId{key = WriterID, kind = WriterKind}},
                                readerGUID =
                                    #guId{entityId = #entityId{key = ReaderID, kind = ReaderKind}},
                                final_flag = Final,
                                sn_range = BitMapBase,
                                count = Count})
    when is_integer(BitMapBase) ->
    <<ReaderID:3/binary,
      ReaderKind:8,
      WriterID:3/binary,
      WriterKind:8,
      0:32,
      BitMapBase:32/little,
      0:32/little,
      Count:32/little>>;
serialize_acknack_body(#acknack{writerGUID =
                                    #guId{entityId = #entityId{key = WriterID, kind = WriterKind}},
                                readerGUID =
                                    #guId{entityId = #entityId{key = ReaderID, kind = ReaderKind}},
                                final_flag = Final,
                                sn_range = Range,
                                count = Count}) ->
    BitMapBase = lists:min(Range),
    NumBits = lists:max(Range) - BitMapBase + 1,
    <<ReaderID:3/binary,
      ReaderKind:8,
      WriterID:3/binary,
      WriterKind:8,
      0:32,
      BitMapBase:32/little,
      NumBits:32/little,
      (calc_bitmap(BitMapBase, NumBits, Range))/binary,
      Count:32/little>>.

bit_in_map(_, _, BitMap, []) ->
    BitMap;
bit_in_map(Base, BITMAP_LENGTH, BitMap, [N | TL]) ->
    <<Set:BITMAP_LENGTH/big>> = BitMap,
    Bit = gen_bitmask(Base, BITMAP_LENGTH, N),
    bit_in_map(Base, BITMAP_LENGTH, <<(Set bor Bit):BITMAP_LENGTH>>, TL).

gen_bitmask(Base, BITMAP_LENGTH, N) ->
    Bit_Index = N - Base,
    R_Shift = Bit_Index rem 8,
    L_Shift = Bit_Index rem 32 div 8 * 8,
    L_DWORD_shift = 32 * (BITMAP_LENGTH div 32 - Bit_Index div 32 - 1),
    Bit = 128 bsl L_DWORD_shift bsl L_Shift bsr R_Shift.

calc_bitmap(Base, NumBits, Range) ->
    BITMAP_LENGTH = 32 * ((NumBits-1) div 32 + 1),
    %io:format("~p\n",[Length]),
    Bits = <<0:BITMAP_LENGTH>>,
    bit_in_map(Base, BITMAP_LENGTH, Bits, Range).

serialize_acknack(#acknack{final_flag = FF} = A) ->
    Body = serialize_acknack_body(A),
    SubHead =
        serialize_sub_header(#subMessageHeader{kind = ?SUB_MSG_KIND_ACKNACK,
                                               length = byte_size(Body),
                                               flags = <<0:6, FF:1, 1:1>>}),
    <<SubHead/binary, Body/binary>>.

% DATA-SCANNING |X|X|X|N|K|D|Q|E|
% FLAGS are: N = non-standard, K = key serialized, D= data present, Q = in-line-QOS, E = little endian
% I expect little endian
% only data
%
debug_data_flags(<<_:3, N:1, K:1, D:1, Q:1, E:1>>) ->
    io:format("Flags were: N=~p,K=~p,D=~p,Q=~p,E=~p\n", [N, K, D, Q, E]).

get_inline_qos(Inline_QOS_plus_data, QOS_list) ->
    case parse_param(Inline_QOS_plus_data) of
        {?PID_SENTINEL, _, Rest} ->
            {QOS_list, Rest};
        {ID, Value, Next} ->
            get_inline_qos(Next, [param_to_record(ID, Value) | QOS_list])
    end.

get_inline_qos(Inline_QOS_plus_data) ->
    get_inline_qos(Inline_QOS_plus_data, []).

parse_data(<<_:3, 0:1, 0:1, 0:1, 1:1, 1:1>>,% expected flags: Just Inline-qos and little-endian
           <<_:16/bitstring,%extra flags not used
             _:16/little,% OctetsToInlineQos not used for now
             ReaderID:24,
             ReaderKind:8,
             WriterID:24,
             WriterKind:8,
             _:32,% usually is all 0
             WriterSN:32/little-signed-integer,
             Inline_QOS/binary>>) ->
    {QOS_list, _} = get_inline_qos(Inline_QOS),
    {QOS_list,
        #entityId{key = <<ReaderID:24>>, kind = ReaderKind},
        #entityId{key = <<WriterID:24>>, kind = WriterKind},
        WriterSN};
parse_data(<<_:3, 0:1, _:1, _:1, 0:1, 1:1>>,% expected flags: Data present or Serialized key, NO inline-qos and little-endian
           <<_:16/bitstring,%extra flags not used
             _:16/little,% OctetsToInlineQos not used for now
             ReaderID:24,
             ReaderKind:8,
             WriterID:24,
             WriterKind:8,
             _:32,% usually is all 0
             WriterSN:32/little-signed-integer,
             Rappresentation_id:16,
             _:16,% options usually unused
             SerializedPayload/binary>>) ->
    {#entityId{key = <<ReaderID:24>>, kind = ReaderKind},
     #entityId{key = <<WriterID:24>>, kind = WriterKind},
     WriterSN,
     <<Rappresentation_id:16>>,
     SerializedPayload};
parse_data(<<_:3, 0:1, _:1, _:1, 1:1, 1:1>>,% expected flags: Data present or Serialized key, Inline-Qos and little-endian
           <<_:16/bitstring,%extra flags not used
             16:16/little,% OctetsToInlineQos expected to be 16
             ReaderID:24,
             ReaderKind:8,
             WriterID:24,
             WriterKind:8,
             _:32,% usually is all 0
             WriterSN:32/little-signed-integer,
             Inline_QOS_plus_data/binary>>) ->
    {QOS_list, <<Rappresentation_id:16, _:16, SerializedPayload/binary>>} =
        get_inline_qos(Inline_QOS_plus_data),
    {QOS_list,
     #entityId{key = <<ReaderID:24>>, kind = ReaderKind},
     #entityId{key = <<WriterID:24>>, kind = WriterKind},
     WriterSN,
     <<Rappresentation_id:16>>,
     SerializedPayload};
parse_data(F, _) ->
    debug_data_flags(F),
    unsopported.

% parameter parsing to records
param_to_record(?PID_STATUS_INFO, <<V:32/big>>) ->
    {status_info, V};
param_to_record(?PID_USER_DATA, P) ->
    {user_data, P};
param_to_record(?PID_PROTOCOL_VERSION, <<P:16, _:16>>) ->
    {rtps_version, P};
param_to_record(?PID_VENDOR_ID, <<P:16, _:16>>) ->
    {vendor_id, P};
param_to_record(?PID_PARTICIPANT_LEASE_DURATION, <<Sec:32/little, _:32>>) ->
    {participant_lease, Sec};
param_to_record(?PID_PARTICIPANT_GUID, <<Prefix:12/binary, Key:3/binary, Kind:8>>) ->
    {participant_guid, #guId{prefix = Prefix, entityId = #entityId{key = Key, kind = Kind}}};
param_to_record(?PID_BUILTIN_ENDPOINT_SET, <<P:32/little-unsigned-integer>>) ->
    {builtin_endpoint_set, P};
param_to_record(?PID_DOMAIN_ID, P) ->
    {domain_id, P};
% I do not care of locators who are not IPv4
param_to_record(?PID_DEFAULT_UNICAST_LOCATOR,
                <<?LOCATOR_KIND_UDPv4:32/little, Port:32/little, _:12/binary, IP_1:8, IP_2:8, IP_3:8, IP_4:8>>) ->
    {default_uni_locator,
     #locator{kind = ?LOCATOR_KIND_UDPv4,
              port = Port,
              ip = {IP_1, IP_2, IP_3, IP_4}}};
param_to_record(?PID_DEFAULT_MULTICAST_LOCATOR,
                <<?LOCATOR_KIND_UDPv4:32/little, Port:32/little, _:12/binary, IP_1:8, IP_2:8, IP_3:8, IP_4:8>>) ->
    {default_multi_locator,
     #locator{kind = ?LOCATOR_KIND_UDPv4,
              port = Port,
              ip = {IP_1, IP_2, IP_3, IP_4}}};
param_to_record(?PID_METATRAFFIC_UNICAST_LOCATOR,
                <<?LOCATOR_KIND_UDPv4:32/little, Port:32/little, _:12/binary, IP_1:8, IP_2:8, IP_3:8, IP_4:8>>) ->
    {meta_uni_locator,
     #locator{kind = ?LOCATOR_KIND_UDPv4,
              port = Port,
              ip = {IP_1, IP_2, IP_3, IP_4}}};
param_to_record(?PID_METATRAFFIC_MULTICAST_LOCATOR,
                <<?LOCATOR_KIND_UDPv4:32/little, Port:32/little, _:12/binary, IP_1:8, IP_2:8, IP_3:8, IP_4:8>>) ->
    {meta_multi_locator,
     #locator{kind = ?LOCATOR_KIND_UDPv4,
              port = Port,
              ip = {IP_1, IP_2, IP_3, IP_4}}};
param_to_record(?PID_TOPIC_NAME, <<L:32/little, Name:(L - 1)/binary, _/binary>>) ->
    {topic_name, binary_to_list(Name)};
param_to_record(?PID_TYPE_NAME, <<L:32/little, Name:(L - 1)/binary, _/binary>>) ->
    {topic_type, binary_to_list(Name)};
param_to_record(?PID_ENDPOINT_GUID, <<Prefix:12/binary, Key:3/binary, Kind:8>>) ->
    {endpoint_guid, #guId{prefix = Prefix, entityId = #entityId{key = Key, kind = Kind}}};
param_to_record(?PID_DURABILITY, <<V:32/little>>) ->
    {durability_qos, V};
param_to_record(?PID_RELIABILITY, <<V:32/little, _:64>>) ->
    {reliability_qos, V};
param_to_record(?PID_HISTORY, <<QOS:32/little, Depth:32/little>>) ->
    {history_qos, {QOS, Depth}};
param_to_record(?PID_SENTINEL, P) ->
    {sentinel, none};
param_to_record(_, _) ->
    {unknown, none}.

% parameter parsing
parse_param(<<ID:16/little, Length:16/little, Payload/binary>>) ->
    <<Value:Length/binary, Next/binary>> = Payload,
    {ID, Value, Next}.

parse_param_list(<<>>, L) ->
    L;
parse_param_list(Payload, L) ->
    {ID, Value, Next} = parse_param(Payload),
    Entry = param_to_record(ID, Value),
    parse_param_list(Next, L ++ [Entry]).

parse_param_list(Payload) ->
    parse_param_list(Payload, []).

parse_acknack(<<_:6, Final:1, _:1>>,
              <<ReaderID:3/binary,
                ReaderKind:8,
                WriterID:3/binary,
                WriterKind:8,
                _:32,
                BitMapBase:32/little,
                0:32,
                Count:32/little>>) ->
    #acknack{writerGUID = #guId{entityId = #entityId{key = WriterID, kind = WriterKind}},
             readerGUID = #guId{entityId = #entityId{key = ReaderID, kind = ReaderKind}},
             final_flag = Final,
             sn_range = BitMapBase,
             count = Count};
parse_acknack(<<_:6, Final:1, _:1>>,
              <<ReaderID:3/binary,
                ReaderKind:8,
                WriterID:3/binary,
                WriterKind:8,
                _:32,
                BitMapBase:32/little,
                NumBits:32/little,
                BitMap_and_count/binary>>) when NumBits =< 256 ->
    BITMAP_LENGTH = 32 * (NumBits div 32 + 1),
    <<Set:BITMAP_LENGTH/big, Count:32/little>> = BitMap_and_count,
    #acknack{writerGUID = #guId{entityId = #entityId{key = WriterID, kind = WriterKind}},
             readerGUID = #guId{entityId = #entityId{key = ReaderID, kind = ReaderKind}},
             final_flag = Final,
             sn_range =
                 filter_by_bits(BitMapBase,
                                Set,
                                BITMAP_LENGTH,
                                lists:seq(BitMapBase, BitMapBase + NumBits)),
             count = Count}.

parse_gap(<<_:7, 1:1>>,
            <<ReaderID:3/binary,
                ReaderKind:8,
                WriterID:3/binary,
                WriterKind:8,                
                _:32,
                GapStart:32/little,
                _:32,
                BitMapBase:32/little,
                NumBits:32/little>>) when NumBits == 0 ->
    #gap{
        writerGUID = #guId{entityId = #entityId{key = WriterID, kind = WriterKind}},
        readerGUID = #guId{entityId = #entityId{key = ReaderID, kind = ReaderKind}},
        sn_set = lists:seq(GapStart, BitMapBase-1)
    };
parse_gap(<<_:7, 1:1>>,
            <<ReaderID:3/binary,
                ReaderKind:8,
                WriterID:3/binary,
                WriterKind:8,                
                _:32,
                GapStart:32/little,
                _:32,
                BitMapBase:32/little,
                NumBits:32/little,
                BitMap/binary>>) when NumBits =< 256 ->
    BITMAP_LENGTH = 32 * (NumBits div 32 + 1),
    <<NumSet:BITMAP_LENGTH/big>> = BitMap,
    #gap{
        writerGUID = #guId{entityId = #entityId{key = WriterID, kind = WriterKind}},
        readerGUID = #guId{entityId = #entityId{key = ReaderID, kind = ReaderKind}},
        sn_set = lists:seq(GapStart, BitMapBase-1) ++ filter_by_bits(BitMapBase, 
                                NumSet,
                                BITMAP_LENGTH,
                                lists:seq(BitMapBase, BitMapBase + NumBits))
    }.

filter_by_bits(Base, NumSet, BITMAP_LENGTH, List) ->
    [N || N <- List, 0 /= NumSet band gen_bitmask(Base, BITMAP_LENGTH, N)].

parse_heartbeat(<<_:6, Final:1, _:1>>,
                <<Reader_key:3/binary,
                  Reader_kind:8,
                  Writer_key:3/binary,
                  Writer_kind:8,
                  0:32/little,
                  MinSN:32/little,
                  0:32/little,
                  MaxSN:32/little,
                  C:32/little>>) ->
    #heartbeat{writerGUID = #guId{entityId = #entityId{key = Writer_key, kind = Writer_kind}},
               readerGUID = #guId{entityId = #entityId{key = Reader_key, kind = Reader_kind}},
               final_flag = Final,
               min_sn = MinSN,
               max_sn = MaxSN,
               count = C}.

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

gap_parsing_test() ->
    GAP = parse_gap(<<0:7, 1:1>>, <<0,0,4,199,0,0,4,194,0,0,0,0,10,0,0,0,0,0,0,0,12,0,0,0,8,0,0,0,0,0,0,105>>),
    io:format("~p\n",[GAP]),
    ?assertMatch(GAP, #gap{writerGUID = #guId{entityId = #entityId{key= <<0,0,4>>,kind= 194}},
                            readerGUID = #guId{entityId = #entityId{key= <<0,0,4>>,kind= 199}},
                            sn_set = [10,11,13,14,16,19]}).


heartbit_single_test() ->
    HB = #heartbeat{writerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                    min_sn = 1,
                    max_sn = 1,
                    final_flag = 0,
                    readerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                    count = 1},
    SubMsg = serialize_heatbeat(HB),
    {?SUB_MSG_KIND_HEARTBEAT, Flags, Length, Payload} = parse_submsg_header(SubMsg),
    <<Body:Length/binary, _/binary>> = Payload,
    HB_ = parse_heartbeat(Flags, Body),
    io:format("HB1 = ~p\n", [HB]),
    io:format("HB2 = ~p\n", [HB_]),
    ?assert(HB == HB_).

heartbit_range_test() ->
    HB = #heartbeat{writerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                    min_sn = 50,
                    max_sn = 299,
                    final_flag = 1,
                    readerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                    count = 2},
    SubMsg = serialize_heatbeat(HB),
    {?SUB_MSG_KIND_HEARTBEAT, Flags, Length, Payload} = parse_submsg_header(SubMsg),
    <<Body:Length/binary, _/binary>> = Payload,
    HB_ = parse_heartbeat(Flags, Body),
    io:format("HB1 = ~p\n", [HB]),
    io:format("HB2 = ~p\n", [HB_]),
    ?assert(HB == HB_).

acknack_expect_1_test() ->
    A = #acknack{writerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                 final_flag = 0,
                 readerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                 sn_range = 15,
                 count = 1},
    SubMsg = serialize_acknack(A),
    {?SUB_MSG_KIND_ACKNACK, Flags, Length, Payload} = parse_submsg_header(SubMsg),
    <<Body:Length/binary, _/binary>> = Payload,
    A_ = parse_acknack(Flags, Body),
    io:format("A1 = ~p\n", [A]),
    io:format("A2 = ~p\n", [A_]),
    ?assert(A == A_).

acknack_range_test() ->
    A = #acknack{writerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                 final_flag = 1,
                 readerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                 sn_range = [7, 8, 9, 44, 123, 181, 182, 183, 184, 185],
                 count = 1},
    SubMsg = serialize_acknack(A),
    {?SUB_MSG_KIND_ACKNACK, Flags, Length, Payload} = parse_submsg_header(SubMsg),
    <<Body:Length/binary, _/binary>> = Payload,
    A_ = parse_acknack(Flags, Body),
    io:format("A1 = ~p\n", [A]),
    io:format("A2 = ~p\n", [A_]),
    ?assert(A == A_).

acknack_serialize_32_test() ->
    A = #acknack{writerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                 final_flag = 1,
                 readerGUID = #guId{entityId = ?ENTITYID_UNKNOWN},
                 sn_range = lists:seq(1, 32),
                 count = 1},
    ?assertMatch( <<6,3,28,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,32,0,0,0,255,255,255,255,1,0,0,0>>, <<(serialize_acknack(A))/binary>>).

-endif.
