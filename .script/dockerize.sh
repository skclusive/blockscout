#!/bin/bash

# shellcheck disable=SC2034
MSYS_NO_PATHCONV=1 docker build -t explorer.ui -f Dockerfile --progress=plain --build-arg GIT_COMMIT_SHA=$(git rev-parse --short HEAD) --build-arg GIT_TAG=$(git describe --tags --abbrev=0) --build-arg API_BASE_PATH='/explorer' ./