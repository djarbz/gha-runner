#!/usr/bin/env bash

# Exit on error, undefined variable, or pipe failure.
set -euo pipefail

# --- Helper Functions ---

# A helper function to run commands with sudo if not already root.
# This makes the script portable and avoids errors if run as root.
run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Generates a unique and friendly name for the runner.
generate_runner_name() {
  # If a full name is provided, use it (truncated to 64 chars).
  if [[ -n "${RUNNER_FULL_NAME:-}" ]]; then
    printf "%.64s" "${RUNNER_FULL_NAME}"
    return
  fi

  local prefix="${RUNNER_NAME_PREFIX:-github-runner}"
  local suffix

  # Use the hostname if it's available and non-empty, otherwise generate a random string.
  if [[ -s "/etc/hostname" ]]; then
    suffix=$(cat /etc/hostname)
  else
    # A more modern and reliable way to get random hex characters.
    suffix=$(openssl rand -hex 6)
  fi

  printf "%.64s" "${prefix}-${RUNNER_NAME:-}${suffix}"
}

# --- Cleanup Function ---

# This function is called on script exit to ensure the runner is always deregistered.
# It now accepts the registration token as an argument to avoid global variables.
cleanup() {
  local token="$1" # Accept token as the first argument. Can be empty.
  echo "--- Performing cleanup ---"

  if [[ -n "${token}" ]]; then
    echo "Deregistering runner..."
    # Use '|| true' to prevent the script from exiting if deregistration fails.
    ./config.sh remove --token "${token}" || true
  fi

  if [[ -d "./_work" ]]; then
    echo "Cleaning work directory..."
    rm -rf "./_work/*"
  fi

  echo "--- Cleanup complete ---"
}

# --- Main Logic ---

main() {
  # --- Variable Validation ---
  if [[ -z "${ACCESS_TOKEN:-}" ]]; then
    echo "Error: ACCESS_TOKEN environment variable is not set." >&2
    exit 1
  fi
  if [[ -z "${REPOSITORY:-}" ]]; then
    echo "Error: REPOSITORY environment variable is not set." >&2
    exit 1
  fi

  # Set a preliminary trap for cleanup in case the script fails early.
  # The token is empty here, so it will only clean the directory.
  trap 'cleanup ""' EXIT

  # Scope variables locally for security.
  local access_token="${ACCESS_TOKEN}"
  local repository="${REPOSITORY}"
  local runner_name
  runner_name=$(generate_runner_name)
  unset ACCESS_TOKEN REPOSITORY

  # --- Runner Registration ---
  echo "Requesting registration token for repository: ${repository}"
  # Use a local variable for the token.
  local reg_token
  reg_token=$(
    curl -fsS -X POST \
      -H "Authorization: token ${access_token}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${repository}/actions/runners/registration-token" | jq .token --raw-output
  )

  if [[ -z "${reg_token}" ]]; then
    echo "Error: Failed to retrieve a registration token. Check credentials and repository path." >&2
    exit 1
  fi
  echo "Registration token received successfully."

  # Now that we have a token, redefine the trap to include it for deregistration.
  # This is the key to avoiding global variables for the cleanup function.
  trap 'cleanup "${reg_token}"' EXIT

  # --- Runner Configuration ---
  echo "Configuring the runner named '${runner_name}'..."
  # Use the helper to avoid running 'sudo' as the root user.
  run_as_root chown -R "$(id -u):999" ./

  # Configure the runner.
  ./config.sh --url "https://github.com/${repository}" \
    --token "${reg_token}" \
    --name "${runner_name}" \
    --ephemeral \
    --unattended \
    --disableupdate

  # --- Start and Wait ---
  echo "Starting the runner..."
  # Run in the background and wait, allowing the trap to catch signals.
  ./run.sh & wait $!
}

# --- Script Execution ---
main "$@"
