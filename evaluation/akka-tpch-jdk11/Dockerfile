FROM arm64v8/maven:3-amazoncorretto-11-al2023

RUN apk --no-cache add git unzip \
    && git clone https://github.com/kude-platform/template-projects-akka /tmp/template-projects-akka-build

WORKDIR /tmp/template-projects-akka-build

RUN mvn install -DskipTests

RUN mkdir -p /tmp/app
WORKDIR /tmp/app
RUN mkdir -p ./data
COPY data/TPCH.zip ./data/TPCH.zip

COPY ./entrypoint.sh .
RUN chmod +x ./entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]