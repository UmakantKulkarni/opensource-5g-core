#!/usr/bin/env bash

#Script written to install the pre-requisite resources that are needed

echo -e "Creating 5g-core namespace....\n"

echo

kubectl create ns 5g-core

echo -e "Creating the needed certificates....\n"

echo

cd ca-tls-certificates

kubectl -n 5g-core create secret generic mongodb-ca --from-file=rds-combined-ca-bundle.pem

echo

kubectl -n 5g-core get secret

echo "You can now proceed to install the Helm chart"