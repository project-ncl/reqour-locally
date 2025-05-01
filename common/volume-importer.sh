#!/bin/env bash

readonly DEFAULT_OCI_RUNTIME=podman

function show_usage() {
    echo
    echo "Usage: ./volume-importer.sh [OPTIONS] [--] ARGUMENTS"
    echo
    echo "OPTIONS:"
    echo "  -r, --oci-runtime   OCI Runtime used when creating new volumes used by reqour-rest. Defaults to '$DEFAULT_OCI_RUNTIME'."
    echo
    echo "ARGUMENTS:"
    echo "  1                   Volume name"
    echo "  2                   Directory at host, from which to tar (i.e., root directory, from which we tar)"
    echo
}

function echo_if_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "$@"
    fi
}

function parse_options() {
    echo_if_verbose "Parsing the following options: $@"

    local readonly OPTIONS="$(getopt -o hvc:t:p:m:d:e:r: --long help,verbose,container-name:,image-tag:,port:,--detach,deploy-dir:,env-file:,oci-runtime: -n 'deploy.sh' -- "$@")"
    eval set -- "$OPTIONS"

    HELP=false
    VERBOSE=false
    OCI_RUNTIME=$DEFAULT_OCI_RUNTIME

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
    echo_if_verbose "   OCI Runtime: '$OCI_RUNTIME'"

    ARGUMENTS="$@"
}

function does_volume_exists() {
    search_volume_cmd="$OCI_RUNTIME volume ls | grep -q $VOLUME_NAME"
    echo_if_verbose "Going to run the command: '$search_volume_cmd'"
    eval "${search_volume_cmd}"
    return $?
}

function create_tar() {
    TAR_CMD="tar czvf $TAR_ARTIFACT ."
    pushd $TAR_ROOT_DIR
    echo_if_verbose "Going to run the command: '$TAR_CMD' in the directory '$PWD'"
    $TAR_CMD
    popd
}

function import_tar_into_volume() {
    IMPORT_CMD="$OCI_RUNTIME volume import $VOLUME_NAME $TAR_ARTIFACT"
    echo_if_verbose "Going to run the command: '$IMPORT_CMD'"
    ${IMPORT_CMD}
}

function import() {
    echo_if_verbose "Running import with the following arguments: $@"

    if [[ $# -ne 2 ]]; then
        show_usage
        exit 1
    fi

    readonly VOLUME_NAME=$1
    readonly TAR_ROOT_DIR=$2


    does_volume_exists $1
    if [[ $? -ne 0 ]]; then
        echo 2>&1 "The volume '$VOLUME_NAME' does not exist"
        exit 1
    fi

    if [[ ! -e $2 ]]; then
        echo 2>&1 "The directory '$TAR_ROOT_DIR' does not exist"
        exit 1
    fi

    readonly TAR_ARTIFACT="/tmp/volume.gz.tar"
    create_tar $TAR_ROOT_DIR
    import_tar_into_volume $VOLUME_NAME

    if [[ -e $TAR_ARTIFACT ]]; then
        rm $TAR_ARTIFACT
    fi
}

function main() {
    parse_options "$@"

    if [ "$HELP" = true ]; then
        show_usage
        exit 0
    fi

    import $ARGUMENTS
}

main "$@"
echo_if_verbose "Volume importer ends"

