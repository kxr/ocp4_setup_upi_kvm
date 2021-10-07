#!/bin/bash

err() {
    echo; echo;
    echo -e "\e[97m\e[101m[ERROR]\e[0m ${1}"; shift; echo;
    while [[ $# -gt 0 ]]; do
        echo "    ${1}"
        shift
    done
    echo; exit 1;
}

ok() {
    test -z "$1" && echo " ok" || echo " ${1}"
}

check_if_we_can_continue() {
    if [ "${YES}" != "yes" ]; then
        echo; echo;
        while [[ $# -gt 0 ]]; do
            echo "[NOTE] ${1}"
            shift
        done
        echo -n "Press [Enter] to continue, [Ctrl]+C to abort: "; read userinput;
    fi
}

download() {
    # download [check|get] filename url
    test -n "${1}" && cmd="${1}"  || err "Invalid download ${0} ${@}"
    test -n "${2}" && file="${2}" || err "Invalid download ${0} ${@}"
    test -n "${3}" && url="${3}"  || err "Invalid download ${0} ${@}"

    mkdir -p "${CACHE_DIR}"

    if [ "${cmd}" == "check" ]
    then
        if [ -f "${CACHE_DIR}/${file}" ]; then
            echo "(reusing cached file ${file})"
        else
            timeout 10 curl -qs --head --fail "${url}" &> /dev/null && ok || err "${url} not reachable"
        fi
    elif [ "${cmd}" == "get" ]
    then
        if [ "${FRESH_DOWN}" == "yes" -a -f "${CACHE_DIR}/${file}" ]; then
            rm -f "${CACHE_DIR}/${file}" || err "Error removing ${CACHE_DIR}/${file}"
        fi
        if [ -f "${CACHE_DIR}/${file}" ]; then
            echo "(reusing cached file ${file})"
        else
            echo
            wget ${url} -O "${CACHE_DIR}/${file}.part" && mv "${CACHE_DIR}/${file}.part" "${CACHE_DIR}/${file}"
            test -f "${CACHE_DIR}/${file}" || err "Error dowloading ${file} from ${url}"
        fi
    else
        err "Invalid download ${0} ${@}"
    fi
}
