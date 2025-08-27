#!/bin/env bash

readonly ENV_VARS_TEMPLATE="env-vars.conf"

function create_volume_if_not_exist() {
    VOLUME_NAME=$1

    eval "$OCI_RUNTIME volume ls | grep -q $VOLUME_NAME"
    if [[ $? -eq 0 ]]; then
        echo_if_verbose "Volume '$VOLUME_NAME' already exists, not creating anything."
    else
        echo_if_verbose "Creating $OCI_RUNTIME volume '$VOLUME_NAME'"
        $OCI_RUNTIME volume create $VOLUME_NAME
    fi
}

function create_network_if_not_exist() {
    NETWORK_NAME=$1

    eval "$OCI_RUNTIME network ls | grep -q $NETWORK_NAME"
    if [[ $? -eq 0 ]]; then
        echo_if_verbose "Network '$NETWORK_NAME' already exists, not creating anything."
    else
        echo_if_verbose "Creating $OCI_RUNTIME network '$NETWORK_NAME'"
        eval "$OCI_RUNTIME network create $NETWORK_NAME"
    fi
}

function create_deploy_dir() {
    if [[ -e $DEPLOY_DIR ]]; then
        echo_if_verbose "Deploy directory '$DEPLOY_DIR' already exists, not creating anything (in case you want to create a new one, either delete the current one, or specify new deploy directory using -d/--deploy-dir option)."
    else
        echo_if_verbose "Creating the deploy dir: $DEPLOY_DIR"
        mkdir -p "$DEPLOY_DIR"
    fi
}

function generate_env_file() {
    ENV_FILE="${DEPLOY_DIR}/${ENV_FILENAME}"
    if [[ -e "$ENV_FILE" ]]; then
        echo_if_verbose "'$ENV_FILE' already exists, checking whether it contains all the variables from the template"
        for var in $(cat $ENV_VARS_TEMPLATE | cut -d= -f1); do
          grep --silent $var $ENV_FILE
          if [ $? -ne 0 ]; then
            echo 2>&1 "Variable '$var' is not present in your $ENV_FILE. Add it and re-run again."
            exit 1
          fi
        done
    else
        cp "$ENV_VARS_TEMPLATE" "$ENV_FILE"
        sed -i 's|${PROFILE}|'${PROFILE}'|g' "$ENV_FILE"
    fi
}

function create_mount() {
    MOUNT_PATH="$1"

    if [[ -e $MOUNT_PATH ]]; then
        echo_if_verbose "Mount '$MOUNT_PATH' already exists, not creating a new one (in case you want to create a new one, delete the current one, or specify new location using the -d option)."
    else
        mkdir -p "$MOUNT_PATH"
    fi
}

function copy_files_to_mount() {
    SOURCE_DIR="$1"
    DEST_DIR="$2"

    for source_file in "${SOURCE_DIR%/}/"*; do
      source_file_basename=$(basename $source_file)
      dest_file="${DEST_DIR%/}/$source_file_basename"
      if [[ -e $dest_file ]]; then
        echo_if_verbose "The file '$dest_file' already exists, skipping.."
      else
        cp $source_file $dest_file
      fi
    done
}

function run_compose_cmd() {
    local readonly COMPOSE_CMD="$1"

    echo_if_verbose "Going to run a command: '$COMPOSE_CMD'"
    pushd "$DEPLOY_DIR"
    eval "${COMPOSE_CMD}"
    popd
}

function compose_up() {
    if [[ $DETACHED_MODE == 'true' ]]; then
        # cannot use --detach=$DETACHED_MODE, since podman-compose supports only -d/--detach when one wants to run in detached mode
        run_compose_cmd "$COMPOSE_BACKEND up --detach"
    else
        run_compose_cmd "$COMPOSE_BACKEND up"
    fi
}

function compose_down() {
    run_compose_cmd "$COMPOSE_BACKEND down"
}

function delete_compose_file_if_exist() {
    if [[ -e "${DEPLOY_DIR}/${COMPOSE_FILE}" ]]; then
        rm "${DEPLOY_DIR}/${COMPOSE_FILE}"
    fi
}

