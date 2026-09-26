#!/bin/zsh
# Runs PuttCore tests. With only Command Line Tools installed (no Xcode), swift-testing
# isn't on the default search paths, so point at it explicitly.
set -e
cd "$(dirname "$0")/../PuttCore"
D=/Library/Developer/CommandLineTools/Library/Developer
if xcode-select -p | grep -q CommandLineTools; then
  swift test -Xswiftc -F -Xswiftc $D/Frameworks -Xlinker -rpath -Xlinker $D/Frameworks -Xlinker -rpath -Xlinker $D/usr/lib "$@"
else
  swift test "$@"
fi
