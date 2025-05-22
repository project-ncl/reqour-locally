#!/bin/env bash

readonly COMMONS_DIR="../../common"
readonly CONFIGURATIONS_PATH="mounts/configurations"
readonly SECRETS_PATH="mounts/secrets"
readonly CONFIGURATIONS_VOLUME="reqour-adjuster-configurations"
readonly SECRETS_VOLUME="reqour-adjuster-secrets"
readonly MANIPULATORS_VOLUME="reqour-adjuster-manipulators"
readonly REQOUR_NETWORK="reqour-network"

. "${COMMONS_DIR}/library.sh"
. "${COMMONS_DIR}/deploy-library.sh"

readonly DEFAULT_COMPOSE_BACKEND="docker compose"
readonly DEFAULT_IMAGE_TAG=reqour-adjuster
readonly DEFAULT_CONTAINER_NAME=reqour-adjuster
readonly DEFAULT_PORT=8080
readonly DEFAULT_DETACHED_MODE=true
readonly DEFAULT_DEPLOY_DIR="/tmp/reqour/adjuster/deploy"
readonly DEFAULT_ENV_FILENAME=$ENV_VARS_TEMPLATE
readonly DEFAULT_OCI_RUNTIME=podman

function show_usage() {
    echo
    echo "Usage: ./deploy.sh [OPTIONS] [ -- ] COMMAND"
    echo
    echo "OPTIONS:"
    echo "  -h, --help              Show this help usage"
    echo "  -v, --verbose           Verbose output"
    echo "  -b, --compose-backend   Backend for compose. Defaults to '$DEFAULT_COMPOSE_BACKEND'."
    echo "  -t, --image-tag         Image tag of the built image. Defaults to '$DEFAULT_IMAGE_TAG'."
    echo "  -c, --container-name    Container name. Defaults to '$DEFAULT_CONTAINER_NAME'."
    echo "  -p, --port              Port (at host) where to bind the container port. Defaults to '$DEFAULT_PORT'."
    echo "  -m, --detach            Run compose up in detached mode. Defaults to $DEFAULT_DETACHED_MODE."
    echo "  -d, --deploy-dir        Deployment directory containing all the necessary resources, e.g. compose.yaml. Defaults to '$DEFAULT_DEPLOY_DIR'."
    echo "  -e, --env-filename      Environment variables filename within the deploy directory. Defaults to '$DEFAULT_ENV_FILENAME'."
    echo "  -r, --oci-runtime       OCI Runtime used when creating new volumes used by reqour-rest. Defaults to '$DEFAULT_OCI_RUNTIME'."
    echo "  -l, --local-jar         Location of the local JAR you want mount to the volume. This can be useful in case you want to try your locally freshly built local JAR."
    echo
    echo "COMMAND:"
    echo "  template PROFILE        Create a template (with TODOs to be changed) for the given profile."
    echo "  import-volumes          Import all the needed deployment resources into volumes (creates the volumes if not exist)."
    echo "  up                      Create compose file and run the container."
    echo "  down                    Stop the container, delete the compose file."
    echo
    echo "PROFILE:"
    echo "  devel                   Development environment"
    echo "  stage                   Stage environment"
    echo "  prod                    Prod environment"
    echo
}

function parse_options() {
    local readonly OPTIONS="$(getopt -o hvc:t:p:m:d:e:r:l: --long help,verbose,container-name:,image-tag:,port:,--detach,deploy-dir:,env-file:,oci-runtime:,local-jar: -n 'deploy.sh' -- "$@")"
    eval set -- "$OPTIONS"

    HELP=false
    VERBOSE=false
    COMPOSE_BACKEND="$DEFAULT_COMPOSE_BACKEND"
    CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
    IMAGE_TAG="$DEFAULT_IMAGE_TAG"
    PORT=$DEFAULT_PORT
    DETACHED_MODE=$DEFAULT_DETACHED_MODE
    DEPLOY_DIR=$DEFAULT_DEPLOY_DIR
    ENV_FILENAME="$DEFAULT_ENV_FILENAME"
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
            -b | --compose-backend)
                COMPOSE_BACKEND="$2"
                shift 2
                ;;
            -t | --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -c | --container-name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            -p | --port)
                PORT="$2"
                shift 2
                ;;
            -m | --detach)
                DETACHED_MODE="$2"
                shift 2
                ;;
            -d | --deploy-dir)
                DEPLOY_DIR="${2%/}"
                shift 2
                ;;
            -e | --env-file)
                if [[ "$2" == *"/"* ]]; then
                    echo 2>&1 "Environment filename should be just a name within the deployment directory, i.e., it should not be a path."
                else
                    ENV_FILENAME="$2"
                fi
                shift 2
                ;;
            -r | --oci-runtime)
                OCI_RUNTIME="$2"
                shift 2
                ;;
            -l | --local-jar)
                LOCAL_JAR="$2"
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
    echo_if_verbose "   Compose backend: '$COMPOSE_BACKEND'"
    echo_if_verbose "   Image tag: '$IMAGE_TAG'"
    echo_if_verbose "   Container name: '$CONTAINER_NAME'"
    echo_if_verbose "   Port: '$PORT'"
    echo_if_verbose "   Detached mode: '$DETACHED_MODE'"
    echo_if_verbose "   Deployment directory: '$DEPLOY_DIR'"
    echo_if_verbose "   Environment variables file: '$ENV_FILENAME'"
    echo_if_verbose "   OCI Runtime: '$OCI_RUNTIME'"
    if [[ -n $LOCAL_JAR ]]; then
        echo_if_verbose "   Local JAR: '$LOCAL_JAR'"
    fi

    ARGUMENTS="$@"
}

