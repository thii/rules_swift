#!/bin/bash

# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eux

if [[ "${TRAVIS_OS_NAME}" == "osx" ]]; then
  OS=darwin
else
  OS=linux
fi

# ------------------------------------------------------------------------------
# Helper to use the github redirect to find the latest release.
function github_latest_release_tag() {
  local PROJECT=$1
  curl \
      -s \
      -o /dev/null \
      --write-out '%{redirect_url}' \
      "https://github.com/${PROJECT}/releases/latest" \
  | sed -e 's,https://.*/releases/tag/\(.*\),\1,'
}

# ------------------------------------------------------------------------------
# Helper to get a download url out of bazel build metadata file.
function url_from_bazel_manifest() {
  local MANIFEST_URL=$1
    if [[ "${OS}" == "darwin" ]]; then
      local JSON_OS="macos"
    else
      local JSON_OS="ubuntu1404"
    fi
  wget -O - "${MANIFEST_URL}" \
    | python -c "import json; import sys; print json.load(sys.stdin)['platforms']['${JSON_OS}']['url']"
}

# ------------------------------------------------------------------------------
# Helper to install bazel.
function install_bazel() {
  local VERSION="${1}"

  if [[ "${VERSION}" == "RELEASE" ]]; then
    VERSION="$(github_latest_release_tag bazelbuild/bazel)"
  fi

  # macOS and trusty images have jdk8, so install bazel without jdk.
  if [[ "${VERSION}" == "HEAD" ]]; then
    # bazelbuild/continuous-integration/issues/234 - they don't seem to have an installed
    # just raw binaries?
    mkdir -p "$HOME/bin"
    wget -O "$HOME/bin/bazel" \
      "$(url_from_bazel_manifest https://storage.googleapis.com/bazel-builds/metadata/latest.json)"
    chmod +x "$HOME/bin/bazel"
  else
    wget -O install.sh \
      "https://github.com/bazelbuild/bazel/releases/download/${VERSION}/bazel-${VERSION}-installer-${OS}-x86_64.sh"
    chmod +x install.sh
    ./install.sh --user
    rm -f install.sh
  fi

  bazel version
}

# ------------------------------------------------------------------------------
# Helper to install buildifier.
function install_buildifier() {
  local VERSION="${1}"

  if [[ "${VERSION}" == "RELEASE" ]]; then
    VERSION="$(github_latest_release_tag bazelbuild/buildtools)"
  fi

  if [[ "${VERSION}" == "HEAD" ]]; then
    echo "buildifier head is not supported"
    exit 1
  fi

  if [[ "${OS}" == "darwin" ]]; then
    URL="https://github.com/bazelbuild/buildtools/releases/download/${VERSION}/buildifier.osx"
  else
    URL="https://github.com/bazelbuild/buildtools/releases/download/${VERSION}/buildifier"
  fi

  mkdir -p "$HOME/bin"
  wget -O "${HOME}/bin/buildifier" "${URL}"
  chmod +x "${HOME}/bin/buildifier"
  buildifier --version
}

# ------------------------------------------------------------------------------
# Helper to install Swift.
function install_swift() {
  local VERSION="${1}"

  mkdir .swift
  curl -sL "https://swift.org/builds/swift-$VERSION-release/ubuntu1404/swift-$VERSION-RELEASE/swift-$VERSION-RELEASE-ubuntu14.04.tar.gz" | \
      tar xz -C .swift &> /dev/null

  # TODO(bazelbuild/bazel#6834): This is a workaround for an apparent issue with
  # the C++ toolchain configuration. The repository rule runs
  # `clang -fuse-ld=gold` in a repository rule context to determine if gold is
  # supported as the linker, which (I believe) can find `ld.gold` on the system
  # path. It also passes the path to Clang's bin directory as a program prefix
  # directory (`-B`), but if `ld.gold` doesn't live in this directory, then when
  # `clang` is invoked in a build action context, it won't have access to
  # `PATH`, so the subsequent link action fails.
  #
  # There are two ways to fix this: pass `--action_env=PATH` to Bazel or symlink
  # `ld.gold` where Clang can find it within Bazel's sandbox. We choose the
  # latter because it doesn't leak the system path into every action.
  which ld.gold && \
    sudo ln -s "$(which ld.gold)" /usr/local/clang-5.0.0/bin/ld.gold
}

# ------------------------------------------------------------------------------
# Install what is requested.
[[ -z "${BAZEL:-}" ]] || install_bazel "${BAZEL}"
[[ -z "${BUILDIFIER:-}" ]] || install_buildifier "${BUILDIFIER}"
[[ -z "${SWIFT_VERSION:-}" ]] || install_swift "${SWIFT_VERSION}"
