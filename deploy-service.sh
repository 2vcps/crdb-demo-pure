#!/usr/bin/env bash
set -x

docker network create --driver overlay cockroachdb

# Start the bootstrap node
docker service create \
--replicas 1 \
--name cockroachdb-bootstrap \
--network cockroachdb \
--mount type=volume,source=cockroachdb-bootstrap,target=/cockroach/cockroach-data,volume-driver=pure \
--stop-grace-period 60s \
cockroachdb/cockroach:v1.0 start \
--advertise-host=cockroachdb-bootstrap \
--logtostderr \
--insecure

until [[ "$(docker inspect $(docker service ps -q cockroachdb-bootstrap | head -1) --format '{{ .Status.State }}')" == *"running"* ]]; do sleep 5; done

# Start the cluster, point it to the bootstrap node
docker service create \
--replicas 2 \
--name cockroachdb-cluster \
--hostname "{{.Task.Name}}" \
--network cockroachdb \
--endpoint-mode dnsrr \
--mount type=volume,source="cockroachdb-cluster-{{.Task.Slot}}",target=/cockroach/cockroach-data,volume-driver=pure \
--stop-grace-period 60s \
cockroachdb/cockroach:v1.0 start \
--join=cockroachdb-bootstrap:26257 \
--logtostderr \
--insecure

until [[ "$(docker inspect $(docker service ps cockroachdb-cluster | grep cockroachdb-cluster.1 | head -1 | awk '{print $1}') --format '{{ .Status.State }}')" == *"running"* ]]; do sleep 5; done

# Kill the bootstrap node, we don't want it creating new clusters if it restarts
docker service rm cockroachdb-bootstrap

# Join it back to the custer (they need it to add nodes), and point it at the
# cluster dns name.
docker service create \
--replicas 1 \
--name cockroachdb-bootstrap \
--network cockroachdb \
--mount type=volume,source=cockroachdb-bootstrap,target=/cockroach/cockroach-data,volume-driver=pure \
--stop-grace-period 60s \
cockroachdb/cockroach:v1.0 start \
--advertise-host=cockroachdb-bootstrap \
--join=cockroachdb-cluster.1:26257 \
--logtostderr \
--insecure
