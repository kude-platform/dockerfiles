FROM amazoncorretto:11-alpine

RUN wget https://dlcdn.apache.org/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz
RUN tar -xvf apache-maven-3.9.9-bin.tar.gz
RUN mv apache-maven-3.9.9 /opt
RUN rm apache-maven-3.9.9-bin.tar.gz

ENV M2_HOME='/opt/apache-maven-3.9.9'
ENV PATH="$M2_HOME/bin:$PATH"

RUN apk --no-cache add git unzip iperf \
    && git clone https://github.com/kude-platform/template-projects-akka-build /tmp/template-projects-akka-build

WORKDIR /tmp/template-projects-akka-build

RUN mvn install -DskipTests

RUN mkdir -p /tmp/app
WORKDIR /tmp/app
RUN mkdir -p ./data
COPY data/TPCH.zip ./data/TPCH.zip

COPY ./entrypoint.sh .
RUN chmod +x ./entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]