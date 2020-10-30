if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export TERM="xterm-256color"
export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="powerlevel10k/powerlevel10k"

ZSH_DISABLE_COMPFIX="true"

plugins=(
  archlinux
  ansible
  aws
  tmux
  docker
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh
source ~/.profile

unsetopt share_history
autoload -U compinit
compinit

[[ ! -f ~/.credentials ]] || source ~/.credentials

export EDITOR='nvim'
export GOPATH=$HOME/.go 
export PATH="$PATH:$HOME/.rvm/bin:$HOME/.go/bin:$HOME/bin" # Add RVM to PATH for scripting

alias ls="ls --color -sh"
alias v="nvim -p"
alias ll="ls -liha"
alias v='nvim -p'
alias phs='python3 -m http.server'

s3ls()
{
    aws s3 ls s3://$1
}

s3cp()
{
    aws s3 cp $2 s3://$1 
}

thewadl()
{ #this grabs endpoints from a application.wadl and puts them in yahooapi.txt
    curl -s $1 | grep path | sed -n "s/.*resource path=\"\(.*\)\".*/\1/p" | tee -a ~/.tools/dirsearch/db/yahooapi.txt
}

am()
{ #runs amass passively and saves to json
    amass enum --passive -d $1 -json $1.json
    jq .name $1.json | sed "s/\"//g"| httprobe -c 60 | tee -a $1-domains.txt
}

crtprobe()
{ #runs httprobe on all the hosts from certspotter
    curl -s https://crt.sh/\?q\=\%.$1\&output\=json | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u | httprobe | tee -a ./all.txt
}

certspotter()
{ 
    curl -s https://certspotter.com/api/v0/certs\?domain=$1 | jq '.[].dns_names[]' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u | grep $1
} #h/t Michiel Prins

crtsh(){
    curl -s https://crt.sh/\?q=\%.$1\&output=json | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u
}

certnmap()
{
    curl https://certspotter.com/api/v0/certs\?domain=$1 | jq '.[].dns_names[]' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u | grep $1  | nmap -T5 -Pn -sS -i - -$
} #h/t Jobert Abma

ipinfo()
{
    curl http://ipinfo.io/$1
}

dirsearch()
{
    python3 ~/.tools/dirsearch/dirsearch.py -u $1 -e $2 -t 50 -b 
}

sqlmap()
{
    python ~/.tools/sqlmap*/sqlmap.py -u $1 
}

ncx()
{
    ncat -lvnp $1
}

crtshdirsearch()
{ #gets all domains from crtsh, runs httprobe and then dir bruteforcers
    curl -s https://crt.sh/\?q=%.$1\&output=json | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u | httprobe -c 50 | grep https | xargs -n1 -I{} python3 ~/.tools/dirsearch/dirsearch.py -u {} -e $2 -t 50 -b 
}


dirs()
{
    name=$(echo $1 | unfurl -u domains)
    x=$(date +%Y%m%d%H%M%S)
    mkdir -p ~/work
    mkdir -p ~/work/$name
    ffuf -u $1FUZZ -D -e asp,aspx,cgi,cfml,CFM,htm,html,json,jsp,php,phtml,pl,py,sh,shtml,sql,txt,xml,xhtml,tar,tar.gz,tgz,war,zip,swp,src,jar,java,log,bin,js,db -t 150 -o ~/work/$name/$name_$x.json
}

checkms()
{
    curl "https://login.microsoftonline.com/getuserrealm.srf?login=username@$1&xml=1"
    echo
    curl "https://outlook.office365.com/autodiscover/autodiscover.json/v1.0/test@$1?Protocol=Autodiscoverv1&RedirectCount=1"
}
checkd()
{
	host -t mx $1
	echo
	host -t ns $1
	echo
	checkms $1
	echo
	echo "Run amass enum and amass intel"
	echo "Check censys.io"
	echo "Check also https://$1.account.box.com"
	echo
	echo "Check PowerMeta.ps1 and FOCA"
	echo "Check MSOLSpray and MailSniper with user accounts from hunter.io and accounts from files' metadata"
}
vvall()
{
    nvim -p $(find $1 -type f \( ! -iname ".*" ! -iname "README.*" \))
}

export POWERSHELL_TELEMETRY_OPTOUT=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export PATH=$PATH:$HOME/.bin

c()
{
	curl -s http://monster:5000/api/cve/$1 | jq .
}

# added by travis gem
[ ! -s $HOME/.travis/travis.sh ] || source $HOME/.travis/travis.sh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

zstyle ':completion:*' menu select
