FROM docker:20.10.8-dind-alpine3.14

ENV SCALA_VERSION 2.13.4
ENV SBT_VERSION 1.4.9

ARG SCALA_VERSION
ENV SCALA_VERSION ${SCALA_VERSION:-2.13.6}
ARG SBT_VERSION
ENV SBT_VERSION ${SBT_VERSION:-1.5.1}
ARG USER_ID
ENV USER_ID ${USER_ID:-1001}
ARG GROUP_ID 
ENV GROUP_ID ${GROUP_ID:-1001}


# ENV PATH /sbt/bin:$PATH

RUN apk add --no-cache \
		ca-certificates \
		openssh-client \
		openjdk11 \
		curl \
		bash

RUN curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash

RUN \
  wget -O - https://downloads.typesafe.com/scala/2.13.4/scala-2.13.4.tgz | tar xfz - -C /root/ && \
  echo >> /root/.bashrc && \
  echo "export PATH=~/scala-2.13.4/bin:$PATH" >> /root/.bashrc

# Install SBT
RUN \
  curl -fsL "https://github.com/sbt/sbt/releases/download/v$SBT_VERSION/sbt-$SBT_VERSION.tgz" | tar xfz - -C /usr/share && \
  chown -R root:root /usr/share/sbt && \
  chmod -R 755 /usr/share/sbt && \
  ln -s /usr/share/sbt/bin/sbt /usr/local/bin/sbt

# Install Scala
## Piping curl directly in tar
RUN \
  case $SCALA_VERSION in \
    "3"*) URL=https://github.com/lampepfl/dotty/releases/download/$SCALA_VERSION/scala3-$SCALA_VERSION.tar.gz SCALA_DIR=/usr/share/scala3-$SCALA_VERSION ;; \
    *) URL=https://downloads.typesafe.com/scala/$SCALA_VERSION/scala-$SCALA_VERSION.tgz SCALA_DIR=/usr/share/scala-$SCALA_VERSION ;; \
  esac && \
  curl -fsL $URL | tar xfz - -C /usr/share && \
  mv $SCALA_DIR /usr/share/scala && \
  chown -R root:root /usr/share/scala && \
  chmod -R 755 /usr/share/scala && \
  ln -s /usr/share/scala/bin/* /usr/local/bin && \
  case $SCALA_VERSION in \
    "3"*) echo "@main def main = println(util.Properties.versionMsg)" > test.scala ;; \
    *) echo "println(util.Properties.versionMsg)" > test.scala ;; \
  esac && \
  scala -nocompdaemon test.scala && rm test.scala

# Add and use user sbtuser
RUN addgroup -S sbtgroup && adduser -S sbtuser sbtuser -G sbtgroup
USER sbtuser

# Switch working directory
WORKDIR /home/sbtuser  

# Prepare sbt (warm cache)
RUN \
  sbt sbtVersion && \
  mkdir -p project && \
  echo "scalaVersion := \"${SCALA_VERSION}\"" > build.sbt && \
  echo "sbt.version=${SBT_VERSION}" > project/build.properties && \
  echo "// force sbt compiler-bridge download" > project/Dependencies.scala && \
  echo "case object Temp" > Temp.scala && \
  sbt compile && \
  rm -r project && rm build.sbt && rm Temp.scala && rm -r target

# Link everything into root as well
# This allows users of this container to choose, whether they want to run the container as sbtuser (non-root) or as root
USER root
RUN \
  ln -s /home/sbtuser/.cache /root/.cache && \
  ln -s /home/sbtuser/.sbt /root/.sbt && \
  if [ -d "/home/sbtuser/.ivy2" ]; then ln -s /home/sbtuser/.ivy2 /root/.ivy2; fi

# Switch working directory back to root
## Users wanting to use this container as non-root should combine the two following arguments
## -u sbtuser
## -w /home/sbtuser
WORKDIR /root  

CMD sbt
