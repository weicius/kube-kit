#!/usr/bin/env bash
# vim: nu:noai:ts=4

# this is the plain command string.
DATE_NOW="date +'%Y-%m-%d %H:%M:%S'"


########################################################################################
## ****************************** Usage of LOG Command ****************************** ##
## LOG <info|title|debug|warn|error|fatal> [-n|--nonewline] [-r|--raw-texts] messages ##
########################################################################################

function LOG() {
    local level=""
    local texts=""
    local nonewline="false"
    local raw_texts="${ENABLE_RAW_LOGS:-false}"

    while true; do
        if [[ "${1,,}" =~ ^(info|title|debug|warn|fatal|error)$ ]]; then
            level="${1}"
            shift
            continue
        fi

        case "${1}" in
            -n|--nonewline)
                nonewline="true"
                shift
                ;;
            -r|--raw-texts)
                raw_texts="true"
                shift
                ;;
            *)
                texts+="${1} "
                shift
                [[ $# -eq 0 ]] && break
                ;;
        esac
    done

    case "${level,,}" in
        info)
            # print 'green' text.
            color_code="\033[0;32m"
            ;;
        title)
            # print 'dark gray' text.
            color_code="\033[0;90m"
            ;;
        debug)
            # print 'blue' text.
            color_code="\033[0;34m"
            ;;
        warn)
            # print 'orange' text.
            color_code="\033[0;33m"
            ;;
        error)
            # print 'red' text.
            color_code="\033[0;31m"
            ;;
        fatal)
            # print 'magenta' text.
            color_code="\033[0;35m"
            ;;
        *)
            # print debug by default.
            level="debug"
            color_code="\033[0;34m"
            ;;
    esac

    # use 'bash <<< "${DATE_NOW}"' or 'eval ${DATE_NOW}' to execute command from a variable.
    # use '${texts%?}', '${texts::-1}' or '${texts% }' to remove last space (separator).
    prefix_text="$(eval ${DATE_NOW}) [${level^^}]"

    # add a prefix (ipv4 address of current host) if LOG is executed on remote hosts.
    [[ "${#BASH_SOURCE[@]}" -eq 0 ]] && prefix_text="[$(util::current_host_ip)] ${prefix_text}"
    final_text="${prefix_text} ${texts}"

    # display the messages with colored text if 'raw_texts' is NOT 'true'.
    [[ "${raw_texts,,}" != "true" ]] && final_text="${color_code}${final_text}\033[0m"

    # do not print a newline '\n' at the end of messages if nonewline is NOT 'true'.
    [[ "${nonewline,,}" != "true" ]] && final_text+="\n"

    # redirect the warn and error logs into stderr.
    case "${level,,}" in
        warn|error|fatal)
            echo -en "${final_text}" 1>&2
            ;;
        *)
            echo -en "${final_text}"
            ;;
    esac
}


function LOG_EMPHASIZE() {
    local level="${1}"
    local char="${2}"
    local message="${char}${char} ${*:3} ${char}${char}"

    if [[ -z "${level}" ]]; then
        LOG error "The level <info|title|debug|warn|error|fatal> is required!"
        return 1
    elif [[ -z "${char}" || "${char}" =~ ^.{2,}$ ]]; then
        LOG error "The single special character is required!"
        return 2
    fi

    pretty_header=$(printf "%0.s${char}" $(seq ${#message}))

    LOG "${level}" "${pretty_header}"
    LOG "${level}" "${message}"
    LOG "${level}" "${pretty_header}"
}
