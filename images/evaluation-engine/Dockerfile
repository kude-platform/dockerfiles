FROM openjdk:21-jdk AS build

RUN microdnf install git \
    && git clone https://github.com/kude-platform/evaluation-engine /tmp/evaluation-engine
WORKDIR /tmp/evaluation-engine
RUN ./gradlew clean build -Pvaadin.productionMode

FROM openjdk:21-jdk-slim
EXPOSE 8080
WORKDIR /opt/app
COPY --from=build /tmp/evaluation-engine/build/libs/app.jar /opt/app/
ENTRYPOINT ["java","-jar","app.jar"]