function generate_configurations_mount() {
    CONFIGURATIONS_MOUNT="${DEPLOY_DIR}/${CONFIGURATIONS_PATH}"
    create_mount $CONFIGURATIONS_MOUNT
    pushd "${CONFIGURATIONS_PATH}"
    copy_files_to_mount "." "${CONFIGURATIONS_MOUNT}"
    popd
}

function generate_secrets_mount() {
    REQOUR_SECRETS_MOUNT="${DEPLOY_DIR}/${SECRETS_PATH}/reqour-${PROFILE}"
    create_mount $REQOUR_SECRETS_MOUNT
    pushd "${SECRETS_PATH}/reqour-profile/"
    copy_files_to_mount "." "${REQOUR_SECRETS_MOUNT}"
    popd
}

function generate_deployment_resources() {
    create_deploy_dir
    generate_env_file
    generate_configurations_mount
    generate_secrets_mount
}

function are_todos_resolved() {
    echo_if_verbose "Checking whether all the TODOs are resolved..."
    local readonly TODOS_HUNTER="${COMMONS_DIR}/todos-hunter.sh"
    eval "$TODOS_HUNTER $DEPLOY_DIR"
    return $?
}

function create_volumes_if_not_exist() {
    create_volume_if_not_exist $CONFIGURATIONS_VOLUME
    create_volume_if_not_exist $SECRETS_VOLUME
    create_volume_if_not_exist $MANIPULATORS_VOLUME
}

function import_into_volumes() {
    readonly VOLUME_IMPORTER="${COMMONS_DIR}/volume-importer.sh"
    [[ "$VERBOSE" == true ]] && readonly verbose_flag=" -v" || readonly verbose_flag=""

    ${VOLUME_IMPORTER}${verbose_flag} $CONFIGURATIONS_VOLUME ${DEPLOY_DIR}/${CONFIGURATIONS_PATH}
    ${VOLUME_IMPORTER}${verbose_flag} $SECRETS_VOLUME ${DEPLOY_DIR}/${SECRETS_PATH}
}

function generate_compose_file() {
    pushd "$DEPLOY_DIR"
    if [[ -n $LOCAL_JAR ]]; then
        readonly local_jar_mounting="      - ${LOCAL_JAR}:/opt/reqour/reqour-adjuster-runner.jar:ro,Z"
    fi

    cat > ${COMPOSE_FILE} <<EOF
---
services:
  reqour-adjuster:
    container_name: $CONTAINER_NAME
    image: $IMAGE_TAG
    ports:
      - '${PORT}:8080'
    env_file:
      - $ENV_FILENAME
    volumes:
      - source: $CONFIGURATIONS_VOLUME
        target: /mnt/configurations
        type: volume
      - source: $SECRETS_VOLUME
        target: /mnt/secrets
        type: volume
      - ${MANIPULATORS_VOLUME}:/mnt/manipulators:Z
${local_jar_mounting}
    networks:
      - $REQOUR_NETWORK
volumes:
  $CONFIGURATIONS_VOLUME:
    external: true
  $SECRETS_VOLUME:
    external: true
  $MANIPULATORS_VOLUME:
    external: true
networks:
  ${REQOUR_NETWORK}:
    external: true
EOF

    echo_if_verbose "Generated compose file is: "
    echo_if_verbose "$(cat ${COMPOSE_FILE})"
    popd
}

function run_subcommand() {
    echo_if_verbose "Parsing the following arguments: '$@'"

    readonly COMPOSE_FILE="compose.yaml"

    if [[ $# -eq 2 && $1 == "template" && ($2 == "devel" || $2 == "stage" || $2 == "prod") ]]; then
        PROFILE=$2
        generate_deployment_resources
    elif [[ $# -eq 1 && $1 == "import-volumes" ]]; then
        are_todos_resolved
        if [[ $? -eq 0 ]]; then
            echo 2>&1 "###############################################################"
            echo 2>&1 "# Paste correct values for all the TODOs, and then try again! #"
            echo 2>&1 "###############################################################"
            exit 1
        else
            echo_if_verbose "All the TODOs are resolved, importing.."
        fi
        create_volumes_if_not_exist
        import_into_volumes
    elif [[ $# -eq 1 && $1 == "up" ]]; then
        generate_compose_file
        create_network_if_not_exist $REQOUR_NETWORK
        compose_up
    elif [[ $# -eq 1 && $1 == "down" ]]; then
        compose_down
        delete_compose_file_if_exist
    else
        show_usage
        exit 1
    fi

}

function main() {
    parse_options "$@"

    if [ "$HELP" = true ]; then
        show_usage
        exit 0
    fi

    run_subcommand $ARGUMENTS
}

main "$@"

