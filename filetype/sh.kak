hook global BufCreate .*\.(z|ba|c|k|mk)?sh(rc|_profile)? %{
    set-option buffer filetype sh
}

hook global WinSetOption filetype=sh %{
    require-module sh
    set-option window static_words %opt{sh_static_words}

    hook window ModeChange pop:insert:.* -group sh-trim-indent sh-trim-indent
    hook window InsertChar \n -group sh-insert sh-insert-on-new-line
    hook window InsertChar \n -group sh-indent sh-indent-on-new-line
    hook -once -always window WinSetOption filetype=.* %{ remove-hooks window sh-.+ }
}

hook -group sh-highlight global WinSetOption filetype=sh %{
    add-highlighter window/sh ref sh
    hook -once -always window WinSetOption filetype=.* %{ remove-highlighter window/sh }
}

provide-module sh %[

add-highlighter shared/sh regions
add-highlighter shared/sh/code default-region group
add-highlighter shared/sh/double_string region  %{(?<!\\)(?:\\\\)*\K"} %{(?<!\\)(?:\\\\)*"} group
add-highlighter shared/sh/single_string region %{(?<!\\)(?:\\\\)*\K'} %{'} fill string
add-highlighter shared/sh/expansion region -recurse \$\{ \$\{ \}|\n fill value
add-highlighter shared/sh/comment region (?<!\\)(?:\\\\)*(?:^|\h)\K# '$' fill comment
add-highlighter shared/sh/heredoc region -match-capture '<<-?\h*''?(\w+)''?' '^\t*(\w+)$' fill string

add-highlighter shared/sh/double_string/fill fill string

evaluate-commands %sh{
    # Grammar
    # Generated with `compgen -k` in bash
    keywords="if then else elif fi case esac for select while until do done in
             function time coproc"

    # Generated with `compgen -b` in bash
    builtins="alias bg bind break builtin caller cd command compgen complete
             compopt continue declare dirs disown echo enable eval exec
             exit export false fc fg getopts hash help history jobs kill
             let local logout mapfile popd printf pushd pwd read readarray
             readonly return set shift shopt source suspend test times trap
             true type typeset ulimit umask unalias unset wait"

    join() { sep=$2; eval set -- $1; IFS="$sep"; echo "$*"; }

    # Add the language's grammar to the static completion list
    printf %s\\n "declare-option str-list sh_static_words $(join "${keywords}" ' ') $(join "${builtins}" ' ')"

    # Highlight keywords
    printf %s\\n "add-highlighter shared/sh/code/ regex (?<!-)\b($(join "${keywords}" '|'))\b(?!-) 0:keyword"

    # Highlight builtins
    printf %s "add-highlighter shared/sh/code/builtin regex (?<!-)\b($(join "${builtins}" '|'))\b(?!-) 0:builtin"
}

add-highlighter shared/sh/code/operators regex [\[\]\(\)&|]{1,2} 0:operator
add-highlighter shared/sh/code/variable regex ((?<![-:])\b\w+)= 1:variable
add-highlighter shared/sh/code/alias regex \balias(\h+[-+]\w)*\h+([\w-.]+)= 2:variable
add-highlighter shared/sh/code/function regex ^\h*(\S+)\h*\(\) 1:function

add-highlighter shared/sh/code/unscoped_expansion regex \$(\w+|#|@|\?|\$|!|-|\*) 0:value
add-highlighter shared/sh/double_string/expansion regex \$(\w+|\{.+?\}) 0:value
# brackets
add-highlighter shared/sh/code/ regex '[(){}\[\]]' 0:brackets
# ‾‾‾‾‾‾‾‾

define-command -hidden sh-trim-indent %{
    # remove trailing white spaces
    try %{ execute-keys -draft -itersel <a-x> s \h+$ <ret> d }
}

# This is at best an approximation, since shell syntax is very complex.
# Also note that this targets plain sh syntax, not bash - bash adds a whole
# other level of complexity. If your bash code is fairly portable this will
# probably work.
#
# Of necessity, this is also fairly opinionated about indentation styles.
# Doing it "properly" would require far more context awareness than we can
# bring to this kind of thing.
define-command -hidden sh-insert-on-new-line %[
    evaluate-commands -draft -itersel %[
        # copy '#' comment prefix and following white spaces
        try %{ execute-keys -draft k <a-x> s ^\h*\K#\h* <ret> y gh j P }
    ]
]

define-command -hidden sh-indent-on-new-line %[
    evaluate-commands -draft -itersel %[
        # preserve previous line indent
        try %{ execute-keys -draft <semicolon> K <a-&> }
        # filter previous line
        try %{ execute-keys -draft k : sh-trim-indent <ret> }

        # Indent loop syntax, e.g.:
        # for foo in bar; do
        #       things
        # done
        #
        # or:
        #
        # while foo; do
        #       things
        # done
        #
        # or equivalently:
        #
        # while foo
        # do
        #       things
        # done
        #
        # indent after do
        try %{ execute-keys -draft <space> k <a-x> <a-k> \bdo$ <ret> j <a-gt> }
        # deindent after done
        try %{ execute-keys -draft <space> k <a-x> <a-k> \bdone$ <ret> K <a-&> j <a-lt> j K <a-&> }

        # Indent if/then/else syntax, e.g.:
        # if [ $foo = $bar ]; then
        #       things
        # else
        #       other_things
        # fi
        #
        # or equivalently:
        # if [ $foo = $bar ]
        # then
        #       things
        # else
        #       other_things
        # fi
        #
        # indent after then
        try %{ execute-keys -draft <space> k <a-x> <a-k> \bthen$ <ret> j <a-gt> }
        # deindent after fi
        try %{ execute-keys -draft <space> k <a-x> <a-k> \bfi$ <ret> K <a-&> j <a-lt> j K <a-&> }
        # deindent and reindent after else - deindent the else, then back
        # down and return to the previous indent level.
        try %{ execute-keys -draft <space> k <a-x> <a-k> \belse$ <ret> <a-lt> j }

        # Indent case syntax, e.g.:
        # case "$foo" in
        #       bar) thing1;;
        #       baz)
        #               things
        #               ;;
        #       *)
        #               default_things
        #               ;;
        # esac
        #
        # or equivalently:
        # case "$foo"
        # in
        #       bar) thing1;;
        # esac
        #
        # indent after in
        try %{ execute-keys -draft <space> k <a-x> <a-k> \bin$ <ret> j <a-gt> }
        # deindent after esac
        try %{ execute-keys -draft <space> k <a-x> <a-k> \besac$ <ret> <a-lt> j K <a-&> }
        # indent after )
        try %{ execute-keys -draft <space> k <a-x> <a-k> ^\s*\(?[^(]+[^)]\)$ <ret> j <a-gt> }
        # deindent after ;;
        try %{ execute-keys -draft <space> k <a-x> <a-k> ^\s*\;\;$ <ret> j <a-lt> }

        # Indent compound commands as logical blocks, e.g.:
        # {
        #       thing1
        #       thing2
        # }
        #
        # or in a function definition:
        # foo () {
        #       thing1
        #       thing2
        # }
        #
        # We don't handle () delimited compond commands - these are technically very
        # similar, but the use cases are quite different and much less common.
        #
        # Note that in this context the '{' and '}' characters are reserved
        # words, and hence must be surrounded by a token separator - typically
        # white space (including a newline), though technically it can also be
        # ';'. Only vertical white space makes sense in this context, though,
        # since the syntax denotes a logical block, not a simple compound command.
        try %= execute-keys -draft <space> k <a-x> <a-k> (\s|^)\{$ <ret> j <a-gt> =
        # deindent closing }
        try %= execute-keys -draft <space> k <a-x> <a-k> ^\s*\}$ <ret> <a-lt> j K <a-&> =
        # deindent closing } when after cursor
        try %= execute-keys -draft <a-x> <a-k> ^\h*\} <ret> gh / \} <ret> m <a-S> 1<a-&> =

    ]
]

]