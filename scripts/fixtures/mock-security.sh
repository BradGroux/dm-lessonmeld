#!/usr/bin/env bash
set -euo pipefail

: "${MOCK_SECURITY_LOG:?MOCK_SECURITY_LOG is required}"
command_name="$1"
{
  printf '%s' "${command_name}"
  shift
  for argument in "$@"; do
    printf '\t%s' "${argument}"
  done
  printf '\n'
} >> "${MOCK_SECURITY_LOG}"

if [[ "${MOCK_SECURITY_FAIL_COMMAND:-}" == "${command_name}" ]]; then
  exit 1
fi
