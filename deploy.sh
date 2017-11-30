#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

# From https://gist.github.com/domenic/ec8b0fc8ab45f39403dd

echo "[TRACE] TRAVIS_BRANCH: $TRAVIS_BRANCH"
echo "[TRACE] TRAVIS_PULL_REQUEST_BRANCH: $TRAVIS_PULL_REQUEST_BRANCH"
echo "[TRACE] TRAVIS_PULL_REQUEST: $TRAVIS_PULL_REQUEST"

SOURCE_BRANCH="$TRAVIS_PULL_REQUEST_BRANCH"
TARGET_BRANCH="$TRAVIS_PULL_REQUEST-$TRAVIS_PULL_REQUEST_BRANCH"

if [ "$TRAVIS_PULL_REQUEST" = "false" -a "$TRAVIS_BRANCH" != "master" ]; then
   echo "[ABORT] We're in a push build (not in master nor in a pull request), so exiting. "
   exit 0
fi

if [ "$TRAVIS_PULL_REQUEST" != "false" -a "$TRAVIS_PULL_REQUEST_BRANCH" = "master" ]; then
   echo "[ERROR] We're in a pull request but we're in the master branch?!?!"
   echo " This shouldn't happen..."
   exit 1
fi

if [ "$TRAVIS_PULL_REQUEST" = "false"  -a "$SOURCE_BRANCH" = "master" ]; then
  SOURCE_BRANCH="master"
  TARGET_BRANCH="gh-pages"
fi

echo "[TRACE] SOURCE_BRANCH: $SOURCE_BRANCH"
echo "[TRACE] TARGET_BRANCH: $TARGET_BRANCH"

# Save some useful information
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`

# Clone the existing gh-pages for this repo into out/
# Create a new empty branch if the target branch doesn't exist yet (should only happen on first deply)
git clone $REPO out
cd out
git checkout $TARGET_BRANCH || git checkout --orphan $TARGET_BRANCH
cd ..

# Clean out existing contents
rm -rf out/**/* || exit 0

# Copy content from build into  existing contents

echo "[TRACE] Building the specification"
cd spec
ant build

# Make sure we're in the right directory

echo "[TRACE] Copying the specification and cleaning out"

cp -R build/* ../out/

cd ../out

rm .travis.yml
rm w3c.json
rm -rf spec
rm -rf .gitfilters

# Useful additional information

echo "\nNote:" >>README.md

echo "\nThis branch was automatically built from $SOURCE_BRANCH" >>README.md

if [ "$TRAVIS_PULL_REQUEST_SHA" != "" ]; then
  echo "\nusing commit $TRAVIS_PULL_REQUEST_SHA" >>README.md
fi

# Now let's go have some fun with the cloned repo
cd ../out
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

# If there are no changes to the compiled out (e.g. this is a README update) then just bail.
if git diff --quiet; then
    echo "No changes to the output on this push; exiting."
    exit 0
fi

# Commit the "changes", i.e. the new version.
# The delta will show diffs between new and old versions.
git add -A .
git commit -m "Deploy to $TARGET_BRANCH: ${SHA}"

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in ../deploy_key.enc -out ../deploy_key -d
chmod 600 ../deploy_key
eval `ssh-agent -s`
ssh-add ../deploy_key

# Now that we're all set up, we can push.
echo "Ready to push"
git push $SSH_REPO $TARGET_BRANCH
