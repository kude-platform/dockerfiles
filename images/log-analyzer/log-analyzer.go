package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
)

type testStruct struct {
	Test string
}

func ingestLogs(rw http.ResponseWriter, req *http.Request) {
	body, err := io.ReadAll(req.Body)
	if err != nil {
		panic(err)
	}
	log.Println(string(body))
	var t testStruct
	err = json.Unmarshal(body, &t)
	if err != nil {
		panic(err)
	}
	log.Println(t.Test)
}

func main() {
	http.HandleFunc("/ingest/logs", ingestLogs)
	log.Fatal(http.ListenAndServe(":8082", nil))
}
