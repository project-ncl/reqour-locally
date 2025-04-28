#!/bin/env bash

#######
# Args
#######

# List of directories and files:
#   if it's a file: just try to find 'TODO' occurrence in there
#   if it's a directory: proceed for every file, in case of another directory in there, proceeds recursively
# Note: skipping .git directories
readonly DIRS_FILES=${@:-.}

readonly RED='\033[0;31m'
readonly NO_COLOR='\033[0m'
readonly GREP_OUT=/tmp/todos-hunter-out

TODO_FOUND=1

function file_hunt() {
    if [ ! -f $1 ]; then
        # skip what's not a file
        return
    fi

    cat $1 | grep -iE ".*=?\s*TODO.*" > $GREP_OUT
    if [ $? -eq 0 ]; then
        printf "$1: ${RED}$(cat ${GREP_OUT})${NO_COLOR}\n"
        TODO_FOUND=$(( $TODO_FOUND * 0 ))
    fi
}

for dir_file in $DIRS_FILES; do
    if [ -d $dir_file ]; then
        for file in $(find $dir_file ! -path '*.git*'); do
            file_hunt $file
        done
    elif [ -f $dir_file ]; then
        file_hunt $dir_file
    else
        echo 2>&1 "'$dir_file' is neither a file nor a directory, skipping"
    fi
done

exit $TODO_FOUND

