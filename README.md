# Vim-Run

Run, view, and manage UNIX shell commands with ease from your favorite code editor.
(a work in progress)

<!-- insert gif demo here -->

## Installation
Using [vim-plug](https://github.com/junegunn/vim-plug):
```vim
Plug 'ledesmablt/vim-run'
```

Using Vim's built-in package support:
```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone http://github.com/ledesmablt/vim-run
vim -c 'helptags vim-run/doc' -c quit
```

## Commands
```vim
" start jobs
:Run {command}
:RunQuiet {command}
:RunWatch {command}
:RunAgain

" kill jobs
:RunKill {job_key}
:RunKillAll

" view & manage jobs
:RunListToggle
:RunClear
:RunClearDone
:RunClearFailed
:RunClearKilled
```
