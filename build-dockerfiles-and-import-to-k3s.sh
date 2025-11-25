#!/bin/bash

for dir in ./images/*/
do
    dir=${dir%*/}
    name=${dir##*/}
    version=$(cat "${dir}"/version.txt)

    fqi="registry.local/${name}:${version}"
    echo "Building ${fqi}"

    if k3s ctr image list -q | grep -q "${fqi}"
    then
      echo "Image ${fqi} already exists, skipping"
      continue
    fi

    sudo k3s ctr image list -q | grep registry.local/${name} | xargs sudo k3s ctr image del

    docker build --no-cache -t "${fqi}" "${dir}"
    #docker build -t "${fqi}" "${dir}"

    if command -v k3s &> /dev/null
    then
      docker save "${fqi}" | k3s ctr images import -
    else
      echo "k3s not found, skipping image import of ${fqi}"
    fi
done

# sudo docker image prune -a -f
