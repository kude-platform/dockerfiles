package main

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Dataset struct {
	Name string `json:"name"`
}

var datasets []Dataset

func updateAvailableDatasets() {
	resp, err := http.Get("http://" + os.Getenv("EVALUATION_SERVICE_HOST") + ":" + os.Getenv(
		"EVALUATION_SERVICE_PORT") + "/api/data/datasets")

	if err != nil {
		log.Printf("Failed to get datasets from evaluation service: %s", err)
		return
	}

	responseBody, err := io.ReadAll(resp.Body)

	if err != nil {
		log.Printf("Failed to read response body from evaluation service: %s", err)
		return
	}

	err = json.Unmarshal(responseBody, &datasets)

	if err != nil {
		log.Printf("Failed to unmarshal datasets: %s", err)
		return
	}

	log.Printf("Updated available datasets: %s", datasets)
}

func downloadDatasets() {
	datasetDir := os.Getenv("DATASET_DIR")

	for _, dataset := range datasets {
		datasetName := strings.TrimRight(dataset.Name, ".zip")
		if _, err := os.Stat(datasetDir + "/" + datasetName); err == nil {
			log.Printf("Dataset %s already exists", datasetName)
			continue
		}

		resp, err := http.Get("http://" + os.Getenv("EVALUATION_SERVICE_HOST") + ":" + os.Getenv(
			"EVALUATION_SERVICE_PORT") + "/api/files/download/data/" + dataset.Name)

		if err != nil {
			log.Printf("Failed to download dataset %s: %s", dataset.Name, err)
			continue
		}

		f, err := os.CreateTemp("", dataset.Name)

		if err != nil {
			log.Printf("Failed to create file for dataset %s: %s", dataset.Name, err)
			continue
		}

		_, err = io.Copy(f, resp.Body)

		if err != nil {
			log.Printf("Failed to save dataset %s: %s", dataset.Name, err)
			continue
		}
		log.Printf("Downloaded dataset zip %s", dataset.Name)

		archive, err := zip.OpenReader(f.Name())
		if err != nil {
			panic(err)
		}

		dst := filepath.Join(datasetDir, datasetName)
		for _, f := range archive.File {
			if f.FileInfo().IsDir() {
				continue
			}
			fileName := f.Name[strings.LastIndex(f.Name, "/")+1 : len(f.Name)]
			filePath := filepath.Join(dst, fileName)
			fmt.Println("unzipping file ", filePath, " to ", dst)
			if err = os.MkdirAll(dst, os.ModePerm); err != nil {
				panic(err)
			}
			outFile, err := os.OpenFile(filePath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
			if err != nil {
				panic(err)
			}

			rc, err := f.Open()
			if err != nil {
				panic(err)
			}
			_, err = io.Copy(outFile, rc)
			if err != nil {
				panic(err)
			}
			outFile.Close()
			rc.Close()

		}

		archive.Close()
		f.Close()
		os.Remove(f.Name())
	}

	log.Printf("Finished downloading datasets")

	fileFolders, err := os.ReadDir(datasetDir)

	if err != nil {
		log.Printf("Failed to read dataset directory: %s", err)
		return
	}

	for _, fileFolder := range fileFolders {
		if !containsDataset(datasets, fileFolder.Name()) {
			err := os.RemoveAll(datasetDir + "/" + fileFolder.Name())
			if err != nil {
				log.Printf("Failed to delete dataset folder %s: %s", fileFolder.Name(), err)
			} else {
				log.Printf("Deleted dataset folder %s", fileFolder.Name())
			}
		}
	}

}

func containsDataset(d []Dataset, name string) bool {
	for _, a := range d {
		if strings.TrimRight(a.Name, ".zip") == name {
			return true
		}
	}
	return false
}

func main() {
	updateInterval := 30
	i, err := strconv.Atoi(os.Getenv("UPDATE_INTERVAL"))
	if err == nil {
		updateInterval = i
	} else {
		log.Printf("Failed to parse UPDATE_INTERVAL: %s, using default of 30", err)
	}

	datasetDir := os.Getenv("DATASET_DIR")
	if _, err := os.Stat(datasetDir); os.IsNotExist(err) {
		err := os.Mkdir(datasetDir, 0755)
		if err != nil {
			log.Printf("Failed to create dataset directory: %s", err)
			panic(err)
		}
	}

	go func() {
		for range time.Tick(time.Second * time.Duration(updateInterval)) {
			update()
		}
	}()

	update()

	log.Fatal(http.ListenAndServe(":"+os.Getenv("SERVER_PORT"), nil))
}

func update() {
	updateAvailableDatasets()
	downloadDatasets()
}
