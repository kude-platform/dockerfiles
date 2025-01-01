#!/bin/bash
#current directory in the container is /tmp/app
pidOfCurrentProcess=0

function finish {
    echo "Received signal, trying to publish logs, results, and exit"
    if [ $pidOfCurrentProcess -ne 0 ]; then
        echo "Killing process $pidOfCurrentProcess"
        kill -SIGTERM $pidOfCurrentProcess
        wait $pidOfCurrentProcess
    fi
    publishLogs
    if [ "$JOB_COMPLETION_INDEX" -eq 0 ] && [ -n "$RESULTS_ENDPOINT" ]; then
      curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
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

if [ -z "$GIT_BRANCH" ]; then
  git clone "$GIT_URL" ./source
else
  git clone -b "$GIT_BRANCH" --single-branch "$GIT_URL" ./source
fi

pom_path=/tmp/app/source/pom.xml

if [ ! -f ./source/pom.xml ]; then
    publishEvents "POM_NOT_IN_ROOT"
    echo "pom.xml not found in the root directory of the project. Trying to find it in the subdirectories"
    pom_path=$(find . -name pom.xml -type f -print -quit)

    if [ -z "$pom_path" ]; then
        publishEvents "POM_NOT_FOUND"
        echo "pom.xml not found in the project"
        exit 1
    fi
fi

pom_directory=$(dirname "$pom_path")

if [ "$pom_directory" != "/tmp/app/source" ]; then
    cp -r "$pom_directory"/* /tmp/app/source
fi

cd /tmp/app/source

if [ -n "$REMOVE_LINES_IN_FILES" ] && [ -n "$REMOVE_AMOUNT_IN_PERCENT" ]; then
  for file in $(echo $REMOVE_LINES_IN_FILES | tr "," "\n")
  do
    amountOfLines=$(wc -l < $file)
    amountOfLinesToKeep=$(echo "scale=0; $amountOfLines * (100 - $REMOVE_AMOUNT_IN_PERCENT) / 100" | bc)
    head -n $amountOfLinesToKeep $file > $file.tmp
    mv $file.tmp $file
  done
fi

if [ "$APPLY_PATCH" = true ]; then
  git apply --reject --ignore-space-change --ignore-whitespace /tmp/app/akka-kubernetes-config.patch
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

export MASTER_HOST="$JOB_NAME-0.$SVC_NAME"
export CURRENT_HOST="$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME"

publishEvents "BUILD_COMPLETED"

if [ -n "$EVALUATION_SERVICE_ALL_PODS_READY_TO_RUN_ENDPOINT" ]; then
  echo "Waiting until all pods are ready..."
  
  while true; do
    milliseconds_to_sleep_until_next_full_second=$((1000 - $(date +%s%3N) % 1000))
    sleep 0.$milliseconds_to_sleep_until_next_full_second

    response=$(curl -s "$EVALUATION_SERVICE_ALL_PODS_READY_TO_RUN_ENDPOINT/$EVALUATION_ID")
    echo "Response from evaluation service: $response"

    if [ "$response" = "READY" ]; then
      break
    fi

  done
fi


START_COMMAND_NAME=START_COMMAND_"$JOB_COMPLETION_INDEX"

START_COMMAND=$(echo "${!START_COMMAND_NAME}" | envsubst)

if [ "$LOG_TO_CONSOLE" = true ]; then
  if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
    echo "$START_COMMAND"
    $START_COMMAND &

    pidOfCurrentProcess=$!
    echo "Java run pid is $pidOfCurrentProcess"
    wait "$pidOfCurrentProcess"

    if [ -n "$RESULTS_ENDPOINT" ]; then
      curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
    fi
  else
    echo "$START_COMMAND"
    $START_COMMAND &
  
    pidOfCurrentProcess=$!
    echo "Java run pid is $pidOfCurrentProcess"
    wait "$pidOfCurrentProcess"
  fi

  publishEvents "JOB_COMPLETED"
  exit $?
fi

echo "Starting service, logs will be available in service.log"

if [ "$JOB_COMPLETION_INDEX" -eq 0 ]; then
  publishEvents "STARTING_MASTER"
  echo "$START_COMMAND"
  $START_COMMAND & $@ &> ./service.log &
else
  publishEvents "STARTING_WORKER"
  echo "$START_COMMAND"
  $START_COMMAND & $@ &> ./service.log &
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