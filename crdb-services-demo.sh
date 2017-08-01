docker service create \
--replicas 1 \
--name cockroach_db1 \
--hostname cockroach_db1 \
--network cockroachdb \
--mount type=volume,source=cockroachdb-1,target=/cockroach/cockroach-data,volume-driver=pure \
--stop-grace-period 60s \
--publish 8888:8080 \
cockroachdb/cockroach:v1.0.2 start \
--logtostderr \
--insecure

docker service create \
--replicas 1 \
--name cockroach_db2 \
--hostname cockroach_db2 \
--network cockroachdb \
--mount type=volume,source=cockroachdb-2,target=/cockroach/cockroach-data,volume-driver=pure \
--stop-grace-period 60s \
cockroachdb/cockroach:v1.0.2 start \
--join=cockroach_db1:26257 \
--logtostderr \
--insecure

docker service create \
--replicas 1 \
--name cockroach_db3 \
--hostname cockroach_db3 \
--network cockroachdb \
--mount type=volume,source=cockroachdb-3,target=/cockroach/cockroach-data,volume-driver=pure \
--stop-grace-period 60s \
cockroachdb/cockroach:v1.0.2 start \
--join=cockroach_db1:26257 \
--logtostderr \
--insecure


docker service create \
--replicas 1 \
--name crdb-proxy \
--hostname crdb-proxy \
--network cockroachdb \
--publish 26257:26257 \
jowings/crdb-proxy:v1
