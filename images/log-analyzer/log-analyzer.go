package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

/*
   [{"date":1730547081.923005,"time":"2024-11-02T12:31:21.92300537+01:00",
       "stream":"stdout","_p":"F",
       "log":"/ # \r/ # \u001b[J\r/ # \u001b[Jecho \"hello\"",
       "kubernetes":{"pod_name":"ddm-akka","namespace_name":"default",
           "pod_id":"78686c19-c8dd-47ad-a244-c4e263cefcaa",
           "labels":{"run":"ddm-akka"},"host":"pi-master",
           "container_name":"ddm-akka",
           "docker_id":"7d8534acd61f98be4a1d317dfb263173e2645ede3356c7ca65743b90346dd287",
           "container_hash":"docker.io/library/busybox@sha256:768e5c6f5cb6db0794eec98dc7a967f40631746c32232b78a3105fb946f3ab83",
           "container_image":"docker.io/library/busybox:latest"}},
   {"date":1730547081.929952,"time":"2024-11-02T12:31:21.929951752+01:00",
       "stream":"stdout","_p":"F",
        "log":"hello",
       "kubernetes":{"pod_name":"ddm-akka","namespace_name":"default",
       "pod_id":"78686c19-c8dd-47ad-a244-c4e263cefcaa","labels":{"run":"ddm-akka"},
       "host":"pi-master","container_name":"ddm-akka",
       "docker_id":"7d8534acd61f98be4a1d317dfb263173e2645ede3356c7ca65743b90346dd287",
       "container_hash":"docker.io/library/busybox@sha256:768e5c6f5cb6db0794eec98dc7a967f40631746c32232b78a3105fb946f3ab83",
       "container_image":"docker.io/library/busybox:latest"}}]

evaluationId=`kubernetes.labels[\"batch.kubernetes.io/job-name\"]`,
index=`kubernetes.labels[\"batch.kubernetes.io/job-completion-index\"]
*/

type LogEntry struct {
	Log        string `json:"log"`
	Kubernetes Kubernetes
}

type Kubernetes struct {
	Labels map[string]string
}

var javaLogMessageErrorCategories = map[string][]string{
	"NULL_POINTER_EXCEPTION":              {"NullPointerException", "NPE"},
	"ARRAY_INDEX_OUT_OF_BOUNDS_EXCEPTION": {"ArrayIndexOutOfBoundsException", "ArrayIndexOutOfBounds"},
	"CLASS_CAST_EXCEPTION":                {"ClassCastException", "ClassCast"},
	"CONNECTION_PROBLEM":                  {"ConnectException", "StreamTcpException"},
}

type EvaluationEvent struct {
	evaluationId string
	index        string
	errors       []string
}

func ingestLogs(_ http.ResponseWriter, req *http.Request) {
	body, err := io.ReadAll(req.Body)
	if err != nil {
		panic(err)
	}
	var logEntries []LogEntry
	err = json.Unmarshal(body, &logEntries)
	if err != nil {
		panic(err)
	}
	var errors []string

	for _, logEntry := range logEntries {
		category, foundCategory := categorizeLog(logEntry.Log)

		if foundCategory {
			log.Printf("Categorized log message: %s as %s", logEntry.Log, category)
			errors = append(errors, category)
		}
	}

	if len(errors) > 0 {
		event := EvaluationEvent{
			evaluationId: logEntries[0].Kubernetes.Labels["batch.kubernetes.io/job-name"],
			index:        logEntries[0].Kubernetes.Labels["batch.kubernetes.io/job-completion-index"],
			errors:       errors,
		}
		eventJson, err := json.Marshal(event)

		if err != nil {
			panic(err)
		}

		_, err = http.Post("http://"+os.Getenv("EVALUATION_SERVICE_HOST")+":"+os.Getenv(
			"EVALUATION_SERVICE_PORT")+"/ingest/event",
			"application/json", bytes.NewBuffer(eventJson))
		if err != nil {
			log.Printf("Failed to post event to evaluation service: %s", err)
		}
	}
}

func categorizeLog(log string) (response string, foundCategory bool) {
	for category, keywords := range javaLogMessageErrorCategories {
		for _, keyword := range keywords {
			if strings.Contains(log, keyword) {
				return category, true
			}
		}
	}
	return "", false
}

func main() {
	http.HandleFunc("/ingest/logs", ingestLogs)
	log.Fatal(http.ListenAndServe(":"+os.Getenv("SERVER_PORT"), nil))
}
