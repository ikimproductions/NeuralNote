#!/usr/bin/env bash
# Pull the latest DamRsn/NeuralNote into this fork's main branch and push it.
#   scripts/sync-upstream.sh            # merge upstream/main into the current branch
#   scripts/sync-upstream.sh --rebuild  # ...then rebuild + reinstall NeuralNote+
set -euo pipefail
cd "$(dirname "$0")/.."

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/DamRsn/NeuralNote.git

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "error: commit or stash your changes first" >&2
    exit 1
fi

git fetch upstream
echo "Merging upstream/main into $(git branch --show-current)..."
if ! git merge --no-edit upstream/main; then
    cat >&2 <<'MSG'

Merge conflicts. The fork's own changes live in:
  CMakeLists.txt (product name / bundle id / plugin code / .mm sources)
  Lib/Utils/AudioUtils.{h,cpp}, NeuralNote/Source/MacFilePromiseDrop.{h,mm}
  NeuralNote/PluginSources/PluginEditor.{h,cpp}, Tests/audio_file_test.h
Resolve them, `git add` the files and `git commit`, then run this script again.
MSG
    exit 1
fi

git submodule update --init --recursive
git push origin HEAD
echo "Fork is in sync with upstream."

if [ "${1:-}" = "--rebuild" ]; then
    scripts/install.sh
fi
