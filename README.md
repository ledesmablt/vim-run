# vim-run

Run, view, and manage UNIX shell commands with ease from your
favorite code editor.

![vim-run-demo-3](https://user-images.githubusercontent.com/22242264/97441234-73c9e500-1963-11eb-81ae-72bcab2b8b87.gif)

## Introduction

Running external commands with vim has always been clunky to work with.
```
:!apt update                          (can't edit while running)
:!apt update &                        (stdout hijacks your screen)
:!apt update > some/file.log &        (logs available only when done)
```

In most cases, it would be a lot more convenient to just open up a new
terminal (maybe with `:term`, `tmux`, or a new window in your OS) and run your
command from there.

But what if you don't want to worry about managing several active terminal
sessions? Maybe you'd prefer to just keep one window open - vim - and run
processes without losing too much screen real estate.

This plugin attempts to solve that problem and provide a more intuitive
experience around running processess asynchronously.


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
:Run [<command>]
:RunQuiet [<command>]
:RunWatch [<command>]
:RunSplit [<command>]
:RunVSplit [<command>]
:RunNoStream [<command>]
:RunAgain
:RunAgainEdit
:RunSendKeys [<text>]

" kill jobs
:RunKill [<job_key>]
:RunKillAll

" view & manage jobs
:RunListToggle
:RunClear
:RunClearDone
:RunClearFailed
:RunClearKilled

" manage log files
:RunSaveLog [<job_key>]
:RunBrowseLogs [<limit>]
:RunDeleteLogs
```

## Configuration
```vim
let g:rundir = ~/.vim/rundir
let g:run_shell = $SHELL
let g:run_quiet_default = 0
let g:run_autosave_logs = 0
let g:run_nostream_default = 0
let g:run_browse_default_limit = 10
```

More details in the docs - `:h vim-run`
