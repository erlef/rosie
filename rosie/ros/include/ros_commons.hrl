-ifndef(ROS_COMMONS).

-define(ROS_COMMONS, true).
-define(ROS_CONTEXT, ros_context).

-record(ros_parameter, {
        name,
        type,
        value
}).

-record(ros_node_options, {
        namespace = none,
        enable_rosout = true,
        start_parameter_services = true,
        parameter_overrides = none,
        allow_undeclared_parameters = false,
        automatically_declare_parameters_from_overrides = false
}).

-endif.
