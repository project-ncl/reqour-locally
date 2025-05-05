#!/bin/env bash

function echo_if_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "$@"
    fi
}

