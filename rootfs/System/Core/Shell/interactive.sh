# SPDX-License-Identifier: GPL-2.0-or-later

cd() {
    if [ "$#" -eq 0 ]; then
        command cd "$HOME"
        return
    fi

    if [ "$#" -eq 1 ]; then
        case "$1" in
            [A-Z]:|[A-Z]:/*)
                target="$(solpath --resolve "$1")" || return
                command cd "$target"
                return
                ;;
        esac
    fi

    command cd "$@"
}

PS1='solven $(solpath --display "$PWD") # '
export PS1
