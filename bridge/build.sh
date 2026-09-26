#!/bin/zsh
# Builds AirpodStream.app: a tiny helper that streams AirPods motion as JSON lines.
# It must be an .app launched via `open`, because macOS only grants motion access to an
# app that declares NSMotionUsageDescription — Python and your terminal don't.
set -e
cd "$(dirname "$0")"
APP=AirpodStream.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
swiftc -O airpod-stream.swift -o $APP/Contents/MacOS/airpod-stream
cp Info.plist $APP/Contents/Info.plist
codesign -s - --force $APP
echo "built bridge/$APP"
