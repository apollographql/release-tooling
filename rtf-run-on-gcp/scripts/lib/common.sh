#!/usr/bin/env bash
# Shared utility functions for RTF GCP scripts.

# Colors for output
declare -A C=(
  [red]='\033[31m'   [green]='\033[32m'  [yellow]='\033[33m'
  [blue]='\033[34m'  [purple]='\033[35m' [cyan]='\033[36m'
  [white]='\033[37m' [bold]='\033[1m'    [nc]='\033[0m'
)

function heading {
  echo -e "${C[cyan]}${C[bold]}::${C[nc]} $*"
}

function warn {
  echo -e "${C[yellow]}${C[bold]}::${C[nc]} $*"
}

function error {
  echo -e "${C[red]}${C[bold]}::${C[nc]} $*"
}

function error_and_exit {
  error "$*"
  exit 1
}
