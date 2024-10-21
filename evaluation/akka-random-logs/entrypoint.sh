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

if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  java $JVM_ARGS -jar ./app.jar master -h "$JOB_NAME-0.$SVC_NAME" -ia $POD_IP $ADDITIONAL_MASTER_ARGS
else
  java $JVM_ARGS -jar ./app.jar worker -mh "$JOB_NAME-0.$SVC_NAME" -h "$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME" -ia $POD_IP $ADDITIONAL_WORKER_ARGS
fi