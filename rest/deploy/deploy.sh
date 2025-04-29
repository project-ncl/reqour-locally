#!/bin/env bash

readonly DEFAULT_COMPOSE_BACKEND="docker compose"
readonly DEFAULT_IMAGE_TAG=reqour-rest
readonly DEFAULT_CONTAINER_NAME=reqour-rest
readonly DEFAULT_PORT=8080
readonly DEFAULT_DETACHED_MODE=true
readonly DEFAULT_DEPLOY_DIR="/tmp/reqour-rest/deploy"
readonly DEFAULT_ENV_FILENAME=env-vars.conf
readonly DEFAULT_OCI_RUNTIME=podman

function show_usage() {
    echo
    echo "./build.sh [OPTIONS] [ -- ] COMMAND"
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
    echo
    echo "COMMAND:"
    echo "  up PROFILE              Compose up (among others, creates podman volumes (if not already exist) and everything needed for the deployment (e.g. compose file, application.yaml, etc.))"
    echo "  down                    Compose down (among others, deletes the container and the compose file, i.e., nothing except that is deleted (e.g. podman volumes))"
    echo
    echo "PROFILE:"
    echo "  devel                   Development environment"
    echo "  stage                   Stage environment"
    echo "  prod                    Prod environment"
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
                shift
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
                DEPLOY_DIR="$2"
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

    ARGUMENTS="$@"
}

function create_volume_if_not_exist() {
    $OCI_RUNTIME volume ls | grep -q $1
    if [[ $? -eq 0 ]]; then
        echo_if_verbose "Volume '$1' already exists, not creating anything."
    else
        echo_if_verbose "Creating $OCI_RUNTIME volume '$1'"
        $OCI_RUNTIME volume create $1
    fi
}

function create_volumes_if_not_exist() {
    create_volume_if_not_exist reqour-rest-configurations
    create_volume_if_not_exist reqour-rest-secrets
}

function create_deploy_dir() {
    if [[ -e $DEPLOY_DIR ]]; then
        echo_if_verbose "Deploy directory '$DEPLOY_DIR' already exists, not creating anything (in case you want to create a new one, either delete the current one, or specify new deploy directory as an -d/--deploy-dir option)."
    else
        echo_if_verbose "Creating the deploy dir: $DEPLOY_DIR"
        mkdir -p "$DEPLOY_DIR"
    fi
}

function generate_compose_file() {
    pushd "$DEPLOY_DIR"
    cat > ${COMPOSE_FILE} <<EOF
---
services:
  reqour-rest:
    container_name: $CONTAINER_NAME
    image: $IMAGE_TAG
    ports:
      - '${PORT}:8080'
    env_file:
      - $ENV_FILENAME
    volumes:
      - source: reqour-rest-secrets
        target: /mnt/secrets
        type: bind
      - source: reqour-rest-configurations
        target: /mnt/configurations
        type: bind
EOF

    echo_if_verbose "Generated compose file is: "
    echo_if_verbose "$(cat ${COMPOSE_FILE})"
    popd
}

function generate_env_file() {
    ENV_FILE="${DEPLOY_DIR}/${ENV_FILENAME}"
    if [[ -e "$ENV_FILE" ]]; then
        echo_if_verbose "'$ENV_FILE' already exists, not creating anything (in case you want to create a new one, delete the previous one, or specify new location using -d/-e options)."
    else
        cp env-vars.conf "$ENV_FILE"
        sed -i 's|${PROFILE}|'${PROFILE}'|g' "$ENV_FILE"
    fi
}

function create_mount() {
    if [[ $# -ne 1 ]]; then
        echo_if_verbose "Expecting exactly 1 argument (mount path to create if not already exist), but got: '$@'"
        exit 1
    fi

    MOUNT_PATH="$1"

    if [[ -e $MOUNT_PATH ]]; then
        echo_if_verbose "'$MOUNT_PATH' already exists, not creating a new one (in case you want to create a new one, delete the previous one, or specify new location using the -d option)."
    else
        mkdir -p "$MOUNT_PATH"
    fi
}

function create_configurations_mount() {
    CONFIGURATIONS_PATH="mounts/configurations"
    CONFIGURATIONS_MOUNT="${DEPLOY_DIR}/${CONFIGURATIONS_PATH}"
    create_mount $CONFIGURATIONS_MOUNT
}

function create_secrets_mount() {
    SECRETS_PATH="mounts/secrets"
    SECRETS_MOUNT="${DEPLOY_DIR}/${SECRETS_PATH}/reqour-${PROFILE}"
    create_mount $SECRETS_MOUNT
}

function generate_application_yaml_file() {
    create_configurations_mount

    APPLICATION_YAML="${CONFIGURATIONS_MOUNT}/application.yaml"
    if [[ -e $APPLICATION_YAML ]]; then
        echo_if_verbose "'$APPLICATION_YAML' already exists, not creating a new one (in case you want to create a new one, delete the previous one, or specify new location using the -d option)."
    else
        cp "${CONFIGURATIONS_PATH}/application.yaml" "$APPLICATION_YAML"
    fi
}

function generate_secrets() {
    create_secrets_mount

    if [[ -z $(ls -A "$SECRETS_MOUNT") ]]; then
        echo_if_verbose "'${SECRETS_MOUNT}' is empty, generating secrets"
        cp "${SECRETS_PATH}/"* "${SECRETS_MOUNT}"
    else
        echo_if_verbose "'${SECRETS_MOUNT}' is not empty, skipping secrets generation"
    fi
}

function generate_deployment_resources() {
    create_deploy_dir
    generate_compose_file
    generate_env_file
    generate_application_yaml_file
    generate_secrets
}

function compose_up() {
    local readonly compose_up_cmd="$COMPOSE_BACKEND up --detach=${DETACHED_MODE}"
    echo_if_verbose "Going to run a command: $compose_up_cmd"
    pushd "$DEPLOY_DIR"
    ${compose_up_cmd}
    popd
}

function compose_down() {
    local readonly compose_down_cmd="$COMPOSE_BACKEND down"
    echo_if_verbose "Going to run a command: $compose_down_cmd"
    pushd "$DEPLOY_DIR"
    ${compose_down_cmd}
    popd
}

function delete_compose_file() {
    rm "${DEPLOY_DIR}/${COMPOSE_FILE}"
}

function run_subcommand() {
    echo_if_verbose "Parsing the following arguments: $@"

    if [[ ! (($# -eq 2 && $1 == "up" && ($2 == "devel" || $2 == "stage" || $2 == "prod")) || ($# -eq 1 && $1 == "down")) ]]; then
        echo 2>&1 "Expecting up PROFILE | down as arguments, got: "$@""
        exit 1
    fi

    readonly COMPOSE_FILE="compose.yaml"

    if [[ "$1" == "up" ]]; then
        PROFILE="$2"
        create_volumes_if_not_exist
        generate_deployment_resources

        echo_if_verbose "Checking whether all the TODOs are resolved..."
        $TODOS_HUNTER "$DEPLOY_DIR"
        if [[ $? -eq 0 ]]; then
            echo 2>&1 "##############################################################"
            echo 2>&1 "# Paste correct values for all the TODOs, and then try again #"
            echo 2>&1 "##############################################################"
            exit 1
        fi

        compose_up
    else
        compose_down
        delete_compose_file
    fi
}

function main() {
    local readonly TODOS_HUNTER="../../common/todos-hunter.sh"
    parse_options "$@"

    if [ "$HELP" = true ]; then
        show_usage
    fi

    run_subcommand $ARGUMENTS
}

main "$@"

