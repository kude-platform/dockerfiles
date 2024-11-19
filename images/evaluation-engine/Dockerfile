FROM amazoncorretto:21-alpine AS build

RUN apk --no-cache add git \
    && git clone https://github.com/kude-platform/evaluation-engine /tmp/evaluation-engine
WORKDIR /tmp/evaluation-engine
RUN ./gradlew clean build -Pvaadin.productionMode

FROM amazoncorretto:21-alpine
EXPOSE 8080
WORKDIR /opt/app
COPY --from=build /tmp/evaluation-engine/build/libs/app.jar /opt/app/
ENTRYPOINT ["java","-jar","app.jar"]