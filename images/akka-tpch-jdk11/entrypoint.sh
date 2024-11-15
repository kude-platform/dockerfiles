#!/bin/bash
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

if [ "$APPLY_PATCH" = true ]; then
  git apply ./akka-kubernetes-config.patch
fi 

echo "Building project, logs will be available at /tmp/app/mvn.log"

if [ "$OFFLINE_MODE" = true ]; then
  mvn -o install $ADDITIONAL_MAVEN_ARGS $@ | tee ./mvn.log >/dev/null
else
  mvn install $ADDITIONAL_MAVEN_ARGS $@ | tee ./mvn.log >/dev/null
fi

if [ ${PIPESTATUS[0]} -ne 0 ]; then
  curl -X POST -F "file=@./mvn.log" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
  echo "Maven build failed"
  exit 1
fi

cp ./target/app.jar ./app.jar

JAVA_EXIT_CODE=0

echo "Starting service, logs will be available at /tmp/app/service.log"

if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  java $JVM_ARGS -jar ./app.jar master -h "$JOB_NAME-0.$SVC_NAME" -ia $POD_IP $ADDITIONAL_MASTER_ARGS $@ | tee ./service.log >/dev/null
  JAVA_EXIT_CODE=${PIPESTATUS[0]}
  if [ -n "$RESULTS_ENDPOINT" ]; then
    curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
  fi
else
  java $JVM_ARGS -jar ./app.jar worker -mh "$JOB_NAME-0.$SVC_NAME" -h "$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME" -ia $POD_IP $ADDITIONAL_WORKER_ARGS $@ | tee ./service.log >/dev/null
  JAVA_EXIT_CODE=${PIPESTATUS[0]}
fi

zip logs.zip ./service.log ./mvn.log
if [ -n "$LOGS_ENDPOINT" ]; then
  curl -X POST -F "file=@./logs.zip" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
fi

exit $JAVA_EXIT_CODE