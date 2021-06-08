#!/usr/bin/env bash
numSubs="$1"
imsi=208930000000000
run_loop () {
  #cd /users/umakant/UERANSIM/build
  for i in $(seq 1 $numSubs);
  do
    imsi=$((imsi+1))
    nr-ue -c ../config/ue.yaml -i $imsi > /dev/null 2>&1 & 
    echo "Created subscriber #$i with imsi $imsi"
    sleep 0.1
  done
}

run_loop
