#!/bin/env bash

readonly DEFAULT_OCI_RUNTIME=podman
readonly DEFAULT_IMAGE_TAG=reqour-rest
readonly DEFAULT_BUILD_DIR="/tmp/reqour-rest/build"
readonly DEFAULT_BUILD_ARGS_FILE=build-args.conf

function show_usage() {
    echo "./build.sh [OPTIONS] [ -- ] ARGUMENTS"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help              Show this help usage"
    echo "  -v, --verbose           Verbose output"
    echo "  -r, --oci-runtime       OCI runtime to be used to build the image. Defaults to '$DEFAULT_OCI_RUNTIME'."
    echo "  -t, --image-tag         Image tag of the built image. Defaults to '$DEFAULT_IMAGE_TAG'."
    echo "  -a, --build-args-file   Build Arguments file (with relative path to context direcotry). Defaults to '$DEFAULT_BUILD_ARGS_FILE'."
    echo "  -b, --build-dir         Build Directory containing e.g. Build Arguments file. Defaults to '$DEFAULT_BUILD_DIR'."

    echo ""
    echo "ARGUMENTS:"
    echo "  1                       Context directory for the build"
}

function echo_if_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "$@"
    fi
}

function parse_options() {
    echo_if_verbose "Parsing the following options: $@"

    local readonly OPTIONS="$(getopt -o hvr:t:a:b: --long help,verbose,oci-runtime:,image-tag:,build-args-file:,build-dir: -n 'build.sh' -- "$@")"
    eval set -- "$OPTIONS"

    HELP=false
    VERBOSE=false
    OCI_RUNTIME=$DEFAULT_OCI_RUNTIME
    IMAGE_TAG=$DEFAULT_IMAGE_TAG
    BUILD_ARGS_FILE=$DEFAULT_BUILD_ARGS_FILE
    BUILD_DIR=${DEFAULT_BUILD_DIR}

    while true; do
        case $1 in
            -h | --help)
                HELP=true
                break
                ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -r | --oci-runtime)
                OCI_RUNTIME="$2"
                shift 2
                ;;
            -t | --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -a | --build-args-file)
                BUILD_ARGS_FILE="$2"
                shift 2
                ;;
            -b | --build-dir)
                BUILD_DIR="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo 2>&1 "Invalid option ($1) given"
                show_usage
                exit 1
                ;;
        esac
    done

    echo_if_verbose "Parsing of options successfully ended, the following options will be used:"
    echo_if_verbose "   OCI runtime: '$OCI_RUNTIME'"
    echo_if_verbose "   image tag: '$IMAGE_TAG'"
    echo_if_verbose "   build args file: '$BUILD_ARGS_FILE'"
    echo_if_verbose "   build directory: '$BUILD_DIR'"

    ARGUMENTS="$@"
}

function parse_arguments() {
    echo_if_verbose "Parsing the following arguments: $@"

    if [[ -z $@ || $# -ne 1 ]]; then
        echo 2>&1 "Expecting exactly a single argument - context of the build, but got: '$@'."
        show_usage
        exit 1
    fi

    readonly CONTEXT_DIR="$1"
}

function create_build_args_copy() {
    if [[ ! -e "${BUILD_DIR}/${BUILD_ARGS_FILE}" ]]; then
        if [[ ! -e $BUILD_DIR ]]; then
            echo_if_verbose "Creating the directory: $BUILD_DIR"
            mkdir -p "$BUILD_DIR"
        fi
        cp build-args.conf "${BUILD_DIR}/${BUILD_ARGS_FILE}"
    fi
}

function main() {
    local readonly TODOS_HUNTER="../../common/todos-hunter.sh"
    parse_options "$@"
    parse_arguments "$ARGUMENTS"

    if [[ "$HELP" == true ]]; then
        show_usage
        exit 0
    fi

    create_build_args_copy

    echo "Checking whether all the TODOs are resolved..."
    $TODOS_HUNTER "${BUILD_DIR}/${BUILD_ARGS_FILE}"
    if [[ $? -eq 0 ]]; then
        echo 2>&1 "Paste correct values for all the TODOs, and then try again"
        exit 1
    fi

    COMMAND="${OCI_RUNTIME} build -t ${IMAGE_TAG} --build-arg-file="${BUILD_DIR}/${BUILD_ARGS_FILE}" ${CONTEXT_DIR}"
    echo "Going to run a command: ${COMMAND}"
    ${COMMAND}
}

main "$@"

