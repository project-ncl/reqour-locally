#!/bin/env bash

readonly TEMPLATE_BUILD_ARGS_FILE=build-args.conf

function create_build_args_copy() {
    BUILD_DIR=$1
    BUILD_ARGS_FILE=$2

    if [[ $# -ne 2 ]]; then
        echo 2>&1 "Expected 2 arguments (build directory, build arguments file), got: '$@'"
    fi

    if [[ ! -e "${BUILD_DIR}/${BUILD_ARGS_FILE}" ]]; then
        if [[ ! -e $BUILD_DIR ]]; then
            echo_if_verbose "Creating the directory: $BUILD_DIR"
            mkdir -p "$BUILD_DIR"
        fi
        cp $TEMPLATE_BUILD_ARGS_FILE "${BUILD_DIR}/${BUILD_ARGS_FILE}"
    fi
}

