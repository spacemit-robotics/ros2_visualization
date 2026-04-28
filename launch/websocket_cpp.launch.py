# Copyright 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
#
# SPDX-License-Identifier: Apache-2.0

from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration


def generate_launch_description():
    return LaunchDescription([

        DeclareLaunchArgument(
            'image_topic',
            default_value='/result_img',
            description='Posted image topics'),

        DeclareLaunchArgument(
            'port',
            default_value='8080',
            description='port'),

        Node(
            package='visualization',
            executable='websocket_cpp_node',
            name='websocket_cpp_node',
            output='screen',
            parameters=[
                {'image_topic': LaunchConfiguration('image_topic')},
                {'port': LaunchConfiguration('port')}
                ]
        ),
    ])
