#!/bin/bash
#current directory in the container is /tmp/app
pidOfCurrentProcess=0

function finish {
    echo "Received signal, trying to publish logs and exit"
    publishLogs
    if [ $pidOfCurrentProcess -ne 0 ]; then
        echo "Killing process $pidOfCurrentProcess"
        kill -SIGTERM $pidOfCurrentProcess
        wait $pidOfCurrentProcess
    fi
    exit 0
}

function publishLogs {
    if [ -f ./service.log ] && [ -f ./mvn.log ]; then
        echo "publishing maven and service logs"
        zip logs.zip ./service.log ./mvn.log
        if [ -n "$LOGS_ENDPOINT" ]; then
            curl -X POST -F "file=@./logs.zip" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
        fi
    elif [ -f ./mvn.log ]; then
        echo "publishing maven logs"
        if [ -n "$LOGS_ENDPOINT" ]; then
            curl -X POST -F "file=@./mvn.log" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
        fi
    else 
        echo "no logs to publish available"
    fi    
}

function publishEvents {
    echo "Publishing event $1"
    curl -X POST -H "Content-Type: application/json" -d \
    '{"evaluationId":"'$EVALUATION_ID'", "index": "'$JOB_COMPLETION_INDEX'", "errors": ["'$1'"]}' "$EVENT_INGESTION_ENDPOINT"; \
}

trap finish SIGHUP SIGINT SIGQUIT SIGTERM

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
  git apply --reject --ignore-space-change --ignore-whitespace ./../akka-kubernetes-config.patch
fi 

echo "Building project, logs will be available at /tmp/app/mvn.log"

if [ "$OFFLINE_MODE" = true ]; then
  mvn -o install $ADDITIONAL_MAVEN_ARGS $@ &> ./mvn.log &
else
  mvn install $ADDITIONAL_MAVEN_ARGS $@ &> ./mvn.log &
fi

pidOfCurrentProcess=$!
echo "Maven install pid is $pidOfCurrentProcess"
wait "$pidOfCurrentProcess"

if [ $? -ne 0 ]; then
  curl -X POST -F "file=@./mvn.log" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
  echo "Maven build failed"
  publishEvents "MVN_BUILD_FAILED"
  exit 1
fi

cp ./target/app.jar ./app.jar

JAVA_EXIT_CODE=0

echo "Starting service, logs will be available at /tmp/app/service.log"

if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  publishEvents "STARTING_MASTER"
  java $JVM_ARGS -jar ./app.jar master -h "$JOB_NAME-0.$SVC_NAME" -ia $POD_IP $ADDITIONAL_MASTER_ARGS $@ &> ./service.log &
else
  publishEvents "STARTING_WORKER"
  java $JVM_ARGS -jar ./app.jar worker -mh "$JOB_NAME-0.$SVC_NAME" -h "$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME" -ia $POD_IP $ADDITIONAL_WORKER_ARGS $@ &> ./service.log &
fi

pidOfCurrentProcess=$!
echo "Java run pid is $pidOfCurrentProcess"
wait "$pidOfCurrentProcess"
JAVA_EXIT_CODE=$?

if [ "$JOB_COMPLETION_INDEX" -eq 0 ] && [ -n "$RESULTS_ENDPOINT" ]; then
  curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
fi

zip logs.zip ./service.log ./mvn.log
if [ -n "$LOGS_ENDPOINT" ]; then
  curl -X POST -F "file=@./logs.zip" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
fi

if [ -n "$LOG_ANALYZER_ENDPOINT" ]; then
  curl -X POST -F "file=@./service.log" "$LOG_ANALYZER_ENDPOINT?evaluationId=$EVALUATION_ID&index=$JOB_COMPLETION_INDEX"
fi

publishEvents "JOB_COMPLETED"

exit $JAVA_EXIT_CODE