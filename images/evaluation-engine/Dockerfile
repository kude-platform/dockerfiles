FROM amazoncorretto:21-alpine AS build

RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main/ nodejs
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community/ npm

RUN apk --no-cache add git \
    && git clone https://github.com/kude-platform/evaluation-engine /tmp/evaluation-engine
WORKDIR /tmp/evaluation-engine
RUN ./gradlew clean build -Pvaadin.productionMode -x test

FROM amazoncorretto:21-alpine
RUN apk --no-cache add curl bash 
RUN export VERIFY_CHECKSUM=false
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
EXPOSE 8080
WORKDIR /opt/app
COPY --from=build /tmp/evaluation-engine/helm /opt/app/helm
COPY --from=build /tmp/evaluation-engine/build/libs/app.jar /opt/app/
ENTRYPOINT ["java","-jar","app.jar"]