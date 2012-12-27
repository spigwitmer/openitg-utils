#!/bin/bash

# Usage: ./gen-arcade-patch [private RSA]
# 
# Generates a full arcade patch from the assets data, then signs the patch
# with the Private.rsa file given on the command line.

# written by vyhd/pat

# work directory - this forms the root dir of the final patch
TMP_DIR="/tmp/.tmp-patch"

# arcade patch data that we copy wholesale to the temp dir
PATCH_DATA_DIR="assets/arcade-patch"

# values that aren't really magical, just used in a few places
OITG_BINARY="src/openitg"
CONFIG_HEADER="src/config.h"

# default to private.rsa in CWD (for the sake of a default value)
PRIVATE_RSA=${1-private.rsa}

# include the simple helper routines
source common.sh

# exit immediately on nonzero exit code
set -e
set -u
# set this for loquacious and slightly redundant verbosity
# set -x

function print_usage
{
	echo "Usage: $0 [private RSA key]"
	exit 0
}

if ! [ -f "$PRIVATE_RSA" ]; then print_usage; fi

# clean up after ourselves on exit
trap "rm -rf $TMP_DIR" EXIT
trap "echo \"Failed! \"" ERR

#
# see if we have all the functions and files we need here
#

echo "Checking dependencies..."

has_command javac
has_command java

has_file "$OITG_BINARY" "%s doesn't exist! Please build it."
has_file "$CONFIG_HEADER" "Why do you have a binary, but not config.h?"
has_file "$VERIFY_SIG_PATH" "%s is missing; try checking out the repo again?"
has_file "$PRIVATE_RSA" "RSA key \"%s\" not found! (failed sanity check)"

#
# warn the user if the util doesn't exist
has_file "assets/utilities/itg2-util/src/itg2ac-util" "cd assets/utilities/itg2-util && ./autogen.sh && ./configure && make"

#
# build the signature verification program if it hasn't been built
# - we usually make them build our utilities, but this is simple
#

if ! [ -f "${VERIFY_SIG_PATH%.*}.class" ]; then
	echo "SignFile not built yet. building now..."
	cd "$VERIFY_SIG_DIR"
	javac "$VERIFY_SIG_FILE"
	cd -
fi

#
# actually build the patch here
#

OITG_DATE="`date +%m-%d-%Y`"
OITG_VERSION="`git describe`"

if [ $? -ne 0 ]; then
	echo "'git describe' failed! Are you working in a Git repo?"
	exit 1
fi

# sanity check - make sure this build is actually for arcades
set +e

grep "#define ITG_ARCADE 1" "$CONFIG_HEADER" &> /dev/null

if [ $? -ne 0 ]; then
	echo "Your config.h says this isn't an arcade build. Aborting."
	exit 1
fi

set -e

mkdir -p "$TMP_DIR"

echo "Copying base patch data..."
cp -a $PATCH_DATA_DIR/* "$TMP_DIR"

echo "Generating patch.zip..."
./gen-patch-zip.sh "$TMP_DIR/patch.zip" &> /dev/null

echo "Copying and stripping binary..."
cp -L "$OITG_BINARY" "$TMP_DIR"
strip --strip-unneeded "$TMP_DIR/openitg"

echo "Reticulating splines..."

# replace the placeholders in patch.xml with our actual data
sed -r -i -e "s/OITG_VERSION/$OITG_VERSION/g" "$TMP_DIR/patch.xml"
sed -r -i -e "s/OITG_DATE/$OITG_DATE/g" "$TMP_DIR/patch.xml"

echo "Zipping patch data..."

# NOTE: the "ITG 2 " prefix is required for the patches to be seen by itg/openitg
PATCH_OUTPUT_FILE="ITG 2 OpenITG-$OITG_VERSION.itg"
TEMP_SIG_FILE="$TMP_DIR/.sig"

# delete this if it exists, so we don't just "update"
rm -f "$PATCH_OUTPUT_FILE"

CWD="`pwd`"
cd "$TMP_DIR"
zip -r "$CWD/$PATCH_OUTPUT_FILE" * &> /dev/null
cd - &> /dev/null

echo "Signing and appending signature..."

java -classpath $VERIFY_SIG_DIR SignFile "$PATCH_OUTPUT_FILE" "$PRIVATE_RSA" "$TEMP_SIG_FILE"
cat "$TEMP_SIG_FILE" >> "$PATCH_OUTPUT_FILE"

echo "Done: $PATCH_OUTPUT_FILE"
exit 0
