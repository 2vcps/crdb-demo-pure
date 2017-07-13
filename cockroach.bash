# bash completion for cockroach                            -*- shell-script -*-

__debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__my_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__handle_reply()
{
    __debug "${FUNCNAME[0]}"
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            COMPREPLY=( $(compgen -W "${allflags[*]}" -- "$cur") )
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%%=*}"
                __index_of_word "${flag}" "${flags_with_completion[@]}"
                if [[ ${index} -ge 0 ]]; then
                    COMPREPLY=()
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zfs completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    COMPREPLY=( $(compgen -W "${completions[*]}" -- "$cur") )

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        COMPREPLY=( $(compgen -W "${noun_aliases[*]}" -- "$cur") )
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        declare -F __custom_func >/dev/null && __custom_func
    fi

    __ltrim_colon_completions "$cur"
}

# The arguments should be in the form "ext1|ext2|extn"
__handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1
}

__handle_flag()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    if [ -n "${flagvalue}" ] ; then
        flaghash[${flagname}]=${flagvalue}
    elif [ -n "${words[ $((c+1)) ]}" ] ; then
        flaghash[${flagname}]=${words[ $((c+1)) ]}
    else
        flaghash[${flagname}]="true" # pad "true" for bool flag
    fi

    # skip the argument to a two word flag
    if __contains_word "${words[c]}" "${two_word_flags[@]}"; then
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__handle_noun()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__handle_command()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_$(basename "${words[c]//:/__}")"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__handle_word()
{
    if [[ $c -ge $cword ]]; then
        __handle_reply
        return
    fi
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __handle_flag
    elif __contains_word "${words[c]}" "${commands[@]}"; then
        __handle_command
    elif [[ $c -eq 0 ]] && __contains_word "$(basename "${words[c]}")" "${commands[@]}"; then
        __handle_command
    else
        __handle_noun
    fi
    __handle_word
}

