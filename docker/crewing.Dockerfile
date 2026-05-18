# syntax=docker/dockerfile:1.6
# Multi-stage build for phoebe/crewing.
# Expects build context = ../phoebe (set in compose).
# Requires Nexus credentials mounted as BuildKit secret "m2-settings"
# (points at the user's ~/.m2/settings.xml with a <server id="nexus"> entry).

FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
ARG DOCKER_TAG
ARG NEXUS_REPO=nexus.marecrew.com
ENV DOCKER_TAG=${DOCKER_TAG}
ENV NEXUS_REPO=${NEXUS_REPO}

# Copy the whole phoebe monorepo (parent pom + all modules it needs).
COPY . .

# Build crewing + any phoebe modules it depends on (-am = also-make).
# Skip tests and javadoc to keep the first build reasonable.
RUN --mount=type=secret,id=m2-settings,target=/root/.m2/settings.xml \
    --mount=type=cache,target=/root/.m2/repository \
    mvn -B -s /root/.m2/settings.xml \
        -pl crewing -am \
        -Dmaven.test.skip=true \
        -Dmaven.javadoc.skip=true \
        clean package

# --- Runtime stage ---
FROM eclipse-temurin:17-jre
WORKDIR /app
ARG DOCKER_TAG
COPY --from=build /src/crewing/target/crewing-${DOCKER_TAG}.jar /app/crewing.jar

EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/crewing.jar"]
