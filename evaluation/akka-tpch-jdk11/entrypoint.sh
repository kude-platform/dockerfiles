#!/bin/sh
#current directory in the container is /tmp/app

if [ -z "$JOB_COMPLETION_INDEX" ]; then
  echo "JOB_COMPLETION_INDEX is not set"
  exit 1
fi

if [ -z "$JOB_NAME" ]; then
  echo "JOB_NAME is not set"
  exit 1
fi

if [ -z "$SVC_NAME" ]; then
  echo "SVC_NAME is not set"
  exit 1
fi

if [ -z "$GIT_URL" ]; then
  echo "GIT_URL is not set"
  exit 1
fi

git clone "$GIT_URL" ./source
unzip -o ./data/TPCH.zip -d ./source/data

cd ./source

mvn -o install

cp ./target/app.jar ./app.jar


if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  java -jar ./app.jar master -h "$JOB_NAME-0.$SVC_NAME"
else
  java -jar ./app.jar worker -mh "$JOB_NAME-0.$SVC_NAME" -h "$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME"
fi