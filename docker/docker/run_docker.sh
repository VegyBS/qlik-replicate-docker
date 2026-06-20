#!/bin/bash
# Expect five parameters:
#    1. Rest port
#    2. Docker image
#    3. Replicate password
#    4. Replicate Data folder, optional (when empty, "/replicate/data" is used)
#    5. container name, optional (when empty, a random name is provided)
if [[ -z "$1" ]] || [[ -z "$2" ]] || [[ -z "$3" ]]
then
  echo "Usage: run_docker.sh <Rest port> <Docker image> <Replicate password> [<Replicate data folder>] [<Container name>]"
  exit 1
fi

if [[ -z "$4" ]] && [[ -z "$5" ]]
then
	docker run -d -e ReplicateRestPort=$1 -e ReplicateAdminPassword=$3 -p $1:$1 --expose $1 $2
elif [[ -z "$4" ]] && [[ ! -z "$5" ]]
then
	docker run --name $5 -d -e ReplicateRestPort=$1 -e ReplicateAdminPassword=$3 -p $1:$1 --expose $1 $2
elif [[ ! -z "$4" ]] && [[ -z "$5" ]]
then
	docker run -d -e ReplicateDataFolder="$4" -e ReplicateRestPort=$1 -e ReplicateAdminPassword=$3 -p $1:$1 --expose $1 $2
else
	docker run --name $5 -d -e ReplicateDataFolder="$4" -e ReplicateRestPort=$1 -e ReplicateAdminPassword=$3 -p $1:$1 --expose $1 $2
fi
