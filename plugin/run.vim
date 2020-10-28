" ============================================================================
" File:         run.vim
" Maintainer:   Benj Ledesma <benj.ledesma@gmail.com>
" License:	    The MIT License (see LICENSE file)
" Description:  Run, view, and manage UNIX shell commands with ease from your
"               favorite code editor.
"
" ============================================================================

" prerequisites
let load_fail = 1
let fail_msg = 'Could not load vim-run - '
if !isdirectory('/tmp')
  let fail_msg .= '/tmp directory not detected.'
elseif len($SHELL) == 0 && !exists('g:run_shell')
  let fail_msg .= '$SHELL environment variable missing.'
        \ . ' You may assign a shell path to the variable g:run_shell'
        \ . ' to fix this issue.'
elseif len($HOME) == 0 && !exists('g:rundir')
  let fail_msg .= "$HOME environment variable missing."
        \ . " You may assign a directory to the variable g:rundir"
        \ . " to fix this issue."
else
  let load_fail = 0
endif

if load_fail
  echoerr fail_msg
  finish
endif

" user vars
let g:rundir                   = get(g:, 'rundir',  $HOME . '/.vim/rundir')
let g:run_shell                = get(g:, 'run_shell', $SHELL)
let g:run_quiet_default        = get(g:, 'run_quiet_default', 0)
let g:run_autosave_logs        = get(g:, 'run_autosave_logs', 0)
let g:run_nostream_default     = get(g:, 'run_nostream_default', 0)
let g:run_browse_default_limit = get(g:, 'run_browse_default_limit', 10)

" commands
command -nargs=* -complete=file Run :call run#Run(<q-args>)
command -nargs=* -complete=file RunQuiet :call run#RunQuiet(<q-args>)
command -nargs=* -complete=file RunWatch :call run#RunWatch(<q-args>)
command -nargs=* -complete=file RunSplit :call run#RunSplit(<q-args>)
command -nargs=* -complete=file RunVSplit :call run#RunVSplit(<q-args>)
command -nargs=* -complete=file RunNoStream :call run#RunNoStream(<q-args>)
command RunAgain :call run#RunAgain()
command RunAgainEdit :call run#RunAgainEdit()
command -nargs=* -complete=file RunSendKeys :call run#RunSendKeys(<q-args>)

command -nargs=1 -complete=custom,run#list_running_jobs RunKill :call run#RunKill(<q-args>)
command RunKillAll :call run#RunKillAll()

command RunListToggle :call run#RunListToggle()
command RunClear :call run#RunClear(['DONE', 'FAILED', 'KILLED'])
command RunClearDone :call run#RunClear(['DONE'])
command RunClearFailed :call run#RunClear(['FAILED'])
command RunClearKilled :call run#RunClear(['KILLED'])

command -nargs=1 -complete=custom,run#list_unsaved_jobs RunSaveLog :call run#RunSaveLog(<q-args>)
command -nargs=? RunBrowseLogs :call run#RunBrowseLogs(<args>)
command RunDeleteLogs :call run#RunDeleteLogs()
