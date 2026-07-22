pub const BASH_AUTOCOMPLETION =
    \\_{[name]s}_cli_autocomplete() {{
    \\    declare -A CMD_OPTS=(
    \\      {[cmd_opts]s}
    \\    )
    \\    local cur prev cmd opts global_flags
    \\    COMPREPLY=()
    \\
    \\    cur="${{COMP_WORDS[COMP_CWORD]}}"
    \\    cmd="${{COMP_WORDS[1]}}"
    \\
    \\    opts="{[opts]s}"
    \\    global_flags="{[global_flags]s}"
    \\    if (( COMP_CWORD == 1 )); then
    \\      COMPREPLY=( $(compgen -W "$opts ${{CMD_OPTS['root']}} $global_flags" -- "$cur") )
    \\      return 0
    \\    elif [[ -n ${{CMD_OPTS[$cmd]}} ]]; then
    \\       COMPREPLY=( $(compgen -W "${{CMD_OPTS[$cmd]}} $global_flags" -- "$cur") )
    \\    else
    \\       COMPREPLY=( $(compgen -W "$global_flags" -- "$cur") )
    \\    fi
    \\
    \\    return 0
    \\}}
    \\
    \\complete -F _{[name]s}_cli_autocomplete {[name]s}
;
