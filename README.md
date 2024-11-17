# Dockerfiles
Dockerfiles of various evaluation containers as well as other tools on kude platform. 

## Building Docker Images
To build all the docker images, run the following command:
```bash
./build-dockerfiles-and-import-to-k3s.sh
```
The script will build all the docker images, if they are not already built and present in the local docker registry. It will then import the images to the k3s docker registry. Older versions of the images will be removed from the local registry.