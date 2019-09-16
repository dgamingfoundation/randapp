#!/usr/bin/env bash

cur_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "testnet - run randapp testnet"
      echo " "
      echo "testnet [options]"
      echo " "
      echo "options:"
      echo "-h, --help                    show brief help"
      echo "-n, --node_count=n            specify node count"
      echo "--no_rebuild                  run without rebuilding docker images"
      echo "--kill                        stop and remove testnet containers"
      echo "--restart                     removes testnet and starts it without rebuild; equals --kill && --no_rebuild"
      echo "--ruin                        force stop containers 1 and 2 after 5 seconds running dkg"
      echo "--logs                        save current logs to local ./logs folder"
      echo "-l, --log n [r|d]             print log from container with number n in console
                                          r for randapp, d for dkglib logs"
      exit 0
      ;;
    -n|--node_count)
      shift
      if test $# -gt 0; then
        export n=$1
      else
        echo "no maximum_nodes specified"
        exit 1
      fi
      shift
      ;;
    --no_rebuild)
      NOREBUILD=true
      shift
      ;;
    --kill)
      mapfile -d ' ' -t nodeArray < nodeArray.txt
      # first try to stop and remove all containers at once, as it is faster
      # if an error occured - stop and remove them one by one
      (docker stop ${nodeArray[@]} \
      && docker rm ${nodeArray[@]}) \
      || \
      for ((i = 0;i < ${#nodeArray[@]}; i++));
      do
        docker stop ${nodeArray[$i]}
        docker rm ${nodeArray[$i]}
      done
      rm -rf $cur_path/node0_config
      rm $cur_path/nodeArray.txt
      rm -rf $cur_path/logs
      exit 0
      ;;
    --restart)
      $cur_path/$0 --kill
      $cur_path/$0 --no_rebuild
      exit 0
      ;;
    --logs)
      rm -rf $cur_path/logs
      mkdir -p $cur_path/logs
      mapfile -d ' ' -t nodeArray < nodeArray.txt
      for ((i = 0;i < ${#nodeArray[@]}; i++));
      do
        docker exec ${nodeArray[$i]} /bin/bash -c "cat /root/rd_start.log" > $cur_path/logs/rd_start_node${i}.log
        docker exec ${nodeArray[$i]} /bin/bash -c "cat /root/dkglib.log" > $cur_path/logs/dkglib_node${i}.log
      done
      exit 0
      shift
      ;;
    -l|--log)
      shift
      if test $# -gt 1; then
        mapfile -d ' ' -t nodeArray < nodeArray.txt
        ln=$1
        if [[ $ln > $((${#nodeArray[@]}-1)) ]]
        then
          echo "wrong container number"
          exit 1
        fi
        shift
        lt=$1
        case $lt in
          r|randapp)
            docker exec ${nodeArray[$ln]} /bin/bash -c "cat /root/rd_start.log"
            ;;
          d|dkglib)
            docker exec ${nodeArray[$ln]} /bin/bash -c "cat /root/dkglib.log"
            ;;
        esac
      else
        echo "no log target specified"
        exit 1
      fi
      exit 0
      ;;

    --ruin)
      FORCERUIN=true
      shift
      ;;
    *)
      echo "wrong argument:"
      echo "$1"
      exit 0
      ;;
  esac
done

if [[ -z $n ]]
then
      n=4
fi

echo "node_count: $n"

sleep 3

cd $cur_path
rm -rf ./vendor

rm -rf ./node0_config
mkdir ./node0_config

gopath=$(whereis go | grep -oP '(?<=go: )(\S*)(?= .*)' -m 1)
PATH=$gopath:$gopath/bin:$PATH

echo $GOBIN

if [[ $NOREBUILD ]]
then
  echo "no rebuild"
  echo
else
  make prepare
  GO111MODULE=off

  cd $cur_path/../dkglib
  ./testnet.sh
  cd $cur_path
  docker build -t randapp_testnet .
fi

RAPATH=/go/src/github.com/dgamingfoundation/randapp

echo "run node0"

node0_full_id=$(docker run -d randapp_testnet /bin/bash -c "$RAPATH/scripts/init_chain_full.sh $n;
 sed -i 's/timeout_commit = \"5s\"/timeout_commit = \"1s\"/' /root/.rd/config/config.toml;
 rd start &> /root/rd_start.log")
node0_id=${node0_full_id:0:12}

echo "node0: $node0_id"
echo

while  ! docker exec $node0_id /bin/bash -c "[[ -d /root/.rd ]]" ; do
sleep 2
echo "waiting ..."
done

sleep 10

docker cp $node0_id:/root/.rd ./node0_config/.rd
docker cp $node0_id:/root/.rcli ./node0_config/.rcli

chmod -R 0777 ./node0_config

node0_addr=$(cat ./node0_config/.rd/config/genesis.json | jq '.app_state.genutil.gentxs[0].value.memo')

echo node0_addr
echo $node0_addr

if [[ -z $node0_addr ]] || [[ $node0_addr == "null" ]] || [[ $node0_addr == null ]]
then
  echo "ERROR"
  exit 1
fi

sed -i "s/seeds = \"\"/seeds = $node0_addr/" ./node0_config/.rd/config/config.toml
sed -i "s/persistent_peers = \"\"/persistent_peers = $node0_addr/" ./node0_config/.rd/config/config.toml

nodeArray=($node0_id)

for ((i=1;i<$n;i++));
do
    nodeN_full_id=$(docker create -t randapp_testnet /bin/bash -c "$RAPATH/scripts/init_chain.sh $i > /root/inch.log && rd start &> /root/rd_start.log")
    nodeN_id=${nodeN_full_id:0:12}

    nodeArray+=($nodeN_id)

    docker cp ./node0_config/.rd/config/config.toml $nodeN_id:/root/tmp/
    docker cp ./node0_config/.rd/config/genesis.json $nodeN_id:/root/tmp/
    docker cp ./node0_config/.rcli $nodeN_id:/root/tmp/.rcli

    docker start $nodeN_id

    echo "node_num: $i, node_id: $nodeN_id"

done

sleep 5

echo "${nodeArray[@]}" > nodeArray.txt

chmod 0777 ./nodeArray.txt

echo "${nodeArray[@]}"
echo
echo "all nodes started"
echo "run run_clients"
echo

sleep 8

for ((i=0;i<${#nodeArray[@]};i++));
do
  nodeN_id=${nodeArray[$i]}
  docker exec -d $nodeN_id /bin/bash -c "dkglib -num=$i &> /root/dkglib.log" &
  echo "node_num: $i, node_id: $nodeN_id"
done

if [[ $FORCERUIN ]]
then
  sleep 5
  docker stop ${nodeArray[1]}
  docker stop ${nodeArray[2]}
fi