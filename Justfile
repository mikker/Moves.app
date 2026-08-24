set dotenv-load := true

default := "build"

build:
	xcodebuild -scheme Moves -configuration Debug build

run:
	#!/usr/bin/env bash
	set -euo pipefail
	settings=$(xcodebuild -scheme Moves -configuration Debug -showBuildSettings)
	target_build_dir=$(awk -F ' = ' '/ TARGET_BUILD_DIR = / { print $2; exit }' <<< "$settings")
	executable_path=$(awk -F ' = ' '/ EXECUTABLE_PATH = / { print $2; exit }' <<< "$settings")
	bundle_identifier=$(awk -F ' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }' <<< "$settings")
	xcodebuild -scheme Moves -configuration Debug build
	pkill -x "Moves Dev" 2>/dev/null || true
	"$target_build_dir/$executable_path" &
	app_pid=$!
	/usr/bin/log stream --style compact --predicate "processIdentifier == $app_pid AND subsystem == '$bundle_identifier'" &
	log_pid=$!
	cleanup() {
		trap - EXIT INT TERM
		kill "$app_pid" "$log_pid" 2>/dev/null || true
		wait "$app_pid" "$log_pid" 2>/dev/null || true
	}
	trap cleanup EXIT INT TERM
	wait "$app_pid"

archive:
	bash -lc 'set -euo pipefail; rm -rf build/Moves.xcarchive; xcodebuild -scheme Moves -configuration Release archive -destination "generic/platform=macOS" -archivePath build/Moves.xcarchive ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO'

release VERSION="":
	bash -lc 'set -euo pipefail; scripts/release-package.sh "{{VERSION}}"'

distribute VERSION="":
	bash -lc 'set -euo pipefail; scripts/distribute-release.sh "{{VERSION}}"'
