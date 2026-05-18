# syntax=docker/dockerfile:1.6
# Multi-stage build for alcyone (Surveys/Debriefing BE).
# Build context = ../alcyone (set in compose).

FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
ARG DOCKER_TAG
ARG NEXUS_REPO=nexus.marecrew.com
ENV DOCKER_TAG=${DOCKER_TAG}
ENV NEXUS_REPO=${NEXUS_REPO}

COPY . .

RUN --mount=type=secret,id=m2-settings,target=/root/.m2/settings.xml \
    --mount=type=cache,target=/root/.m2/repository \
    mvn -B -s /root/.m2/settings.xml \
        -pl api -am \
        -Dmaven.test.skip=true \
        -Dmaven.javadoc.skip=true \
        clean package

# --- Runtime stage ---
FROM eclipse-temurin:17-jre
WORKDIR /app
ARG DOCKER_TAG
COPY --from=build /src/api/target/api-${DOCKER_TAG}.jar /app/alcyone.jar

EXPOSE 8081
ENTRYPOINT ["java","-jar","/app/alcyone.jar"]
