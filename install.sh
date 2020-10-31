#!/bin/sh

touch .profile
git clone https://github.com/DrMeosch/dotfiles .dotfiles && mkdir -p ~/.config/nvim 2> /dev/null && \
    ln -s ~/.dotfiles/{.p10k.zsh,.tmux.conf,.zshrc} . && \
    ln -s ~/.dotfiles/.config/nvim/init.vim .config/nvim && \
    git clone https://github.com/ohmyzsh/ohmyzsh .oh-my-zsh && \
    git clone https://gitee.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k --depth 1 && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting