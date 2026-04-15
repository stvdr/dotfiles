#!/bin/bash
echo backing up existing ~/.config/nvim/init.vim..
mv ~/.config/nvim/init.vim ~/.config/nvim/init.vim.$(date +"%s")
echo backing up existing .vimrc..
mv ~/.vimrc ~/.vimrc.backup.$(date +"%s")
echo "source $PWD/vim/vimrc" > ~/.vimrc
mkdir -p ~/.config/nvim
echo "source ~/.vimrc" > ~/.config/nvim/init.vim

echo backing up existing .tmux.conf..
mv ~/.tmux.conf ~/.tmux.conf.backup.$(date +"%s")
cat > ~/.tmux.conf <<EOF
set-environment -g DOTFILES_DIR '$PWD'
source-file $PWD/tmux/tmux.conf
EOF

echo backing up existing ~/.zshrc..
mv ~/.zshrc ~/.zshrc.backup.$(date +"%s")
echo "source $PWD/zsh/zshrc" > ~/.zshrc

chmod +x "$PWD/tmux/"*.sh

# Install TPM (tmux plugin manager) if not present
if [ ! -d ~/.tmux/plugins/tpm ]; then
    echo "Installing tmux plugin manager..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo removing backups..
rm ~/.zshrc.backup.* ~/.vimrc.backup.* ~/.tmux.conf.backup.*
