FROM amazoncorretto:21-alpine

RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main/ nodejs
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community/ npm

RUN apk --no-cache add git curl bash \
    && git clone https://github.com/kude-platform/evaluation-engine /tmp/evaluation-engine

ENV VERIFY_CHECKSUM=false
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

WORKDIR /tmp/evaluation-engine
RUN ./gradlew clean build -Pvaadin.productionMode -x test

EXPOSE 8080
ENTRYPOINT ["java","-jar","./build/libs/app.jar"]