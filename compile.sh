#!/usr/bin/env bash
###############################################
# Marlin firmware compilation script          #
# Copyright Eric Draken, 2022, ericdraken.com #
###############################################
set -e

####################
#  BEGIN SETTINGS  #
####################

# e.g. bugfix-2.1.x, release-2.1.1, etc.
# See https://github.com/MarlinFirmware/Marlin branches
MARLIN_BRANCH="v2.0.8.1-cr6-community-release-6.1_build-patch"

# Given https://raw.githubusercontent.com/MarlinFirmware/Configurations/$MARLIN_BRANCH/config/examples/Creality/Ender-3%20Pro/CrealityV427,
# the remote config folder is: Creality/Ender-3%20Pro/CrealityV427
REMOTE_CONFIG_FOLDER="btt-skr-cr6-with-stock-creality-tft"

# e.g. STM32F103RE_creality, STM32F103RE_btt
# See ini/stm32f1.ini for more strings
PLATFORM="STM32F103RE_btt_USB"

##################
#  END SETTINGS  #
##################


CONFIGS="https://raw.githubusercontent.com/j3ffrw/Marlin/$MARLIN_BRANCH/config/${REMOTE_CONFIG_FOLDER}"
GITREPO=https://github.com/j3ffrw/Marlin.git
HERE="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"

printf "\n\033[0;32mGetting Marlin source code for branch %s\033[0m\n" ${MARLIN_BRANCH}

# Create a temporary folder
TMP="$HERE/.tmp/$MARLIN_BRANCH"
[[ -d "$TMP" ]] || mkdir -p "$TMP"

# Create the out folder
OUT="$HERE/firmware/$MARLIN_BRANCH-$PLATFORM"
[[ -d "$OUT" ]] || mkdir -p "$OUT"

# Clone Marlin into the temporary folder
if [[ ! -e "$TMP/README.md" ]]; then
  echo "Cloning Marlin from GitHub to $TMP"
  git clone --depth=1 --single-branch --branch "$MARLIN_BRANCH" $GITREPO "$TMP" || { echo "Failed to clone Marlin"; exit ; }
else
  echo "Using cached Marlin at $TMP"
fi

printf "\n\033[0;32mGetting Marlin config files for %s\033[0m\n" ${REMOTE_CONFIG_FOLDER}

# Select a tool to download config files
which curl >/dev/null && TOOL='curl -L -s -S -f -o wgot'
which wget >/dev/null && TOOL='wget -q -O wgot'

cd "$TMP/Marlin"


# Download configs for REMOTE_CONFIG_FOLDER
echo "Download configs for $REMOTE_CONFIG_FOLDER"
$TOOL "$CONFIGS/Configuration.h"     >/dev/null 2>&1 && mv wgot Configuration.h
$TOOL "$CONFIGS/Configuration_adv.h" >/dev/null 2>&1 && mv wgot Configuration_adv.h
$TOOL "$CONFIGS/platformio-environment.txt"       >/dev/null 2>&1 && mv wgot platformio-environment.txt
$TOOL "$CONFIGS/description.txt"       >/dev/null 2>&1 && mv wgot description.txt

rm -f wgot
cd - >/dev/null

# https://github.com/CR6Community/Marlin?tab=readme-ov-file#development-and-compile-it-yourself
# Copy over existing config files from the user, if present
if [[ -e "$OUT/Configuration.h" ]]; then
  echo "Using configuration files found in $OUT."
  echo "Delete these files to use the remote configuration files instead."
  cp "$OUT/Configuration.h"     "$TMP/Marlin"
  cp "$OUT/Configuration_adv.h" "$TMP/Marlin"
  cp "$OUT/description.txt" "$TMP/Marlin"
  cp "$OUT/platformio-environment.txt" "$TMP/Marlin"
  sed -i -e "s/default_envs\ =\ .*/default_envs = `cat $OUT/platformio-environment.txt`/" "$TMP/platformio.ini"
else
  echo "Using remote configuration files found at $REMOTE_CONFIG_FOLDER."
  cp "$TMP/Marlin/Configuration.h"     "$OUT"
  cp "$TMP/Marlin/Configuration_adv.h" "$OUT"
  cp "$TMP/Marlin/description.txt" "$OUT"
  cp "$TMP/Marlin/platformio-environment.txt" "$OUT"
  sed -i -e "s/default_envs\ =\ .*/default_envs = `cat $TMP/Marlin/platformio-environment.txt`/" "$TMP/platformio.ini"
fi

# Use a custom thermistor table if it exists, and be sure
# to set #define TEMP_SENSOR_0 2 in Configuration.h. You should get
# #warning "Using custom thermistor table temptable_2" [-Wcpp]
# if you have successfully set the thermistor to 2
if [[ -e "$OUT/thermistor_2.h" ]]; then
  echo "Using thermistor_2.h found in $OUT."
  cp "$OUT/thermistor_2.h"     "$TMP/Marlin/src/module/thermistor"
fi

printf "\n\033[0;32mSetting up Docker\033[0m\n"

cd "$TMP"

# Build the Docker image (marlin) if it doesn't exit
# TIP: Run `sudo service docker restart` if you get "Temporary failure in name resolution"
echo Run docker-compose build
docker-compose build

echo Run docker-compose run --rm marlin /code/buildroot/bin/format_code
# Just a test that buildroot is present - this does nothing except return 0
docker-compose run --rm marlin /code/buildroot/bin/format_code

printf "\n\033[0;32mCompiling Marlin for %s\033[0m\n" "$PLATFORM"

# Clean
echo Run docker-compose run --rm marlin platformio run --target clean -e "$PLATFORM"
docker-compose run --rm marlin platformio run --target clean -e "$PLATFORM"
# Build
echo Run docker-compose run --rm marlin platformio run -e "$PLATFORM" --silent
time docker-compose run --rm marlin platformio run -e "$PLATFORM" --silent

printf "\n\033[0;32mCopying compiled firmware\033[0m\n"
printf "\n\033[0;32mfrom: ${TMP}/.pio/build/${PLATFORM}\033[0m\n"
printf "\n\033[0;32mto: ${OUT}\033[0m\n"

find "$TMP/.pio/build/$PLATFORM" -name "firmware*.bin" -exec cp '{}' "${OUT}" \;

printf "\n\033[0;32mFirmware successfully compiled\033[0m\n"
