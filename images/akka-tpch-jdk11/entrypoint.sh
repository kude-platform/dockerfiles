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

if [ -z "$POD_IP" ]; then
  echo "POD_IP is not set"
  exit 1
fi

git clone "$GIT_URL" ./source

if [ "$UNZIP_DATA" = true ]; then
  unzip -o ./data/TPCH.zip -d ./source/data
fi

cd ./source

if [ "$OFFLINE_MODE" = true ]; then
  mvn -o install $ADDITIONAL_MAVEN_ARGS
else
  mvn install $ADDITIONAL_MAVEN_ARGS
fi

cp ./target/app.jar ./app.jar

if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  java $JVM_ARGS -jar ./app.jar master -h "$JOB_NAME-0.$SVC_NAME" -ia $POD_IP $ADDITIONAL_MASTER_ARGS
  if [ -n "$RESULTS_ENDPOINT" ]; then
    curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
  fi
else
  java $JVM_ARGS -jar ./app.jar worker -mh "$JOB_NAME-0.$SVC_NAME" -h "$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME" -ia $POD_IP $ADDITIONAL_WORKER_ARGS
fi