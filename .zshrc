if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export TERM="xterm-256color"
export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(github z autojump archlinux zsh-navigation-tools docker cp zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh
source ~/.profile

autoload -U compinit
compinit

export EDITOR='nvim'
export GOPATH=$HOME/.go 
export PATH="$PATH:$HOME/.rvm/bin:$HOME/.go/bin:$HOME/bin" # Add RVM to PATH for scripting

alias ls="ls --color -sh"
alias v="nvim -p"
alias ll="ls -liha"

dirs(){
        name=$(echo $1 | unfurl -u domains)
        x=$(date +%Y%m%d%H%M%S)
        mkdir -p ~/work
        mkdir -p ~/work/$name
        ffuf -u $1FUZZ -D -e asp,aspx,cgi,cfml,CFM,htm,html,json,jsp,php,phtml,pl,py,sh,shtml,sql,txt,xml,xhtml,tar,tar.gz,tgz,war,zip,swp,src,jar,java,log,bin,js,db -t 150 -o ~/work/$name/$name_$x.json
}

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
