#!/bin/sh

for dir in ./evaluation/*/
do
    dir=${dir%*/}
    name=${dir##*/}
    version=$(cat ${dir}/version.txt)
    echo "Building ${name} in version ${version}"
    docker build -t ${name}:${version} ${dir}
done