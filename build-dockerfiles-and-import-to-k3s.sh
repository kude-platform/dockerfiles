#!/bin/bash

sudo k3s ctr image list -q | grep registry.local | xargs sudo k3s ctr image del

for dir in ./evaluation/*/
do
    dir=${dir%*/}
    name=${dir##*/}
    version=$(cat "${dir}"/version.txt)

    fqi="registry.local/${name}:${version}"
    echo "Building ${fqi}"

    docker build -t "${fqi}" "${dir}"

    if command -v k3s &> /dev/null
    then
      docker save "${fqi}" | k3s ctr images import -
    else
      echo "k3s not found, skipping image import of ${fqi}"
    fi
done