#!/usr/bin/env bash

set -euo pipefail


################################################################################
# Prints a real directory of the path by following symlinks.
#
# Arguments:
#   $1: A path
################################################################################
realdir() {
  if [[ -z "$1" ]]; then
    pwd
  else
    (
      cd "$(dirname "$1")"
      realdir "$(readlink "$(basename "$1")")"
    )
  fi
}

readonly LOCALISH="$(realdir "$0")"

declare -rx LOCAL_ROOT="${HOME}/.local"
declare -rx LOCAL_REPO="${LOCAL_ROOT}/repo"
declare -rx LOCAL_BIN="${LOCAL_ROOT}/bin"
declare -rx LOCALRC="${HOME}/.localrc"

mkdir -p "${LOCAL_ROOT}"
mkdir -p "${LOCAL_REPO}"
mkdir -p "${LOCAL_BIN}"
touch "${LOCALRC}"


# Add LOCAL_BIN to PATH if not existing
if [[ ":${PATH}:" != *":${LOCAL_BIN}:"* ]]; then
  export PATH="${LOCAL_BIN}:${PATH}"
fi


################################################################################
# Appends a content from stdin to localrc if not existing.
#
# Arguments:
#   $1        : A label for the content
#   /dev/stdin: A content to be appended to "${HOME}/.localrc"
################################################################################
localrc() {
  local label="$1"
  local content="$(home_relpathed "$(cat -)")"

  # Put label
  content="$(echo -e "# ${label}\n${content}")"
  require_content "${LOCALRC}" "${content}"
}


################################################################################
# Replaces actual home pathes with ${HOME}
#
# Arguments:
#   $1: A string contains pathes
# Prints:
#   A string containing '${HOME}' rather tan actual home pathes
# Example:
#   '/User/yeonghoey/.localrc' -> '${HOME}/.localrc'
################################################################################
home_relpathed() {
  # Replace '/user/<username>/*' with '${HOME}/.local/*'
  local content="$1"
  local relpath="${LOCAL_ROOT#"${HOME}"}"
  local sedexp="s:${LOCAL_ROOT}:\${HOME}${relpath}:g"
  echo "$content" | sed "${sedexp}"
}


################################################################################
# Appends a content to a file if not existing.
#
# Uses:
#   lib/ui.sh: info
# Arguments:
#   $1          : A file path
#   $2(optional): A content to be existing in the file, use stdin if not passed.
# Returns:
#   0 if content appended, 1 otherwise.
################################################################################
require_content() {
  if [[ "$#" == 1 ]]; then
    local path="$1"
    local content="$(cat -)"
  else
    local path="$1"
    local content="$2"
  fi

  if ! grep -qF "${content}" "${path}"; then
    info "Append to '${path}'"
    echo -e "${content}\n" | tee -a "${path}"
  fi
}


################################################################################
# Writes a content to a file
#
# Uses:
#   lib/ui.sh: info
# Arguments:
#   $1          : A file path
#   $2(optional): A content to be existing in the file, use stdin if not passed.
################################################################################
require_file() {
  if [[ "$#" == 1 ]]; then
    local path="$1"
    local content="$(cat -)"
  else
    local path="$1"
    local content="$2"
  fi
  info "Write to '${path}'"
  echo "$content" | tee "${path}"
}


################################################################################
# Prints the absolute path.
#
# Arguments:
#   $1: A path
################################################################################
abspath() {
  echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
}


################################################################################
# Place a number extension with enusuring the path doesn't exist
#
# Arguments:
#   $1: A path
# Prints:
#   numbered 'file.bk' -> 'file.bk' or 'file.bk.1', 'file.bk.2' etc.
################################################################################
numbered() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "$path"
    return 0
  fi

  local n=0
  while true; do
    if [[ ! -e "$path.$n" ]]; then
      echo "$path.$n"
      return 0
    fi
    n="$((n + 1))"
  done
}


################################################################################
# Download a file
#
# Arguments:
#   $1: A source URL
#   $2: A target path
################################################################################
download() {
  local url="$1"
  local path="$2"

  mkdir -p "$(dirname "$path")"

  # A ripoff from
  # https://github.com/alrra/dotfiles/blob/master/src/os/setup.sh

  info "Download '$url' into '$path'"
  if command_exists 'wget'; then

    wget -qO "$path" "$url" &> /dev/null
    #     │└─ write output to file
    #     └─ don't show output
    return "$?"

  elif command_exists 'curl'; then

    curl -LsSo "$path" "$url" &> /dev/null
    #     │││└─ write output to file
    #     ││└─ show error messages
    #     │└─ don't show the progress meter
    #     └─ follow redirects
    return "$?"

  else
    info "Unable to use 'wget' or 'curl'."
    return 1
  fi
}


################################################################################
# Extract a file
#
# Arguments:
#   $1: A path
#   $2: A target directory
################################################################################
extract() {
  local path="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"

  info "Extract '$path' into '$target_dir'"
  if [[ -f "$path" ]]; then
    case "$path" in
      *.tar.bz2) tar -C "$target_dir" -jxvf "$path"          ;;
      *.tar.gz)  tar -C "$target_dir" -zxvf "$path"          ;;
      *.tar)     tar -C "$target_dir" -xvf "$path"           ;;
      *.zip)     unzip -d "$target_dir" "$path"              ;;
      *.ZIP)     unzip -d "$target_dir" "$path"              ;;
      *)         info "Unabled to extract '$path'"; return 1 ;;
    esac
  else
    info "File '$path' doesn't exist."
    return 1
  fi
}


################################################################################
# Arguments:
#   $1: A name of command
# Returns:
#   0 if exists, 1 otherwise
################################################################################
command_exists() {
  # SEE: https://stackoverflow.com/questions/592620/check-if-a-program-exists-from-a-bash-script
  command -v "$1" >/dev/null 2>&1
}


