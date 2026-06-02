#!/usr/bin/env bash
#
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
#

set -euo pipefail

module_dir="${SROBOTIS_ROOT:-$(pwd)}/middleware/ros2/tools/visualization"
artifact_dir="${SROBOTIS_TEST_ARTIFACT_DIR:-/tmp/visualization-websocket-stream-functional}"
log_dir="${artifact_dir}/logs"
log_file="${log_dir}/websocket_stream_functional.log"
node_log_file="${log_dir}/websocket_stream_functional.node.log"
ros_log_dir="${artifact_dir}/ros_logs"
image_topic="/visualization_ci/image/compressed"
port="18080"

mkdir -p "${log_dir}" "${ros_log_dir}"
: >"${log_file}"
: >"${node_log_file}"

trap 'set +e
if [[ -n "${node_pid:-}" ]]; then
  kill -- "-${node_pid}" >/dev/null 2>&1 || kill "${node_pid}" >/dev/null 2>&1 || true
  wait "${node_pid}" >/dev/null 2>&1 || true
fi' EXIT

log() {
  echo "[websocket-stream-functional] $*" | tee -a "${log_file}"
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

wait_for_http_ok() {
  local deadline=$((SECONDS + 25))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if python3 - <<'PY'
import urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:18080/", timeout=1.0) as response:
        body = response.read().decode("utf-8", errors="replace")
        if response.status == 200 and "ws://" in body and "{{HOST_IP}}" not in body and "{{PORT}}" not in body:
            raise SystemExit(0)
except Exception:
    pass
raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

install_apt_packages \
  ros-humble-ros-base \
  ros-humble-sensor-msgs \
  libopencv-dev \
  libboost-thread-dev

source_ros_setup

export ROS_LOG_DIR="${ros_log_dir}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-58}"
export PYTHONUNBUFFERED=1

if ! command -v ros2 >/dev/null 2>&1; then
  log "ERROR: ros2 command not found"
  exit 1
fi

ensure_visualization_package

log "Starting visualization WebSocket node on port ${port}"
setsid ros2 launch visualization websocket_cpp.launch.py \
  image_topic:="${image_topic}" \
  port:="${port}" \
  >>"${node_log_file}" 2>&1 &
node_pid=$!

if ! wait_for_http_ok; then
  log "ERROR: HTTP index page did not become ready or placeholders were not substituted"
  tee -a "${log_file}" <"${node_log_file}" >&2
  exit 1
fi
log "HTTP index page is served and contains substituted WebSocket endpoint."

python3 - <<'PY' | tee -a "${log_file}"
import base64
import socket
import struct
import subprocess
import sys
import time
from urllib.parse import urlparse

expected_payload = b"visualization-ci-frame"
expected_base64 = base64.b64encode(expected_payload).decode("ascii")

handshake_key = base64.b64encode(b"visual-ci-key123").decode("ascii")
request = (
    "GET / HTTP/1.1\r\n"
    "Host: 127.0.0.1:18080\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {handshake_key}\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
).encode("ascii")

sock = socket.create_connection(("127.0.0.1", 18080), timeout=5.0)
sock.sendall(request)
response = sock.recv(4096)
if b"101 Switching Protocols" not in response:
    raise SystemExit(f"ERROR: WebSocket handshake failed: {response!r}")


def read_exact(sock, length):
    chunks = []
    remaining = length
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise RuntimeError(f"socket closed while reading {length} bytes")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)

publisher = subprocess.Popen(
    [
        "ros2", "topic", "pub", "--once",
        "/visualization_ci/image/compressed",
        "sensor_msgs/msg/CompressedImage",
        "{format: jpeg, data: [118, 105, 115, 117, 97, 108, 105, 122, 97, 116, 105, 111, 110, 45, 99, 105, 45, 102, 114, 97, 109, 101]}",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)

received = b""
deadline = time.time() + 15.0
try:
    while time.time() < deadline:
        sock.settimeout(max(0.1, deadline - time.time()))
        header = sock.recv(2)
        if not header:
            continue
        first, second = header
        opcode = first & 0x0F
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", read_exact(sock, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", read_exact(sock, 8))[0]
        payload = read_exact(sock, length)
        if opcode == 1:
            received = payload
            break
finally:
    sock.close()
    try:
        publisher.wait(timeout=10)
    except subprocess.TimeoutExpired:
        publisher.terminate()
        try:
            publisher.wait(timeout=3)
        except subprocess.TimeoutExpired:
            publisher.kill()
            publisher.wait(timeout=3)
        raise SystemExit("ERROR: ros2 topic pub did not exit within 10 seconds")

if publisher.returncode != 0:
    output = publisher.stdout.read() if publisher.stdout else ""
    raise SystemExit(f"ERROR: ros2 topic pub failed: {output}")

actual_base64 = received.decode("ascii", errors="replace")
if actual_base64 != expected_base64:
    raise SystemExit(
        "ERROR: WebSocket frame payload mismatch: "
        f"expected {expected_base64!r}, got {actual_base64!r}"
    )

print("Received expected base64-encoded CompressedImage payload over WebSocket.")
PY

log "VISUALIZATION WEBSOCKET STREAM FUNCTIONAL TEST PASSED."
