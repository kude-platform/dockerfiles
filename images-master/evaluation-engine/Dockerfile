FROM bitnami/java:21-debian-12 as builder
RUN apt-get update && apt-get install -y git

RUN git clone https://github.com/kude-platform/evaluation-engine /tmp/evaluation-engine

WORKDIR /tmp/evaluation-engine
RUN ./gradlew clean build -Pvaadin.productionMode -x test

FROM bitnami/java:21-debian-12
COPY --from=builder /tmp/evaluation-engine/build/libs/app.jar ./app.jar
RUN mkdir -p ./helm/ddm-akka

COPY --from=builder /tmp/evaluation-engine/helm/ddm-akka ./helm/ddm-akka

EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]