################################################################################
# Arguments:
#   $1: A name of command
# Prints:
#   The absolute path to the command
################################################################################
command_path() {
  command -v "$1"
}


################################################################################
# Tests whether current OS is macOS
################################################################################
macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}


################################################################################
# Tests whether current OS is Ubuntu
################################################################################
ubuntu() {
  [[ "$(uname -s)" == "Linux" ]] && [[ -e "/etc/lsb-release" ]]
}


################################################################################
# Clones a git repostiory or pulls it if existing
#
# Arguments:
#   $1          : A URL for the git remote repository
#   $2(optional): A repo name which will be placed under LOCAL_REPO
################################################################################
repo_git() {
  local url="$1"
  local name="${2-$(basename $url .git)}"
  local target="${LOCAL_REPO}/${name}"

  if [[ -d "${target}" ]]; then
    info "Pull '${target}'"
    git -C "${target}" pull
  else
    # Ensure the parent directories exist
    mkdir -p "${target}"

    info "Clone '${url}'"
    git clone "${url}" "${target}"
  fi
}


################################################################################
# Get a compressed file and extract it as a repo
#
# Arguments:
#   $1: A URL for download via wget
#   $2: A folder name under LOCAL_REPO where the file is extracted in.
################################################################################
repo_zip() {
  local url="$1"
  local repo="${LOCAL_REPO}/$2"
  local download_path="$(mktemp -d)/$(basename "$url")"

  download "$url" "$download_path"
  extract  "$download_path" "$repo"
}


################################################################################
# Get a file and put it into a repo
#
# Arguments:
#   $1: A URL for download via wget
#   $2: A folder name under LOCAL_REPO where the file is extracted in.
################################################################################
repo_get() {
  local url="$1"
  local repo="${LOCAL_REPO}/$2"
  local download_path="$repo/$(basename "$url")"

  download "$url" "$download_path"
}


################################################################################
# Symlinks files under LOCAL_REPO
#
# Arguments:
#   $1: A relative path to LOCAL_REPO
################################################################################
repo_bin() {
  local src="${LOCAL_REPO}/$1"
  local dst="${LOCAL_BIN}/$(basename "$src")"
  info "Make '$binpath' executable."
  chmod +x "$src"
  symlink "$src" "$dst"
}


################################################################################
# Create a symlink from under LOCAL_REPO to a path
#
# Arguments:
#   $1: A relative path to LOCAL_REPO
#   $2: A path for symlink. if path is a existing directory, prompts to replace
################################################################################
repo_sym() {
  local src="${LOCAL_REPO}/$1"
  local dst="$2"
  symlink "$src" "$dst"
}


################################################################################
# Create a symlink
#
# Arguments:
#   $1: A src path
#   $2: A path for symlink. if path is a existing directory, prompts to replace
################################################################################
symlink() {
  local src="$1"
  local dst="$2"

  info "Create a symlink from '$src' to '$dst'"

  if [[ "$src" -ef "$(readlink "$dst")" ]]; then
    info "Symlink already exists. skipped."
    return 0
  fi

  if [[ -e "$dst" ]]; then
    prompt_yn "Path '$dst' already exists. Replace it?"
    if answer_is_yes; then
      local dstbk="$(numbered "${dst}.bk")"
      info "Move '$dst' to '$dstbk'"
      mv "$dst" "$dstbk"
    else
      return 1
    fi
  fi
  # -s, symlink
  ln -s "$(abspath $src)" "$(abspath $dst)"
}



################################################################################
# Run a command under LOCAL_REPO
#
# Arguments:
#   $1              : A relative path to LOCAL_REPO for a command
#   ${@:2}(optional): Arguments for the command
################################################################################
repo_run() {
  local run="${LOCAL_REPO}/$1"
  info "Run '$run'"
  "$run" "${@:2}"
}


################################################################################
# Prints a notification message in a consistent format.
################################################################################
noti() {
  echo "* $1"
}


################################################################################
# Prints a progress infomation message in a consistent format.
################################################################################
info() {
  echo "- $1"
}


################################################################################
# Prints a question and read an answer.
# Arguments:
#   $1: A question.
################################################################################
prompt() {
  printf "? $1: "
  read -r
}


################################################################################
# Prints a question and read an answer.
# Prints:
#   The answer of the last prompt.
################################################################################
answer() {
  echo "${REPLY}"
}


################################################################################
# Prints a question and read 1 character.
# Arguments:
#   $1: A question.
################################################################################
prompt_yn() {
  printf "? $1 (y/n) "
  read -r -n 1
  echo
}


################################################################################
# Returns 0 if previous prompt was 'Yy'
################################################################################
answer_is_yes() {
  if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}


################################################################################
# Run command with its stdout and stderr indented
################################################################################
indented() {
  "$@" 2>&1 | sed 's/^/    /'
}


################################################################################
# Require sudo athorization and keep it alive.
################################################################################
use_sudo() {
  sudo -v &> /dev/null

  # Update existing `sudo` time stamp
  # until this script has finished.
  # https://gist.github.com/cowboy/3118588
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done &> /dev/null &
}


################################################################################
# Run recipes
# Arguments:
#   Names of recipes in "$LOCALISH/recipes"
################################################################################
run_recipes() {
  for recipe in "$@"; do
    noti "Run: '${recipe}'"
    if (source "${LOCALISH}/recipes/${recipe}.sh"); then
      noti "Done: '${recipe}'"
    else
      noti "Abort: '${recipe}'"
      return 1
    fi
  done
}


# ------------------------------------------------------------------------------


run_recipes "$@"
