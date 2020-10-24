#!/bin/sh
# quick and dirty install script

mkdir -p ~/.config/nvim 2> /dev/null

# check if python3 is available
if ! command -v python3 &> /dev/null
then
    echo "python3 could not be found"
    exit
fi

# check if ansible is available
if ! command -v ansible &> /dev/null
then
    { # try
        python3 -m pip install --user ansible
    } || { # catch
        echo "ansible not found / fail to install"
        exit
    }
fi

ansible-galaxy install geerlingguy.dotfiles gantsign.oh-my-zsh

cat <<EOF > /tmp/install.yml
- hosts: localhost
  roles:
    - { role: gantsign.oh-my-zsh }
    - { role: geerlingguy.dotfiles }
  vars:
    users:
      - username: ${USERNAME:-$USER}
    dotfiles_repo_local_destination: "~/.dotfiles"
    dotfiles_repo: "https://github.com/DrMeosch/dotfiles.git"
    dotfiles_files:
      - .zshrc
      - .p10k.zsh
      - .config/nvim/init.vim
      - .tmux.conf
  tasks:
    - name: install zsh-syntax-highlighting
      git:
        repo: https://github.com/zsh-users/zsh-syntax-highlighting.git
        dest: $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

    - name: install p10k
      git:
        repo: https://gitee.com/romkatv/powerlevel10k.git
        dest: $HOME/.oh-my-zsh/custom/themes/powerlevel10k
        depth: 1
EOF

# install dotfiles
ansible-playbook -v /tmp/install.yml
