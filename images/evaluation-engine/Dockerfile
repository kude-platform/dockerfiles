FROM amazoncorretto:21-alpine

RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main/ nodejs
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community/ npm

# gcompbat contains libresolv.so.2 which is required for helm which is used in the evaluation-engine
RUN apk --no-cache add git gcompat \
    && git clone https://github.com/kude-platform/evaluation-engine /tmp/evaluation-engine

WORKDIR /tmp/evaluation-engine
RUN ./gradlew clean build -Pvaadin.productionMode -x test

EXPOSE 8080
ENTRYPOINT ["java","-jar","./build/libs/app.jar"]