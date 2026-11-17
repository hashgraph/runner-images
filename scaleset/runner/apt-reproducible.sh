#!/usr/bin/env bash
##
# Copyright (C) 2026 Hedera Hashgraph, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##

# Reproducible apt helper for the Debian/Ubuntu runner images (bind-mounted into RUN steps, never shipped).
#
#   apt-reproducible.sh pin    Point every apt source (archive, security, and Launchpad PPAs) at a fixed
#                              point-in-time snapshot so every build of the same commit resolves identical packages.
#   apt-reproducible.sh clean  Remove apt/dpkg indexes, caches, logs, and backup files that embed build-time state.
#   apt-reproducible.sh unpin  Restore the original (live) apt sources saved by 'pin', so workflows running on the
#                              finished image install current packages rather than the build-time snapshot.
#
# The snapshot is APT_SNAPSHOT (YYYYMMDDTHHMMSSZ) when set, otherwise the start of the UTC day before
# SOURCE_DATE_EPOCH. The one-day margin guarantees the snapshot services have finished importing that point in time,
# so a later rebuild can never see a newer archive state for the same snapshot ID.

set -euo pipefail

# Pristine copies of every source file 'pin' rewrites, restored by 'unpin'.
BACKUP_DIR=/var/lib/apt-reproducible/sources

snapshot_id() {
  if [[ -n "${APT_SNAPSHOT:-}" ]]; then
    echo "${APT_SNAPSHOT}"
  elif [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
    date -u -d "@$((SOURCE_DATE_EPOCH - 86400))" +%Y%m%dT000000Z
  else
    echo "error: set the SOURCE_DATE_EPOCH or APT_SNAPSHOT build arg (see .claude/build-commands.md)" >&2
    return 1
  fi
}

source_files() {
  shopt -s nullglob
  local f
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f "${f}" ]] && echo "${f}"
  done
  return 0
}

pin() {
  local id f unpinned
  id="$(snapshot_id)"
  if [[ ! "${id}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
    echo "error: invalid apt snapshot id '${id}' (expected YYYYMMDDTHHMMSSZ)" >&2
    return 1
  fi

  while read -r f; do
    # Keep the first (live) version of each file; files added later, such as a PPA, are saved on the next pin.
    if [[ ! -e "${BACKUP_DIR}${f}" ]]; then
      mkdir -p "$(dirname "${BACKUP_DIR}${f}")"
      cp -p "${f}" "${BACKUP_DIR}${f}"
    fi
    sed -i -E \
      -e "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#https://snapshot.ubuntu.com/ubuntu/${id}/#g" \
      -e "s#https?://ppa\.launchpad(content)?\.net/([^/[:space:]]+)/([^/[:space:]]+)/ubuntu/?#https://snapshot.ppa.launchpadcontent.net/\2/\3/ubuntu/${id}/#g" \
      -e "s#https?://deb\.debian\.org/(debian-security|debian)/?#https://snapshot.debian.org/archive/\1/${id}/#g" \
      "${f}"
  done < <(source_files)

  # Fail closed: any active source left on a live mirror would make the build non-reproducible.
  unpinned="$(source_files | xargs -r grep -hvE '^[[:space:]]*(#|$)' |
    grep -oE 'https?://[^[:space:]]+' |
    grep -vE '^https://snapshot\.(ubuntu\.com|debian\.org|ppa\.launchpadcontent\.net)/' || true)"
  if [[ -n "${unpinned}" ]]; then
    echo "error: apt sources not pinned to a snapshot:" >&2
    echo "${unpinned}" >&2
    return 1
  fi

  # Snapshot Release files keep their original Valid-Until; the pinned snapshot ID, not the clock, sets freshness.
  echo 'Acquire::Check-Valid-Until "false";' >/etc/apt/apt.conf.d/99snapshot
  echo "apt sources pinned to snapshot ${id}"
}

clean() {
  apt-get clean
  rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/cache/debconf/*-old /var/cache/ldconfig/aux-cache \
    /var/cache/man/* /var/lib/dpkg/*-old /var/log/apt/* /var/log/alternatives.log /var/log/dpkg.log \
    /root/.launchpadlib /var/lib/dbus/machine-id
  # Package scripts (dbus) generate a random machine ID. Images ship it empty so each container gets its own.
  if [[ -s /etc/machine-id ]]; then
    : >/etc/machine-id
  fi
}

unpin() {
  local saved
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    echo "error: no saved apt sources to restore; run 'pin' first" >&2
    return 1
  fi
  while IFS= read -r -d '' saved; do
    cp -p "${saved}" "${saved#"${BACKUP_DIR}"}"
  done < <(find "${BACKUP_DIR}" -type f -print0)
  rm -rf "$(dirname "${BACKUP_DIR}")" /etc/apt/apt.conf.d/99snapshot
  echo "apt sources restored to the live mirrors"
}

case "${1:-}" in
  pin) pin ;;
  clean) clean ;;
  unpin) unpin ;;
  *)
    echo "usage: $(basename "$0") pin|clean|unpin" >&2
    exit 2
    ;;
esac
