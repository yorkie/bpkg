#!/bin/bash

BPKG_GIT_REMOTE="${BPKG_GIT_REMOTE:-"https://github.com"}"
BPKG_REMOTE="${BPKG_REMOTE:-"https://raw.githubusercontent.com"}"
BPKG_USER="${BPKG_USER:-"bpkg"}"

## outut usage
usage () {
  echo "usage: bpkg-install [-h|--help]"
  echo "   or: bpkg-install [-g|--global] <package>"
  echo "   or: bpkg-install [-g|--global] <user>/<package>"
}

message () {
  if type -f bpkg-term > /dev/null 2>&1; then
    term color "${1}"
  fi

  shift
  printf "    ${1}"
  shift

  if type -f bpkg-term > /dev/null 2>&1; then
    term reset
  fi

  printf ": "

  if type -f bpkg-term > /dev/null 2>&1; then
    term reset
    term bright
  fi

  printf "%s\n" "${@}"

  if type -f bpkg-term > /dev/null 2>&1; then
    term reset
  fi
}

## output error
error () {
  {
    message "red" "error" "${@}"
  } >&2
}

## output warning
warn () {
  {
    message "yellow" "warn" "${@}"
  } >&2
}

## output info
info () {
  local title="info"
  if (( "${#}" > 1 )); then
    title="${1}"
    shift
  fi
  message "cyan" "${title}" "${@}"
}

## Install a bash package
bpkg_install () {
  local pkg="${1}"
  local cwd="`pwd`"
  local user=""
  local name=""
  local url=""
  local uri=""
  local version=""
  local status=""
  local json=""
  local let needs_global=0
  declare -a local parts=()
  declare -a local scripts=()

  case "${pkg}" in
    -h|--help)
      usage
      return 0
      ;;

    -g|--global)
      shift
      needs_global=1
      pkg="${1}"
      ;;
  esac

  ## ensure there is a package to install
  if [ -z "${pkg}" ]; then
    usage
    return 1
  fi

  echo

  ## ensure remote is reachable
  {
    curl -s "${BPKG_REMOTE}"
    if [ "0" != "$?" ]; then
      error "Remote unreachable"
      return 1
    fi
  }

  ## get version if available
  {
    OLDIFS="${IFS}"
    IFS="@"
    parts=(${pkg})
    IFS="${OLDIFS}"
  }

  if [ "1" = "${#parts[@]}" ]; then
    version="master"
    info "Using latest (master)"
  elif [ "2" = "${#parts[@]}" ]; then
    name="${parts[0]}"
    version="${parts[1]}"
  else
     error "Error parsing package version"
    return 1
  fi

  ## split by user name and repo
  {
    OLDIFS="${IFS}"
    IFS='/'
    parts=(${pkg})
    IFS="${OLDIFS}"
  }

  if [ "1" = "${#parts[@]}" ]; then
    user="${BPKG_USER}"
    name="${parts[0]}"
  elif [ "2" = "${#parts[@]}" ]; then
    user="${parts[0]}"
    name="${parts[1]}"
  else
    error "Unable to determine package name"
    return 1
  fi

  ## clean up name of weird trailing
  ## versions and slashes
  name=${name/@*//}
  name=${name////}

  ## build uri portion
  uri="/${user}/${name}/${version}"

  ## clean up extra slashes in uri
  uri=${uri/\/\///}

  ## build url
  url="${BPKG_REMOTE}${uri}"

  ## determine if `package.json' exists at url
  {
    status=$(curl -sL "${url}/package.json" -w '%{http_code}' -o /dev/null)
    if [ "0" != "$?" ] || (( status >= 400 )); then
      error "Package doesn't exist"
      return 1
    fi
  }

  ## read package.json
  json=$(curl -sL "${url}/package.json")

  ## check if forced global
  if $(echo -n $json | bpkg-json -b | grep 'global' | awk '{ print $2 }' | tr -d '"'); then
    needs_global=1
  fi

  ## construct scripts array
  {
    scripts=$(echo -n $json | bpkg-json -b | grep 'scripts' | awk '{ print $2 }' | tr -d '"')
    OLDIFS="${IFS}"
    IFS=','
    scripts=($(echo ${scripts}))
    IFS="${OLDIFS}"
  }

  ## build global if needed
  if [ "1" = "${needs_global}" ]; then
    ## install bin if needed
    build="$(echo -n ${json} | bpkg-json -b | grep 'install' | awk '{$1=""; print $0 }' | tr -d '\"')"
    build="$(echo -n ${build} | sed -e 's/^ *//' -e 's/ *$//')"
    if [ ! -z "${build}" ]; then
      info "install: \`${build}'"
      {(
        ## go to tmp dir
        cd $( [ ! -z $TMPDIR ] && echo $TMPDIR || echo /tmp) &&
        ## prune existing
        rm -rf ${name}-${version} &&
        ## shallow clone
        git clone --depth=1 ${BPKG_GIT_REMOTE}/${user}/${name}.git ${name}-${version} > /dev/null 2>&1 &&
        (
          ## move into directory
          cd ${name}-${version} &&
          ## build
          eval "${build}"
        ) &&
        ## clean up
        rm -rf ${name}-${version}
      )}
    else
      warn "Mssing build script"
    fi

  elif [ "${#scripts[@]}" -gt "0" ]; then
    ## get package name from `package.json'
    name="$(echo -n ${json} | bpkg-json -b | grep 'name' | awk '{ print $2 }' | tr -d '\"')"

    ## make `deps/' directory if possible
    mkdir -p "${cwd}/deps/${name}"

    ## copy package.json over
    curl -sL "${url}/package.json" -o "${cwd}/deps/${name}/package.json"

    ## grab each script and place in deps directory
    for (( i = 0; i < ${#scripts[@]} ; ++i )); do
      (
        local script=${scripts[$i]}
        curl -sL "${url}/${script}" -o "${cwd}/deps/${name}/${script}"
      )
    done
  fi

  return 0
}

if [[ ${BASH_SOURCE[0]} != $0 ]]; then
  export -f bpkg_install
else
  bpkg_install "${@}"
  exit $?
fi
