package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
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

type EventDefinition struct {
	Type     string   `json:"type"`
	Patterns []string `json:"patterns"`
	Level    string   `json:"level"`
}

var eventDefinitions []EventDefinition

var genericExceptionPatterns = []string{
	"Exception", "Error", "error", "exception", "fail", "Fail", "Failed", "failed",
}

type EvaluationEvent struct {
	EvaluationId string            `json:"evaluationId"`
	Index        string            `json:"index"`
	Events       []EventDefinition `json:"events"`
}

func ingestLogFiles(_ http.ResponseWriter, req *http.Request) {
	file, _, err := req.FormFile("file")
	if err != nil {
		panic(err)
	}

	evaluationId := req.URL.Query().Get("evaluationId")
	index := req.URL.Query().Get("index")

	scanner := bufio.NewScanner(file)
	var logEntries []LogEntry
	for scanner.Scan() {
		logEntries = append(logEntries, LogEntry{Log: scanner.Text(),
			Kubernetes: Kubernetes{Labels: map[string]string{"evaluation-id": evaluationId,
				"batch.kubernetes.io/job-completion-index": index}},
		})
	}

	analyzeLogEntries(logEntries)
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
	analyzeLogEntries(logEntries)
}

func analyzeLogEntries(logEntries []LogEntry) {
	var events []EventDefinition

	for _, logEntry := range logEntries {
		eventDefinition, foundCategory := categorizeLog(logEntry.Log)

		if foundCategory {
			log.Printf("Categorized log message: %s as %s", logEntry.Log, eventDefinition)
			events = append(events, eventDefinition)
		}
	}

	if len(events) > 0 {
		event := EvaluationEvent{
			EvaluationId: logEntries[0].Kubernetes.Labels["evaluation-id"],
			Index:        logEntries[0].Kubernetes.Labels["batch.kubernetes.io/job-completion-index"],
			Events:       events,
		}
		eventJson, err := json.Marshal(event)
		log.Printf("Event: %s", eventJson)

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

func categorizeLog(log string) (response EventDefinition, foundCategory bool) {
	for eventDefinition := range eventDefinitions {
		for _, keyword := range eventDefinitions[eventDefinition].Patterns {
			if strings.Contains(log, keyword) {
				return eventDefinitions[eventDefinition], true
			}
		}
	}

	for _, keyword := range genericExceptionPatterns {
		if !strings.Contains(log, keyword) {
			continue
		}

		for _, word := range strings.Fields(log) {
			if !strings.Contains(word, keyword) {
				continue
			}
			return EventDefinition{Type: word, Patterns: []string{word}, Level: "ERROR"}, true
		}

	}

	return EventDefinition{}, false
}

func updateLogMessageEventDefinitions() {
	resp, err := http.Get("http://" + os.Getenv("EVALUATION_SERVICE_HOST") + ":" + os.Getenv(
		"EVALUATION_SERVICE_PORT") + "/api/logEventDefinition")

	if err != nil {
		log.Printf("Failed to get log event definitions from evaluation service: %s", err)
		return
	}

	responseBody, err := io.ReadAll(resp.Body)

	if err != nil {
		log.Printf("Failed to read response body from evaluation service: %s", err)
		return
	}

	err = json.Unmarshal(responseBody, &eventDefinitions)

	if err != nil {
		log.Printf("Failed to unmarshal log event definitions: %s", err)
		return
	}

	log.Printf("Updated log event definitions: %s", eventDefinitions)
}

func initializeGenericExceptionPatterns() {
	if os.Getenv("GENERIC_EXCEPTION_PATTERNS") != "" {
		log.Printf("Using generic exception patterns: %s", os.Getenv("GENERIC_EXCEPTION_PATTERNS"))
		genericExceptionPatterns = strings.Split(os.Getenv("GENERIC_EXCEPTION_PATTERNS"), ",")
	} else {
		log.Printf("Using default generic exception patterns: %s", genericExceptionPatterns)
	}
}

func main() {
	http.HandleFunc("/ingest/logs", ingestLogs)
	http.HandleFunc("/ingest/logfiles", ingestLogFiles)

	initializeGenericExceptionPatterns()

	go func() {
		for range time.Tick(time.Second * 30) {
			updateLogMessageEventDefinitions()
		}
	}()

	log.Fatal(http.ListenAndServe(":"+os.Getenv("SERVER_PORT"), nil))
}