_cockroach_start()
{
    last_command="cockroach_start"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--advertise-host=")
    local_nonpersistent_flags+=("--advertise-host=")
    flags+=("--attrs=")
    local_nonpersistent_flags+=("--attrs=")
    flags+=("--background")
    local_nonpersistent_flags+=("--background")
    flags+=("--cache=")
    local_nonpersistent_flags+=("--cache=")
    flags+=("--certs-dir=")
    local_nonpersistent_flags+=("--certs-dir=")
    flags+=("--host=")
    local_nonpersistent_flags+=("--host=")
    flags+=("--http-host=")
    local_nonpersistent_flags+=("--http-host=")
    flags+=("--http-port=")
    local_nonpersistent_flags+=("--http-port=")
    flags+=("--insecure")
    local_nonpersistent_flags+=("--insecure")
    flags+=("--join=")
    two_word_flags+=("-j")
    local_nonpersistent_flags+=("--join=")
    flags+=("--listening-url-file=")
    local_nonpersistent_flags+=("--listening-url-file=")
    flags+=("--locality=")
    local_nonpersistent_flags+=("--locality=")
    flags+=("--max-offset=")
    local_nonpersistent_flags+=("--max-offset=")
    flags+=("--max-sql-memory=")
    local_nonpersistent_flags+=("--max-sql-memory=")
    flags+=("--pid-file=")
    local_nonpersistent_flags+=("--pid-file=")
    flags+=("--port=")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port=")
    flags+=("--store=")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--store=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_cert_create-ca()
{
    last_command="cockroach_cert_create-ca"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-ca-key-reuse")
    local_nonpersistent_flags+=("--allow-ca-key-reuse")
    flags+=("--ca-key=")
    local_nonpersistent_flags+=("--ca-key=")
    flags+=("--certs-dir=")
    local_nonpersistent_flags+=("--certs-dir=")
    flags+=("--key-size=")
    local_nonpersistent_flags+=("--key-size=")
    flags+=("--lifetime=")
    local_nonpersistent_flags+=("--lifetime=")
    flags+=("--overwrite")
    local_nonpersistent_flags+=("--overwrite")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_cert_create-node()
{
    last_command="cockroach_cert_create-node"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ca-key=")
    local_nonpersistent_flags+=("--ca-key=")
    flags+=("--certs-dir=")
    local_nonpersistent_flags+=("--certs-dir=")
    flags+=("--key-size=")
    local_nonpersistent_flags+=("--key-size=")
    flags+=("--lifetime=")
    local_nonpersistent_flags+=("--lifetime=")
    flags+=("--overwrite")
    local_nonpersistent_flags+=("--overwrite")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_cert_create-client()
{
    last_command="cockroach_cert_create-client"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ca-key=")
    local_nonpersistent_flags+=("--ca-key=")
    flags+=("--certs-dir=")
    local_nonpersistent_flags+=("--certs-dir=")
    flags+=("--key-size=")
    local_nonpersistent_flags+=("--key-size=")
    flags+=("--lifetime=")
    local_nonpersistent_flags+=("--lifetime=")
    flags+=("--overwrite")
    local_nonpersistent_flags+=("--overwrite")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_cert_list()
{
    last_command="cockroach_cert_list"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    local_nonpersistent_flags+=("--certs-dir=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_cert()
{
    last_command="cockroach_cert"
    commands=()
    commands+=("create-ca")
    commands+=("create-node")
    commands+=("create-client")
    commands+=("list")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_quit()
{
    last_command="cockroach_quit"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_sql()
{
    last_command="cockroach_sql"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--database=")
    two_word_flags+=("-d")
    flags+=("--execute=")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--execute=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_user_get()
{
    last_command="cockroach_user_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_user_ls()
{
    last_command="cockroach_user_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_user_rm()
{
    last_command="cockroach_user_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_user_set()
{
    last_command="cockroach_user_set"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--password")
    local_nonpersistent_flags+=("--password")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_user()
{
    last_command="cockroach_user"
    commands=()
    commands+=("get")
    commands+=("ls")
    commands+=("rm")
    commands+=("set")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_zone_get()
{
    last_command="cockroach_zone_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_zone_ls()
{
    last_command="cockroach_zone_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_zone_rm()
{
    last_command="cockroach_zone_rm"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_zone_set()
{
    last_command="cockroach_zone_set"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--disable-replication")
    local_nonpersistent_flags+=("--disable-replication")
    flags+=("--file=")
    two_word_flags+=("-f")
    local_nonpersistent_flags+=("--file=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_zone()
{
    last_command="cockroach_zone"
    commands=()
    commands+=("get")
    commands+=("ls")
    commands+=("rm")
    commands+=("set")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_node_ls()
{
    last_command="cockroach_node_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_node_status()
{
    last_command="cockroach_node_status"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--format=")
    local_nonpersistent_flags+=("--format=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_node()
{
    last_command="cockroach_node"
    commands=()
    commands+=("ls")
    commands+=("status")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_dump()
{
    last_command="cockroach_dump"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--as-of=")
    local_nonpersistent_flags+=("--as-of=")
    flags+=("--certs-dir=")
    flags+=("--dump-mode=")
    local_nonpersistent_flags+=("--dump-mode=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--url=")
    flags+=("--user=")
    two_word_flags+=("-u")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_gen_man()
{
    last_command="cockroach_gen_man"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--path=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_gen_autocomplete()
{
    last_command="cockroach_gen_autocomplete"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--out=")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_gen_example-data()
{
    last_command="cockroach_gen_example-data"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_gen_haproxy()
{
    last_command="cockroach_gen_haproxy"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--out=")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_gen()
{
    last_command="cockroach_gen"
    commands=()
    commands+=("man")
    commands+=("autocomplete")
    commands+=("example-data")
    commands+=("haproxy")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_version()
{
    last_command="cockroach_version"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_keys()
{
    last_command="cockroach_debug_keys"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--from=")
    local_nonpersistent_flags+=("--from=")
    flags+=("--sizes")
    local_nonpersistent_flags+=("--sizes")
    flags+=("--to=")
    local_nonpersistent_flags+=("--to=")
    flags+=("--values")
    local_nonpersistent_flags+=("--values")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_range-data()
{
    last_command="cockroach_debug_range-data"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--replicated")
    local_nonpersistent_flags+=("--replicated")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_range-descriptors()
{
    last_command="cockroach_debug_range-descriptors"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_raft-log()
{
    last_command="cockroach_debug_raft-log"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_estimate-gc()
{
    last_command="cockroach_debug_estimate-gc"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_check-store()
{
    last_command="cockroach_debug_check-store"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_rocksdb()
{
    last_command="cockroach_debug_rocksdb"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_compact()
{
    last_command="cockroach_debug_compact"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_sstables()
{
    last_command="cockroach_debug_sstables"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_range_ls()
{
    last_command="cockroach_debug_range_ls"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--max-results=")
    local_nonpersistent_flags+=("--max-results=")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_range_split()
{
    last_command="cockroach_debug_range_split"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_range()
{
    last_command="cockroach_debug_range"
    commands=()
    commands+=("ls")
    commands+=("split")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_env()
{
    last_command="cockroach_debug_env"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug_zip()
{
    last_command="cockroach_debug_zip"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--certs-dir=")
    flags+=("--host=")
    flags+=("--insecure")
    flags+=("--port=")
    two_word_flags+=("-p")
    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach_debug()
{
    last_command="cockroach_debug"
    commands=()
    commands+=("keys")
    commands+=("range-data")
    commands+=("range-descriptors")
    commands+=("raft-log")
    commands+=("estimate-gc")
    commands+=("check-store")
    commands+=("rocksdb")
    commands+=("compact")
    commands+=("sstables")
    commands+=("range")
    commands+=("env")
    commands+=("zip")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_cockroach()
{
    last_command="cockroach"
    commands=()
    commands+=("start")
    commands+=("cert")
    commands+=("quit")
    commands+=("sql")
    commands+=("user")
    commands+=("zone")
    commands+=("node")
    commands+=("dump")
    commands+=("gen")
    commands+=("version")
    commands+=("debug")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-backtrace-at=")
    flags+=("--log-dir=")
    flags+=("--log-dir-max-size=")
    flags+=("--log-file-max-size=")
    flags+=("--log-file-verbosity=")
    flags+=("--logtostderr")
    flags+=("--no-color")
    flags+=("--verbosity=")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_cockroach()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __my_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("cockroach")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_cockroach cockroach
else
    complete -o default -o nospace -F __start_cockroach cockroach
fi

# ex: ts=4 sw=4 et filetype=sh
