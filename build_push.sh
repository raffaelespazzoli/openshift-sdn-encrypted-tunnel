#!/usr/bin/env bash

set -o errexit
docker build -t quay.io/raffaelespazzoli/openshift-sdn-tunnel:latest .
docker push quay.io/raffaelespazzoli/openshift-sdn-tunnel:latest
docker build -t quay.io/raffaelespazzoli/coredns:latest -f Dockerfile.coredns .
docker push quay.io/raffaelespazzoli/coredns:latest
