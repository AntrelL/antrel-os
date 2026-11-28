# antrel-os: interactive bash.
[[ $- != *i* ]] && return

# omp and other per-user programs live in ~/.local/bin.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH=$HOME/.local/bin:$PATH ;;
esac

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
