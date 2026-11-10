# shellcheck shell=sh
# Shared by sanitize-rootfs.sh and check-rootfs.sh (sourced, not run).

# home_allowed REL: is /home/ubuntu/REL on home-allowlist.txt ($HOME_ALLOW)? An entry ending in /
# covers everything under it.
home_allowed() {
    while IFS= read -r e; do
        case $e in
            ''|'#'*) ;;
            */) case $1 in "$e"*) return 0 ;; esac ;;
            *) [ "$1" = "$e" ] && return 0 ;;
        esac
    done < "$HOME_ALLOW"
    return 1
}

# hub_config TEMPLATE: the gateway's data/.config.yaml for a new device, from its
# scripts/config.template.yaml, as its install script writes it on a machine without Claude Code:
# Claude API, key set in the admin page
hub_config() {
    sed 's/^\(  LLM: \)ClaudeCLI.*/\1ClaudeAPI          # 在管理后台填写 API Key/' "$1"
}

# provenance_uncovered ROOT LIST FILE: reads grep -n hits of FILE (line:content) on stdin and
# prints "/path:content" for each one LIST does not allow. The path is FILE's, so a file name that
# itself holds ":<digits>:" cannot pose as another path. LIST lines (tab separated):
#   file<TAB>PATTERN        the whole file (shell pattern on the path)
#   line<TAB>PATH<TAB>LINE  that exact line of that file
# A file pattern covers only paths with as many / as itself (in case, * also matches /).
provenance_uncovered() {
    tab=$(printf '\t')
    path=${3#"$1"}
    while IFS= read -r hit; do
        content=${hit#*:}
        ok=1
        while IFS=$tab read -r kind a b; do
            case $kind in
                file)
                    # shellcheck disable=SC2254 # $a is a shell pattern on purpose
                    case $path in $a)
                        [ "$(printf %s "$path" | tr -cd /)" = "$(printf %s "$a" | tr -cd /)" ] && ok=0 ;;
                    esac ;;
                line) [ "$path" = "$a" ] && [ "$content" = "$b" ] && ok=0 ;;
            esac
            [ $ok = 0 ] && break
        done < "$2"
        [ $ok = 0 ] || printf '%s:%s\n' "$path" "$content"
    done
}
