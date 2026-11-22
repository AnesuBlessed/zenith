#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Minimal Arrow Breadcrumb Prompt (Style 1)
# =============================================================================
#  Renders subdirectories with clean arrows: ~ ❯ Documents ❯ zenith ❯ 
# =============================================================================

_zenith_prompt() {
    local last_status=$?
    local arrow="❯"

    # Fallback to '>' if non-UTF8 environment
    if [[ "${LANG:-}" != *UTF-8* && "${LC_ALL:-}" != *UTF-8* ]]; then
        arrow=">"
    fi

    # Replace $HOME with ~
    local cur_path="${PWD/#$HOME/\~}"

    # Replace '/' with ' ❯ '
    local breadcrumbs="${cur_path//\// $arrow }"

    # Status color: green if last command succeeded, red if failed
    local prompt_color="\[\033[38;5;141m\]" # Soft accent purple
    local status_color="\[\033[38;5;75m\]"  # Sky blue arrow
    if [[ $last_status -ne 0 ]]; then
        status_color="\[\033[38;5;203m\]"   # Accent red error
    fi

    local reset="\[\033[0m\]"

    PS1="${prompt_color}${breadcrumbs} ${status_color}${arrow} ${reset}"
}

PROMPT_COMMAND="_zenith_prompt"
