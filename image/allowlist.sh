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
# /etc/hosts as Ubuntu writes it, with the image's host name: sanitize writes it, check-rootfs compares
stock_hosts() {
    printf '127.0.0.1\tlocalhost\n127.0.1.1\tthinksmart\n\n'
    printf '# The following lines are desirable for IPv6 capable hosts\n'
    printf '::1     ip6-localhost ip6-loopback\nfe00::0 ip6-localnet\nff00::0 ip6-mcastprefix\n'
    printf 'ff02::1 ip6-allnodes\nff02::2 ip6-allrouters\n'
}
# the lines of ubuntu's AccountsService entry the image keeps (an awk pattern, whole lines only):
# sanitize keeps them, check-rootfs fails on any other
# shellcheck disable=SC2034 # read by sanitize-rootfs.sh and check-rootfs.sh
ACCOUNTS_KEEP='/^\[User\]$|^(Session|XSession)=[A-Za-z0-9._-]*$|^SystemAccount=(true|false)$|^Language=[A-Za-z0-9_.@:-]*$/'
# no link at all: the files sanitize writes into (>, cat >, install; a write would go through it) and
# the directories where sanitize or build-image.sh start a find (find does not enter a starting point
# that is a link, so what is behind it would stay)
# shellcheck disable=SC2034 # read by sanitize-rootfs.sh and check-rootfs.sh
WRITTEN_FILES='etc/passwd etc/shadow etc/group etc/gshadow etc/subuid etc/subgid etc/hostname etc/hosts etc/timezone etc/machine-id root/.bashrc root/.profile home/ubuntu/.bashrc home/ubuntu/.profile home/ubuntu/.bash_logout var/lib/AccountsService/users/ubuntu var/lib/thinksmart-update/status.json
etc home opt root usr/local var/log lib/modules home/ubuntu/xiaozhi-workspace home/ubuntu/xiaozhi-hub-server home/ubuntu/.config/systemd home/ubuntu/.config/pipewire home/ubuntu/.config/wireplumber home/ubuntu/.local
home/ubuntu/Desktop home/ubuntu/Documents home/ubuntu/Downloads home/ubuntu/Music home/ubuntu/Pictures home/ubuntu/Public home/ubuntu/Templates home/ubuntu/Videos'
# links that lead out of the root: an absolute one to a directory, or a relative one climbing past /.
# In the build container they lead into the container, not the image, so sanitize's deletions and
# check-rootfs's checks would miss the image's files there. Allowed (shell patterns), where nothing
# deletes or checks through them: Ubuntu's own, and uv's links from a Python minor version to the
# installed release (the gateway's .venv Python, kept whole by home-allowlist.txt), and openssl's
# /usr/lib/ssl/certs and /usr/lib/ssl/private (both reached through /etc/ssl, which is in the image)
# shellcheck disable=SC2034 # read by sanitize-rootfs.sh and check-rootfs.sh
OUT_DIR_LINKS_OK='/var/run /var/lock /home/ubuntu/.local/share/uv/python/* /usr/lib/ssl/certs /usr/lib/ssl/private'
# inroot ROOT PATH: PATH inside the image with every link on it followed there (an absolute target is
# the image's /); past 40 links, or ., an empty name or .. after something that is not a directory
# (the kernel refuses those), it gives up: an empty line, which no check accepts
inroot() {
    _r=$1; _rest=${2#"$1"}; _q=$1; _i=0
    while [ -n "$_rest" ]; do
        _rest=${_rest#/}; _c=${_rest%%/*}; _rest=${_rest#"$_c"}
        case $_c in
            '' | .) [ -d "$_q" ] || { echo; return 0; }; continue ;;
            ..) [ -d "$_q" ] || { echo; return 0; }; _q=${_q%/*}; [ "${#_q}" -ge "${#_r}" ] || _q=$_r; continue ;;
        esac
        if [ -L "$_q/$_c" ]; then
            [ "$_i" -lt 40 ] || { echo; return 0; }
            _k=$(readlink "$_q/$_c"); _i=$((_i + 1))
            case $_k in /*) _q=$_r ;; esac
            _rest=$_k$_rest
        else
            _q=$_q/$_c
        fi
    done
    printf '%s\n' "$_q"
}
# out_dir_links ROOT SCRATCH: each such link but those, as "/path -> target", one per line; returns 1
# when find fails (SCRATCH holds its list: in a pipe its failure would go unseen)
out_dir_links() {
    find "$1" -xdev -type l > "$2" || { echo "find failed in $1"; return 1; }
    while IFS= read -r _l; do
        _p=$(readlink "$_l") || { echo "${_l#"$1"} -> (unreadable)"; continue; }
        case $_p in
            # an absolute one always leaves the image in the container
            /*) ;;
            # a relative one leaves it when it climbs past / lexically (from the link's directory), or
            # when, followed here, it does not end inside the root (through an absolute link on its
            # way, such as /var/run, or one that only resolves in the image)
            *) _d=${_l#"$1"}
               if ! printf '%s/%s\n' "${_d%/*}" "$_p" | awk -F/ '{
                   n = 0; for (i = 1; i <= NF; i++) if ($i == "..") { if (--n < 0) exit 0 } else if ($i != "" && $i != ".") n++
                   exit 1 }'; then
                   if _t=$(readlink -f "$_l"); then
                       case $_t in "$1" | "$1"/*) continue ;; esac
                   fi
               fi ;;
        esac
        # what it names: a directory in the image (followed there) or here (where sanitize follows it)
        _t=$(inroot "$1" "$_l")
        if [ -z "$_t" ]; then echo "${_l#"$1"} -> $_p (does not resolve in the image)"; continue; fi
        [ -d "$_t" ] || [ -d "$_l" ] || continue
        _ok=; set -f   # the entries split into patterns, not file names
        for _g in $OUT_DIR_LINKS_OK; do
            # shellcheck disable=SC2254 # the entries are patterns
            case ${_l#"$1"} in $_g) _ok=1 ;; esac
        done; set +f
        [ -n "$_ok" ] || printf '%s -> %s\n' "${_l#"$1"}" "$_p"
    done < "$2"
}
