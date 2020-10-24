# Vim-Run

Run, view, and manage UNIX shell commands with ease from your favorite code editor.
(a work in progress)

%%insert image demo here

## Installation
Install using your favorite package manager, or use Vim's built-in package support:
```bash
mkdir -p ~/.vim/pack/plugins/start
cd ~/.vim/pack/plugins/start
git clone http://github.com/ledesmablt/vim-run
vim -c 'helptags vim-run/doc' -c quit
```

## Commands
```
:Run {command}
:RunQuiet {command}
:RunList
:RunClear
:RunClearDone
:RunClearFail
```
