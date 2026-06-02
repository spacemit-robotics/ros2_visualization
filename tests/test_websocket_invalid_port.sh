#!/usr/bin/env bash
#
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
#

set -euo pipefail

module_dir="${SROBOTIS_ROOT:-$(pwd)}/middleware/ros2/tools/visualization"
artifact_dir="${SROBOTIS_TEST_ARTIFACT_DIR:-/tmp/visualization-websocket-port-in-use}"
log_dir="${artifact_dir}/logs"
log_file="${log_dir}/websocket_port_in_use.log"
launch_log_file="${log_dir}/websocket_port_in_use.launch.log"
ros_log_dir="${artifact_dir}/ros_logs"
occupied_port="18081"
error_pattern="(Address already in use|bind.*failed|bind:|Server error.*address|端口.*占用)"

mkdir -p "${log_dir}" "${ros_log_dir}"
: >"${log_file}"
: >"${launch_log_file}"

trap 'set +e
if [[ -n "${launch_pid:-}" ]]; then
  kill -- "-${launch_pid}" >/dev/null 2>&1 || kill "${launch_pid}" >/dev/null 2>&1 || true
  wait "${launch_pid}" >/dev/null 2>&1 || true
fi
if [[ -n "${occupier_pid:-}" ]]; then
  kill "${occupier_pid}" >/dev/null 2>&1 || true
  wait "${occupier_pid}" >/dev/null 2>&1 || true
fi' EXIT

log() {
  echo "[websocket-port-in-use] $*" | tee -a "${log_file}"
}

run_logged() {
  log "\$ $*"
  "$@" >>"${log_file}" 2>&1
}

apt_package_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

install_apt_packages() {
  local -a missing_packages=()
  local package

  for package in "$@"; do
    if ! apt_package_installed "${package}"; then
      missing_packages+=("${package}")
    fi
  done

  if [[ ${#missing_packages[@]} -eq 0 ]]; then
    return
  fi

  log "Installing apt packages: ${missing_packages[*]}"
  export DEBIAN_FRONTEND=noninteractive
  run_logged apt-get update
  run_logged apt-get install -y "${missing_packages[@]}"
}

source_ros_setup() {
  set +u
  if [[ -f "${SROBOTIS_OUTPUT_STAGING:-}/setup.bash" ]]; then
    # shellcheck disable=SC1091
    source "${SROBOTIS_OUTPUT_STAGING}/setup.bash"
  elif [[ -f "${SROBOTIS_ROOT:-$(pwd)}/install/setup.bash" ]]; then
    # shellcheck disable=SC1091
    source "${SROBOTIS_ROOT:-$(pwd)}/install/setup.bash"
  elif [[ -f "/opt/ros/humble/setup.bash" ]]; then
    # shellcheck disable=SC1091
    source "/opt/ros/humble/setup.bash"
  fi
  set -u
}

ensure_visualization_package() {
  if ros2 pkg prefix visualization >>"${log_file}" 2>&1; then
    return
  fi

  if ! command -v colcon >/dev/null 2>&1; then
    log "ERROR: visualization package is not available and colcon command not found"
    exit 1
  fi

  local ws_dir="${artifact_dir}/visualization_ws"
  rm -rf "${ws_dir}"
  mkdir -p "${ws_dir}/src"
  cp -a "${module_dir}" "${ws_dir}/src/visualization"

  log "Building visualization package in temporary workspace"
  run_logged colcon --log-base "${ws_dir}/log" build \
    --base-paths "${ws_dir}/src/visualization" \
    --build-base "${ws_dir}/build" \
    --install-base "${ws_dir}/install" \
    --packages-select visualization \
    --cmake-args -DBUILD_TESTING=OFF

  set +u
  # shellcheck disable=SC1091
  source "${ws_dir}/install/setup.bash"
  set -u
  ros2 pkg prefix visualization >>"${log_file}" 2>&1
}

install_apt_packages \
  ros-humble-ros-base \
  ros-humble-sensor-msgs \
  libopencv-dev \
  libboost-thread-dev

source_ros_setup

export ROS_LOG_DIR="${ros_log_dir}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-59}"
export PYTHONUNBUFFERED=1

if ! command -v ros2 >/dev/null 2>&1; then
  log "ERROR: ros2 command not found"
  exit 1
fi

ensure_visualization_package

python3 - <<'PY' &
import socket
import time

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", 18081))
sock.listen(1)
try:
    while True:
        time.sleep(1)
finally:
    sock.close()
PY
occupier_pid=$!
sleep 1

log "Verifying launch reports bind error for occupied port=${occupied_port}"
setsid ros2 launch visualization websocket_cpp.launch.py \
  image_topic:=/visualization_ci/image/compressed \
  port:="${occupied_port}" \
  >>"${launch_log_file}" 2>&1 &
launch_pid=$!

deadline=$((SECONDS + 20))
while [[ ${SECONDS} -lt ${deadline} ]]; do
  if grep -Eqi "${error_pattern}" "${launch_log_file}"; then
    cat "${launch_log_file}" >>"${log_file}"
    log "Observed expected occupied port bind error."
    log "VISUALIZATION WEBSOCKET PORT IN USE TEST PASSED."
    exit 0
  fi

  if ! kill -0 "${launch_pid}" >/dev/null 2>&1; then
    if wait "${launch_pid}"; then
      log "ERROR: launch unexpectedly exited cleanly for occupied port"
      tee -a "${log_file}" <"${launch_log_file}" >&2
      exit 1
    fi

    cat "${launch_log_file}" >>"${log_file}"
    if grep -Eqi "${error_pattern}" "${launch_log_file}"; then
      log "Observed expected occupied port bind error."
      log "VISUALIZATION WEBSOCKET PORT IN USE TEST PASSED."
      exit 0
    fi
    break
  fi

  sleep 0.5
done

log "ERROR: did not observe the expected occupied port bind error within 20s"
tee -a "${log_file}" <"${launch_log_file}" >&2
exit 1
