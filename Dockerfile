FROM openjdk:11-jre-slim

# Install JMeter
ENV JMETER_VERSION=5.6.3
ENV JMETER_HOME=/opt/apache-jmeter-${JMETER_VERSION}
ENV PATH=${JMETER_HOME}/bin:${PATH}

RUN apt-get update && \
    apt-get install -y wget curl && \
    wget https://downloads.apache.org/jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz -C /opt && \
    rm apache-jmeter-${JMETER_VERSION}.tgz && \
    apt-get clean

# Create directories
RUN mkdir -p /tests /results

WORKDIR /tests

# Default command
CMD ["jmeter", "--version"]