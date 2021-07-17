-ifndef(RMW_DDS_MSG_HRL).
-define(RMW_DDS_MSG_HRL, true).

% ROS2
-define(ros_discovery_info_topic_name, "ros_discovery_info").
-define(ros_discovery_info_topic_type, "rmw_dds_common::msg::dds_::ParticipantEntitiesInfo_").

-define(msg_string_topic_type, "std_msgs::msg::dds_::String_").

-record(gid,{data = <<0:24/binary>>}).

-record(node_entities_info,{
        node_namespace = <<0:256/binary>>,
        node_name = <<0:256/binary>>,
        reader_gid_seq = [],
        writer_gid_seq = []
}).


-record(participant_entities_info,{
        gid = #gid{},        
        node_entities_info_seq = []
}).

% GEOMETRY
-define(msg_twist_topic_type, "geometry_msgs::msg::dds_::Twist_").

-record(vector3,{x=0,y=0,z=0}).

-record(twist,{
        linear = #vector3{},        
        angular = #vector3{}
}).

-endif.

% all sts_msg types of ros are listed below
% Bool
% Byte
% ByteMultiArray
% Char
% ColorRGBA
% Duration
% Empty
% Float32
% Float32MultiArray
% Float64
% Float64MultiArray
% Header
% Int16
% Int16MultiArray
% Int32
% Int32MultiArray
% Int64
% Int64MultiArray
% Int8
% Int8MultiArray
% MultiArrayDimension
% MultiArrayLayout
% String
% Time
% UInt16
% UInt16MultiArray
% UInt32
% UInt32MultiArray
% UInt64
% UInt64MultiArray
% UInt8
% UInt8MultiArray