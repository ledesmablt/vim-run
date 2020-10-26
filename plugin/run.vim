" ============================================================================
" File:         run.vim
" Maintainer:   Benj Ledesma <benj.ledesma@gmail.com>
" License:	    The MIT License (see LICENSE file)
" Description:  Run, view, and manage UNIX shell commands with ease from your
"               favorite code editor.
"
" ============================================================================

" prerequisites
if len($SHELL) == 0
  echoerr 'Could not load vim-run - $SHELL environment variable missing.'
  finish
endif
if len($HOME) == 0 && !exists('g:rundir')
  echoerr "Could not load vim-run - $HOME environment variable missing."
        \ . " You may assign a directory to the variable g:rundir"
        \ . " to fix this issue."
  finish
endif
if !isdirectory('/tmp')
  echoerr 'Could not load vim-run - /tmp directory not detected.'
  finish
endif

" commands
command -nargs=* -complete=file Run :call run#Run(<q-args>)
command -nargs=* -complete=file RunQuiet :call run#RunQuiet(<q-args>)
command -nargs=* -complete=file RunWatch :call run#RunWatch(<q-args>)
command RunAgain :call run#RunAgain()
command RunListToggle :call run#RunListToggle()
command RunClear :call run#RunClear(['DONE', 'FAILED', 'KILLED'])
command RunClearDone :call run#RunClear(['DONE'])
command RunClearFailed :call run#RunClear(['FAILED', 'KILLED'])
command RunClearKilled :call run#RunClear(['KILLED'])
command -nargs=1 -complete=custom,run#list_running_jobs RunKill :call run#RunKill(<q-args>)
command RunKillAll :call run#RunKillAll()
command RunDeleteLogs :call run#RunDeleteLogs()
