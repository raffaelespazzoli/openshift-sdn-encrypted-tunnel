#!/usr/bin/env bash

set -o errexit
docker build -t quay.io/raffaelespazzoli/openshift-sdn-tunnel:latest .
docker push quay.io/raffaelespazzoli/openshift-sdn-tunnel:latest