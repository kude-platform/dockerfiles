#!/bin/bash

masterPort=7077

function publishEvents {
    if [ -z "$3" ]; then
        echo "Publishing event $1"
        curl -X POST -H "Content-Type: application/json" -d \
        '{"evaluationId":"'$EVALUATION_ID'", "index": "'$JOB_COMPLETION_INDEX'", "events": [{"type":"'$1'","level": "'$2'"}]}' "$EVENT_INGESTION_ENDPOINT"; \
        return
    fi
    echo "Publishing event $1"
    curl -X POST -H "Content-Type: application/json" -d \
    '{"evaluationId":"'$EVALUATION_ID'", "index": "'$JOB_COMPLETION_INDEX'", "events": [{"type":"'$1'","level": "'$2'","durationInSeconds": "'$3'"}]}' "$EVENT_INGESTION_ENDPOINT"; \
}

mkdir /tmp/app
cd /tmp/app

export HOME=/tmp/app

if [ -z "$JOB_COMPLETION_INDEX" ]; then
  echo "JOB_COMPLETION_INDEX is not set"
  exit 1
fi

if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  echo "Starting spark as master"
  export SPARK_MODE="master"
  export SPARK_DRIVER_BIND_ADDRESS="$JOB_NAME-0.$SVC_NAME"
  export SPARK_DRIVER_HOST="$JOB_NAME-0.$SVC_NAME"
  export SPARK_LOCAL_IP="$JOB_NAME-0.$SVC_NAME"
  export SPARK_MASTER_HOST="$JOB_NAME-0.$SVC_NAME"
else
  echo "Starting spark as worker"
  export SPARK_MODE="worker"
  export SPARK_MASTER_URL="$JOB_NAME-0.$SVC_NAME:$masterPort"
  /opt/bitnami/scripts/spark/entrypoint.sh /opt/bitnami/scripts/spark/run.sh &

  echo "Started spark as worker, now waiting for stop signal"
  echo -e "HTTP/1.1 200 OK\n\n" | nc -l -p 8091 -q 1
  exit 0
fi

if [ "$JOB_COMPLETION_INDEX" -ne 0 ]; then
  exit 0
fi

/bin/bash -c '/opt/bitnami/scripts/spark/entrypoint.sh /opt/bitnami/scripts/spark/run.sh &'
echo "started spark as master, now building submission and running it"
#/opt/bitnami/scripts/spark/entrypoint.sh /opt/bitnami/scripts/spark/run.sh & spark-submit --conf spark.jars.ivy=/code/artifacts --packages com.amazonaws:aws-java-sdk:1.7.4,org.apache.hadoop:hadoop-aws:2.7.7,org.elasticsearch:elasticsearch-hadoop:7.10.0 --master spark://qs-spark-master:7077 /code/s3_read_elastic_write_example.py http://qs-minio:9000 s3a://qs-bucket/ qs-es-http

n=0
until [ $n -ge 20 ]
do
  echo "Cloning the project, attempt $n"

  if [ -z "$GIT_BRANCH" ]; then
    git clone "$GIT_URL" ./source
  else
    git clone -b "$GIT_BRANCH" --single-branch "$GIT_URL" ./source
  fi

  gitCloneExitCode=$?
  if [ $gitCloneExitCode -eq 0 ]; then
    break
  fi

  n=$[$n+1]
  sleep 1
done

if [ $gitCloneExitCode -ne 0 ]; then
  echo "Failed to clone the project"
  publishEvents "GIT_CLONE_FAILED" "FATAL"
  exit 1
fi

cd ./source

sbt assembly

if [ $? -ne 0 ]; then
  echo "Failed to build the project"
  publishEvents "BUILD_FAILED" "FATAL"
  exit 1
fi

echo "Built the project"

JAVA_ARTIFACT_PATH=$(find ./target -name "*.jar" -type f -not -name "*original*" | head -n 1)
if [ -z "$JAVA_ARTIFACT_PATH" ]; then
  echo "Java artifact not found"
  publishEvents "JAVA_ARTIFACT_NOT_FOUND" "ERROR"
  exit 1
fi

cp "$JAVA_ARTIFACT_PATH" ./app.jar

export MASTER_HOST="$JOB_NAME-0.$SVC_NAME:$masterPort"
export CURRENT_HOST="$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME"

START_COMMAND_NAME=START_COMMAND_"$JOB_COMPLETION_INDEX"

START_COMMAND=$(echo "${!START_COMMAND_NAME}" | envsubst)

echo "Running the command: $START_COMMAND"

SECONDS=0
$START_COMMAND
duration=$SECONDS

echo "Job completed in $duration seconds"
publishEvents "JOB_COMPLETED" "INFO" $duration

for i in $(seq 1 $NUMBER_OF_REPLICAS) # TODO calculate NUMBER_OF_REPLICAS-1, because we are not stopping the master
do
  if [ "$i" -eq 0 ]; then
    continue
  fi
  echo "Stopping worker $i"
  curl -X GET "$JOB_NAME-$i.$SVC_NAME:8091"
done