-module(rtps_debug).
-export([param_list/1,data_flags/1]).

data_flags(<<_:3,N:1,K:1,D:1,Q:1,E:1>>) -> io:format("Flags were: N=~p,K=~p,D=~p,Q=~p,E=~p\n",[N,K,D,Q,E]).

param_list([]) -> ok;
param_list([{ID,Val}|L]) ->
        case ID of
                user_data-> Name = "USER_DATA";
                rtps_version -> Name = "PROTOCOL_VERSION";
                vendor_id -> Name = "VENDOR_ID";
                participant_lease -> Name = "PARTICIPANT_LEASE_DURATION";
                participant_guid -> Name = "PARTICIPANT_GUID";
                builtin_endpoint_set -> Name = "BUILTIN_ENDPOINT_SET";
                domain_id -> Name = "DOMAIN_ID";
                default_uni_locator -> Name = "DEFAULT_UNICAST_LOCATOR";
                default_multi_locator -> Name = "DEFAULT_MULTICAST_LOCATOR";
                meta_uni_locator -> Name = "METATRAFFIC_UNICAST_LOCATOR";
                meta_multi_locator -> Name = "METATRAFFIC_MULTICAST_LOCATOR";
                sentinel -> Name = "SENTINEL";
                unknown -> Name = "Unknown"    
        end, 
        io:format("Param: ~p = ~p\n",[Name,Val]),  param_list(L).