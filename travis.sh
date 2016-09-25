#!/bin/bash

set -uexo pipefail

if [ "$TRAVIS_OS_NAME" == osx ]; then
    profile="vm_stat"
else
    profile="vmstat -s"
fi
date && $profile

# add missing cc link in gdc-4.9.3 download
if [ $DC = gdc ] && [ ! -f $(dirname $(which gdc))/cc ]; then
    ln -s gcc $(dirname $(which gdc))/cc
fi
N=2

# clone druntime and phobos
clone() {
    local url="$1"
    local path="$2"
    local branch="$3"
    for i in {0..4}; do
        if git clone --depth=1 --branch "$branch" "$url" "$path"; then
            break
        elif [ $i -lt 4 ]; then
            sleep $((1 << $i))
        else
            echo "Failed to clone: ${url}"
            exit 1
        fi
    done
}

# build dmd, druntime, phobos
build() {
    make -j$N -C src -f posix.mak MODEL=$MODEL HOST_DMD=$DMD ENABLE_RELEASE=1 all
    make -j$N -C src -f posix.mak MODEL=$MODEL HOST_DMD=$DMD dmd.conf
    make -j$N -C ../druntime -f posix.mak MODEL=$MODEL
    make -j$N -C ../phobos -f posix.mak MODEL=$MODEL
}

# self-compile dmd
rebuild() {
    mv src/dmd src/host_dmd
    make -j$N -C src -f posix.mak MODEL=$MODEL HOST_DMD=./host_dmd clean
    make -j$N -C src -f posix.mak MODEL=$MODEL HOST_DMD=./host_dmd dmd.conf
    make -j$N -C src -f posix.mak MODEL=$MODEL HOST_DMD=./host_dmd ENABLE_RELEASE=1 all
}

# test druntime, phobos, dmd
test() {
    make -j$N -C ../druntime -f posix.mak MODEL=$MODEL unittest
    make -j$N -C ../phobos -f posix.mak MODEL=$MODEL unittest
    test_dmd
}

# test dmd
test_dmd() {
    # test fewer compiler argument permutations for PRs to reduce CI load
    if [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_OS_NAME" == "linux"  ]; then
        make -j$N -C test MODEL=$MODEL # all ARGS by default
    else
        make -j$N -C test MODEL=$MODEL ARGS="-O -inline -release"
    fi
}

for proj in druntime phobos; do
    if [ $TRAVIS_BRANCH != master ] && [ $TRAVIS_BRANCH != stable ] &&
           ! curl -fsSLI https://api.github.com/repos/dlang/$proj/branches/$TRAVIS_BRANCH; then
        # use master as fallback for other repos to test feature branches
        clone https://github.com/dlang/$proj.git ../$proj master
    else
        clone https://github.com/dlang/$proj.git ../$proj $TRAVIS_BRANCH
    fi
done

build
date && $profile
test
date && $profile
rebuild
date && $profile
rebuild
date && $profile
test_dmd
date && $profile
