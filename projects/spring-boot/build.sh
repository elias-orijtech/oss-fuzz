#!/bin/bash -eu
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

mv $SRC/{*.zip,*.dict} $OUT

cp -r "/usr/lib/jvm/java-17-openjdk-amd64/." "$JAVA_HOME"

CURRENT_VERSION=$(./gradlew properties --no-daemon --console=plain | sed -nr "s/^version:\ (.*)/\1/p")

./gradlew publishToMavenLocal -x test -x intTest -i -x asciidoctor -x javadoc -x asciidoctorPdf -x :spring-boot-project:spring-boot-docs:zip -x :spring-boot-project:spring-boot-docs:publishMavenPublicationToMavenLocal
cp "/root/.m2/repository/org/springframework/boot/spring-boot/$CURRENT_VERSION/spring-boot-$CURRENT_VERSION.jar" "$OUT/spring-boot.jar"
cp "/root/.m2/repository/org/springframework/boot/spring-boot-loader/$CURRENT_VERSION/spring-boot-loader-$CURRENT_VERSION.jar" "$OUT/spring-boot-loader.jar"
cp "/root/.m2/repository/org/springframework/boot/spring-boot-starter-web/$CURRENT_VERSION/spring-boot-starter-web-$CURRENT_VERSION.jar" "$OUT/spring-boot-starter-web.jar"

# Spring core
CURRENT_VERSION=$(./gradlew properties --no-daemon --console=plain --build-file=spring-framework/build.gradle | sed -nr "s/^version:\ (.*)/\1/p")
./gradlew build --build-file=spring-framework/spring-core/spring-core.gradle -x test -x javadoc -x :checkstyleNohttp
cp "spring-framework/spring-core/build/libs/spring-core-$CURRENT_VERSION.jar" "$OUT/spring-core.jar"

ALL_JARS="spring-boot.jar spring-boot-loader.jar spring-core.jar spring-boot-starter-web.jar"

# The classpath at build-time includes the project jars in $OUT as well as the
# Jazzer API.
BUILD_CLASSPATH=$(echo $ALL_JARS | xargs printf -- "$OUT/%s:"):$JAZZER_API_PATH

# All .jar and .class files lie in the same directory as the fuzzer at runtime.
RUNTIME_CLASSPATH=$(echo $ALL_JARS | xargs printf -- "\$this_dir/%s:"):\$this_dir

for fuzzer in $(find $SRC -name '*Fuzzer.java'); do
  fuzzer_basename=$(basename -s .java $fuzzer)
  javac -cp $BUILD_CLASSPATH $fuzzer --release 17
  cp $SRC/$fuzzer_basename.class $OUT/

  # Create an execution wrapper that executes Jazzer with the correct arguments.
  echo "#!/bin/sh
# LLVMFuzzerTestOneInput for fuzzer detection.
this_dir=\$(dirname \"\$0\")
JAVA_HOME=\"\$this_dir/open-jdk-17/\" \
LD_LIBRARY_PATH=\"$JVM_LD_LIBRARY_PATH\":\$this_dir \
\$this_dir/jazzer_driver --agent_path=\$this_dir/jazzer_agent_deploy.jar \
--cp=$RUNTIME_CLASSPATH \
--target_class=$fuzzer_basename \
--jvm_args=\"-Xmx2048m\" \
\$@" > $OUT/$fuzzer_basename
  chmod u+x $OUT/$fuzzer_basename
done 
