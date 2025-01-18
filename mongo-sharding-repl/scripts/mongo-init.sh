#!/bin/bash

echo "Pull images and start containers.."
docker-compose -f ./mongo-sharding-repl.yaml up -d

sleep 5
echo "Init config server"
docker exec configSrv mongosh --quiet --eval "
rs.initiate(
  {
    _id : 'config_server',
    configsvr: true,
    members: [
      { _id : 0, host : 'configSrv:27017' }
    ]
  }
);
" >/dev/null 2>&1

sleep 3
echo "Init shard1 with replicas"
docker exec shard1-1 mongosh --quiet --eval "
rs.initiate({_id: 'shard1', members: [
{_id: 0, host: 'shard1-1:27017'},
{_id: 1, host: 'shard1-2:27017'},
{_id: 2, host: 'shard1-3:27017'}
]});
" >/dev/null 2>&1

echo "Init shard2 with replicas"
docker exec shard2-1 mongosh --quiet --eval "
rs.initiate({_id: 'shard2', members: [
{_id: 0, host: 'shard2-1:27017'},
{_id: 1, host: 'shard2-2:27017'},
{_id: 2, host: 'shard2-3:27017'}
]});
" >/dev/null 2>&1

sleep 5
echo "Init router"
docker exec mongos_router mongosh --quiet --eval "
sh.addShard('shard1/shard1-1:27017');
sh.addShard('shard2/shard2-1:27017');

sh.enableSharding('somedb');
sh.shardCollection('somedb.helloDoc', { 'name' : 'hashed' });
" >/dev/null 2>&1

echo "Add some data to DB"
sleep 5
docker exec mongos_router mongosh --quiet --eval "
for (var i = 0; i < 1000; i++) {
    db.getSiblingDB('somedb').helloDoc.insert({ age: i, name: 'ly' + i });
}
print('Total documents: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"

echo "Check data on each DB host"
docker exec shard1-1 mongosh  --quiet --eval "
print('Documents in shard1-1: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"
docker exec shard1-2 mongosh  --quiet --eval "
print('Documents in shard1-2: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"
docker exec shard1-3 mongosh  --quiet --eval "
print('Documents in shard1-3: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"
docker exec shard2-1 mongosh  --quiet --eval "
print('Documents in shard2-1: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"
docker exec shard2-2 mongosh  --quiet --eval "
print('Documents in shard2-2: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"
docker exec shard2-3 mongosh  --quiet --eval "
print('Documents in shard2-3: ' + db.getSiblingDB('somedb').helloDoc.countDocuments());
"