#!/bin/bash
#current directory in the container is /tmp/app
pidOfCurrentProcess=0

function finish {
    echo "Received signal, trying to publish logs, results, and exit"
    if [ "$JOB_COMPLETION_INDEX" -eq 0 ] && [ -n "$RESULTS_ENDPOINT" ]; then
      echo "Publishing results, first attempt"
      curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
    fi
    if [ $pidOfCurrentProcess -ne 0 ]; then
        echo "Killing process $pidOfCurrentProcess"
        kill -SIGTERM $pidOfCurrentProcess
        wait $pidOfCurrentProcess
    fi
    publishLogs
    if [ "$JOB_COMPLETION_INDEX" -eq 0 ] && [ -n "$RESULTS_ENDPOINT" ]; then
      echo "Publishing results, second attempt"
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

pom_path=/tmp/app/source/pom.xml

if [ ! -f ./source/pom.xml ]; then
    publishEvents "POM_NOT_IN_ROOT" "WARN"
    echo "pom.xml not found in the root directory of the project. Trying to find it in the subdirectories"
    pom_path=$(find . -name pom.xml -type f -print -quit)

    if [ -z "$pom_path" ]; then
        publishEvents "POM_NOT_FOUND" "ERROR"
        echo "pom.xml not found in the project"
        exit 1
    fi
fi

pom_directory=$(dirname "$pom_path")

if [ "$pom_directory" != "/tmp/app/source" ]; then
    cp -r "$pom_directory"/* /tmp/app/source
fi

cd /tmp/app/source

if [ -f ./results.txt ] && [ -s ./results.txt ]; then
  publishEvents "RESULTS_FILE_ALREADY_EXISTS_WITH_CONTENT" "WARN"
  rm -f ./results.txt
fi

if [ "$APPLY_PATCH" = true ]; then
  patch -p1 -l -f < /tmp/app/akka-kubernetes-config.patch
fi

echo "Building project, logs will be available at /tmp/app/mvn.log"
SECONDS=0
if [ "$OFFLINE_MODE" = true ]; then
  mvn -o install $ADDITIONAL_MAVEN_ARGS $@ &> ./mvn.log &
else
  mvn install $ADDITIONAL_MAVEN_ARGS $@ &> ./mvn.log &
fi
mvnBuildDuration=$SECONDS

pidOfCurrentProcess=$!
echo "Maven install pid is $pidOfCurrentProcess"
wait "$pidOfCurrentProcess"

if [ $? -ne 0 ]; then

  # try again without patched changes
  if [ "$APPLY_PATCH" = true ]; then
    git reset --hard

    echo "Building project without patch, logs will be available at /tmp/app/mvn.log"

    if [ "$OFFLINE_MODE" = true ]; then
      mvn -o install $ADDITIONAL_MAVEN_ARGS $@ &> ./mvn.log &
    else
      mvn install $ADDITIONAL_MAVEN_ARGS $@ &> ./mvn.log &
    fi

    pidOfCurrentProcess=$!
    echo "Maven install pid is $pidOfCurrentProcess"
    wait "$pidOfCurrentProcess"
    MAVEN_EXIT_CODE=$?

    curl -X POST -F "file=@./mvn.log" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"

    if [ $MAVEN_EXIT_CODE -eq 0 ]; then
      publishEvents "MVN_BUILD_FAILED_WITH_PATCH" "ERROR"
      exit 1
    else
      publishEvents "MVN_BUILD_FAILED" "ERROR"
      exit 1
    fi

  fi

  echo "Maven build failed"
  publishEvents "MVN_BUILD_FAILED" "ERROR"
  exit 1
fi

curl -X POST -F "file=@./mvn.log" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
echo "Build completed in $mvnBuildDuration seconds"
publishEvents "BUILD_COMPLETED" "INFO" $mvnBuildDuration

JAVA_ARTIFACT_PATH=$(find ./target -name "*.jar" -type f -not -name "*original*" | head -n 1)
if [ -z "$JAVA_ARTIFACT_PATH" ]; then
  echo "Java artifact not found"
  publishEvents "JAVA_ARTIFACT_NOT_FOUND" "ERROR"
  exit 1
fi

cp "$JAVA_ARTIFACT_PATH" ./app.jar

JAVA_EXIT_CODE=0

export MASTER_HOST="$JOB_NAME-0.$SVC_NAME"
export CURRENT_HOST="$JOB_NAME-$JOB_COMPLETION_INDEX.$SVC_NAME"

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
  echo "Starting service, logs will be available in console"

  echo "$START_COMMAND"
  SECONDS=0
  $START_COMMAND &

  pidOfCurrentProcess=$!
  echo "Java run pid is $pidOfCurrentProcess"
  wait "$pidOfCurrentProcess"
  JAVA_EXIT_CODE=$?
  duration=$SECONDS

else
  echo "Starting service, logs will be available in service.log"

  publishEvents "STARTING_MASTER" "INFO"
  echo "$START_COMMAND"
  SECONDS=0
  $START_COMMAND & $@ &> ./service.log &

  pidOfCurrentProcess=$!
  echo "Java run pid is $pidOfCurrentProcess"
  wait "$pidOfCurrentProcess"
  JAVA_EXIT_CODE=$?
  duration=$SECONDS

  zip logs.zip ./service.log ./mvn.log
  if [ -n "$LOGS_ENDPOINT" ]; then
    curl -X POST -F "file=@./logs.zip" "$LOGS_ENDPOINT/$EVALUATION_ID/$JOB_COMPLETION_INDEX"
  fi

  if [ -n "$LOG_ANALYZER_ENDPOINT" ]; then
    curl -X POST -F "file=@./service.log" "$LOG_ANALYZER_ENDPOINT?evaluationId=$EVALUATION_ID&index=$JOB_COMPLETION_INDEX"
  fi
fi


if [ "$JOB_COMPLETION_INDEX" -eq 0 ] && [ -n "$RESULTS_ENDPOINT" ]; then
  curl -X POST -F "file=@./results.txt" "$RESULTS_ENDPOINT/$EVALUATION_ID"
fi

echo "Job completed in $duration seconds"
publishEvents "JOB_COMPLETED" "INFO" $duration

exit $JAVA_EXIT_CODE