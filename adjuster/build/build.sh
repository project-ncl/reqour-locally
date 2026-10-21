#!/bin/env bash

readonly PARENT_IMAGE="quay.io\/rh-newcastle\/pnc-rhel-8-reqour"
readonly COMMONS_DIR="../../common"

. "${COMMONS_DIR}/library.sh"
. "${COMMONS_DIR}/build-library.sh"

readonly DEFAULT_OCI_RUNTIME=podman
readonly DEFAULT_IMAGE_TAG=reqour-adjuster
readonly DEFAULT_BUILD_DIR="/tmp/reqour/adjuster/build"
readonly DEFAULT_BUILD_ARGS_FILE=$TEMPLATE_BUILD_ARGS_FILE

function show_usage() {
    echo
    echo "Usage: ./build.sh [OPTIONS] [ -- ] ARGUMENTS"
    echo
    echo "OPTIONS:"
    echo "  -h, --help              Show this help usage"
    echo "  -v, --verbose           Verbose output"
    echo "  -r, --oci-runtime       OCI runtime to be used to build the image. Defaults to '$DEFAULT_OCI_RUNTIME'."
    echo "  -t, --image-tag         Image tag of the built image. Defaults to '$DEFAULT_IMAGE_TAG'."
    echo "  -a, --build-args-file   Build Arguments file (with relative path to context direcotry). Defaults to '$DEFAULT_BUILD_ARGS_FILE'."
    echo "  -b, --build-dir         Build Directory containing e.g. Build Arguments file. Defaults to '$DEFAULT_BUILD_DIR'."
    echo "  -l, --local-jar-dir     Local directory (relative to context) containing the adjuster JAR. If specified, the JAR is COPY-ed from there instead of being downloaded."

    echo
    echo "ARGUMENTS:"
    echo "  1                       Context directory for the build"
    echo
}

function parse_options() {
    echo_if_verbose "Parsing the following options: $@"

    local readonly OPTIONS="$(getopt -o hvr:t:a:b:l: --long help,verbose,oci-runtime:,image-tag:,build-args-file:,build-dir:,local-jar-dir: -n 'build.sh' -- "$@")"
    eval set -- "$OPTIONS"

    HELP=false
    VERBOSE=false
    OCI_RUNTIME=$DEFAULT_OCI_RUNTIME
    IMAGE_TAG=$DEFAULT_IMAGE_TAG
    BUILD_ARGS_FILE=$DEFAULT_BUILD_ARGS_FILE
    BUILD_DIR=${DEFAULT_BUILD_DIR}
    LOCAL_JAR_DIR=""

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
            -l | --local-jar-dir)
                LOCAL_JAR_DIR="$2"
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
    echo_if_verbose "   Image Tag: '$IMAGE_TAG'"
    echo_if_verbose "   Build Args File: '$BUILD_ARGS_FILE'"
    echo_if_verbose "   Build Directory: '$BUILD_DIR'"
    echo_if_verbose "   Local JAR Directory: '$LOCAL_JAR_DIR'"

    ARGUMENTS="$@"
}

function parse_arguments() {
    echo_if_verbose "Parsing the following arguments: '$@'"

    if [[ -z $@ || $# -ne 1 ]]; then
        echo 2>&1 "Expecting exactly a single argument - context of the build, but got: '$@'."
        show_usage
        exit 1
    fi

    readonly CONTEXT_DIR="$1"
}

function are_todos_resolved() {
    echo_if_verbose "Checking whether all the TODOs are resolved..."
    eval $TODOS_HUNTER "${BUILD_DIR}/${BUILD_ARGS_FILE}"
    return $?
}

function backup_containerfile() {
    if [[ ! -e $CONTAINERFILE_ORIGINAL ]]; then
        copy_cmd="cp $CONTAINERFILE $CONTAINERFILE_ORIGINAL"
        echo_if_verbose "Going to run the command: '$copy_cmd' (in the directory: '$PWD')"
        eval "$copy_cmd"
    fi
}

function adjust_containerfile() {
    search_string="image-from-config"
    search_cmd="cat $CONTAINERFILE | grep -q $search_string"
    echo_if_verbose "Seaching the string '$search_string' in the $CONTAINERFILE by running the command: '$search_cmd'"
    eval "$search_cmd"

    if [[ $? -eq 0 ]]; then
        backup_containerfile
        sed -i 's/'${search_string}'/'${PARENT_IMAGE}'/g' "$CONTAINERFILE"
    fi

    if [[ -n "$LOCAL_JAR_DIR" ]]; then
        backup_containerfile

        local reqour_adjuster_jar="$(grep -E '^REQOUR_ADJUSTER_JAR=' "${BUILD_DIR}/${BUILD_ARGS_FILE}" | head -n1 | cut -d= -f2 | awk '{print $1}')"
        echo_if_verbose "Copying the adjuster JAR '${LOCAL_JAR_DIR}/${reqour_adjuster_jar}' into the build context under '${reqour_adjuster_jar}'"
        cp "${LOCAL_JAR_DIR}/${reqour_adjuster_jar}" "${reqour_adjuster_jar}"
        COPIED_JAR="${reqour_adjuster_jar}"

        local replacement="COPY \${REQOUR_ADJUSTER_JAR} \${REQOUR_ADJUSTER_JAR}"
        echo_if_verbose "Replacing the adjuster JAR download line with: '$replacement'"
        sed -i "s|^RUN curl -kfo \$REQOUR_ADJUSTER_JAR \$REQOUR_ADJUSTER_URL/\$REQOUR_ADJUSTER_JAR\$|${replacement}|" "$CONTAINERFILE"
    fi

    if [[ "$VERBOSE" == true ]]; then
        echo_if_verbose "Adjuster $CONTAINERFILE is:"
        cat $CONTAINERFILE
    fi
}

function rollback_changes() {
    if [[ -e $CONTAINERFILE_ORIGINAL ]]; then
        rm $CONTAINERFILE
        mv $CONTAINERFILE_ORIGINAL $CONTAINERFILE
    fi

    if [[ -n "$COPIED_JAR" && -e "$COPIED_JAR" ]]; then
        echo_if_verbose "Removing the adjuster JAR '$COPIED_JAR' copied into the build context"
        rm "$COPIED_JAR"
    fi
}

function build_the_image() {
    pushd "$CONTEXT_DIR"

    readonly COMMAND="${OCI_RUNTIME} build --no-cache -t ${IMAGE_TAG} --build-arg-file="${BUILD_DIR}/${BUILD_ARGS_FILE}" ."
    readonly CONTAINERFILE=Containerfile
    readonly CONTAINERFILE_ORIGINAL="${CONTAINERFILE}-original"

    adjust_containerfile
    echo_if_verbose "Going to run a command: ${COMMAND}"
    eval "${COMMAND}"
    rollback_changes

    popd
}

function main() {
    local readonly TODOS_HUNTER="${COMMONS_DIR}/todos-hunter.sh"
    parse_options "$@"

    if [[ "$HELP" == true ]]; then
        show_usage
        exit 0
    fi

    parse_arguments $ARGUMENTS
    create_build_args_copy $BUILD_DIR $BUILD_ARGS_FILE

    are_todos_resolved
    if [[ $? -eq 0 ]]; then
        echo 2>&1 "###############################################################"
        echo 2>&1 "# Paste correct values for all the TODOs, and then try again! #"
        echo 2>&1 "###############################################################"
        exit 1
    else
        echo_if_verbose "All the TODOs are resolved, ready to build"
    fi

    build_the_image
}

main "$@"

