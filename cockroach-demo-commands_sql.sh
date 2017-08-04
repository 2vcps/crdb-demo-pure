cockroach user set maxroach --insecure --host 10.21.84.10

cockroach sql --insecure --host 10.21.84.10 -e 'create database bank'
cockroach sql --insecure --host 10.21.84.10 -e 'CREATE TABLE IF NOT EXISTS bank.accounts (id INT PRIMARY KEY, balance INT)'
cockroach sql --insecure --host 10.21.84.10 -e 'GRANT ALL ON DATABASE bank TO maxroach'
cockroach sql --insecure --host 10.21.84.10 -e 'GRANT insert ON table bank.accounts TO maxroach'



docker service create --replicas 12 --name gogogo jowings/go_client:v2 go run /go/src/insert_rand.go
