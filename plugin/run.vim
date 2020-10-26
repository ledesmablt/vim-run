if exists('g:loaded_run') || &compatible
  " finish
endif
let g:loaded_run = 1

" user vars
let g:run_quiet_default       = get(g:, 'run_quiet_default', 0)
let g:rundir                  = get(g:, 'rundir',  $HOME . '/.vim/rundir')
let g:runcmdpath              = get(g:, 'runcmdpath', '/tmp/vim-run-cmd')

" script vars
let s:run_jobs                = get(s:, 'run_jobs', {})
let s:run_last_command        = get(s:, 'run_last_command', '')
let s:run_last_options        = get(s:, 'run_last_options', {})
let s:run_killall_ongoing     = get(s:, 'run_killall_ongoing', 0)

" init
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" commands
command -nargs=* -complete=file Run :call Run(<q-args>)
command -nargs=* -complete=file RunQuiet :call RunQuiet(<q-args>)
command -nargs=* -complete=file RunWatch :call RunWatch(<q-args>)
command RunAgain :call RunAgain()
command RunListToggle :call RunListToggle()
command RunClear :call RunClear(['DONE', 'FAILED', 'KILLED'])
command RunClearDone :call RunClear(['DONE'])
command RunClearFailed :call RunClear(['FAILED', 'KILLED'])
command RunClearKilled :call RunClear(['KILLED'])
command -nargs=1 -complete=custom,_ListRunningJobs RunKill :call RunKill(<q-args>)
command RunKillAll :call RunKillAll()
command RunDeleteLogs :call RunDeleteLogs()


" main functions
function! RunListToggle()
  if _IsQFOpen()
    cclose
  else
    call _UpdateRunJobs()
    copen
  endif
endfunction

function! RunClear(status_list)
  " user confirm
  let confirm = input(
        \ 'Clear all jobs with status ' . a:status_list->join('/') . '? (Y/n) '
        \ )
  if confirm !=? 'Y'
    return
  endif

  " remove all jobs that match status_list
  let clear_count = 0
  for job in s:run_jobs->values()
    let status_match = a:status_list->index(job['status']) >= 0
    if status_match
      exec 'bd! ' . job['bufname']
      unlet s:run_jobs[job['timestamp']]
      let clear_count += 1
    endif
  endfor
  call _RunAlertNoFocus('Cleared ' . clear_count . ' jobs.', {'quiet': 1})
endfunction

function! RunKill(job_key)
  if !has_key(s:run_jobs, a:job_key)
    call _PrintError('Job key not found.')
    return
  endif
  let job = s:run_jobs[a:job_key]
  if job['status'] !=# 'RUNNING'
    if !s:run_killall_ongoing
      echom 'Job already finished.'
    endif
    return 0
  else
    call job_stop(job['job'], 'kill')
    return 1
  endif
endfunction

function! RunKillAll()
  " user confirm
  let running_jobs = _ListRunningJobs()->split("\n")
  if len(running_jobs) ==# 0
    call _PrintWarning('No jobs are running.')
    return
  endif

  let confirm = input('Kill all running jobs? (Y/n) ')
  if confirm !=? 'Y'
    return
  endif
  let s:run_killed_jobs = 0
  let s:run_killall_ongoing = len(running_jobs)
  for job_key in running_jobs
    call RunKill(job_key)
  endfor
endfunction

function! RunDeleteLogs()
  " user confirm
  if len(_ListRunningJobs()) > 0
    call _PrintError('Cannot delete logs while jobs are running.')
    return
  endif
  let confirm = input('Delete all logs from ' . g:rundir . '? (Y/n) ')
  if confirm !=? 'Y'
    return
  endif
  call system('rm ' . g:rundir . '/*.log')
  redraw | echom 'Deleted all logs.'
endfunction

function! RunQuiet(cmd)
  call Run(a:cmd, { 'quiet': 1 })
endfunction

function! RunWatch(cmd)
  call Run(a:cmd, { 'watch': 1, 'quiet': 1 })
endfunction

function! RunAgain()
  if len(s:run_last_command) ==# 0
    call _PrintError('Please run a command first.')
    return
  endif
  call Run(s:run_last_command, s:run_last_options)
endfunction

function! Run(cmd, ...)
  " check if command provided
  if len(trim(a:cmd)) ==# 0
    call _PrintError('Please provide a command.')
    return
  endif

  " get options dict
  let options = get(a:, 1, 0)
  if type(options) != 4
    let options = {}
  endif
  let s:run_last_command = a:cmd
  let s:run_last_options = options

  let timestamp = strftime('%Y%m%d_%H%M%S')
  if has_key(s:run_jobs, timestamp)
    call _PrintError('Please wait at least 1 second before starting a new job.')
    return
  endif
  let shortcmd = _CleanCmdName(a:cmd)
  let fname = timestamp . '__' . shortcmd . '.log'
  let fpath = g:rundir . '/' . fname
  let temppath = '/tmp/vim-run.' . timestamp . '.log'
  let execpath = g:runcmdpath . '-exec'
  
  " run job as shell command to tempfile w/ details
  execute 'redir! > ' . g:runcmdpath
    silent echo a:cmd
  redir END
  execute 'redir! > ' . execpath
    silent echo 'printf COMMAND:\ '
    silent echo 'cat ' .  g:runcmdpath . ' | tail -n +2'
    silent echo 'printf "\n\n"'
    silent echo  $SHELL . ' ' . g:runcmdpath 
  redir END
  let job = job_start([$SHELL, execpath]->join(' '), {
        \ 'cwd': getcwd(),
        \ 'out_io': 'buffer', 'out_name': temppath,
        \ 'out_msg': 0, 'out_modifiable': 0,
        \ 'out_cb': '_RunOutCB',
        \ 'close_cb': '_RunCloseCB',
        \ 'pty': 1 
        \ })
  
  " get job info for global job dict
  let info = job_info(job)
  let pid = info['process']
  let job_obj = {
        \ 'pid': pid,
        \ 'command': a:cmd,
        \ 'bufname': temppath,
        \ 'filename': fpath,
        \ 'timestamp': timestamp,
        \ 'job': job,
        \ 'status': 'RUNNING',
        \ 'options': options
        \ }
  let s:run_jobs[timestamp] = job_obj
  let msg = "[" . timestamp . "] " . a:cmd . " - output streaming to buffer "
        \ . bufnr(temppath)

  if has_key(options, 'watch')
    exec 'e ' . temppath
  endif
  call _RunAlertNoFocus(msg, options)
endfunction


" utility
function! _ListRunningJobs(...)
  return copy(s:run_jobs)->filter('v:val.status ==# "RUNNING"')
        \ ->keys()->join("\n")
endfunction

function! _IsQFOpen()
  return len(filter(range(1, winnr('$')), 'getwinvar(v:val, "&ft") ==# "qf"')) > 0
endfunction

function! _CleanCmdName(cmd)
  " replace dir-breaking chars
  return substitute(split(a:cmd, ' ')[0], '[\/]', '', 'g')
endfunction

function! _UpdateRunJobs()
  let g:qf_output = []
  let run_jobs_sorted = reverse(sort(s:run_jobs->values(), {
        \ v1, v2 -> v1.timestamp ==# v2.timestamp ? 0 
        \ : v1.timestamp > v2.timestamp ? 1 : -1
        \ }))
  for val in run_jobs_sorted
    let qf_item = {
      \ 'lnum': 1
      \ }
    if job_status(val['job']) ==# 'run'
      let qf_item['bufnr'] = bufnr(val['bufname'])
      let status = 'RUNNING'
    else
      let qf_item['filename'] = val['filename']
      let exitval = job_info(val['job'])['exitval']
      let status = exitval ==# 0 ? 'DONE' : exitval ==# -1 ? 'KILLED' : 'FAILED'
    endif
    let qf_item['text'] = status . ' - ' . val['command']

    " update output and global jobs dict
    call add(g:qf_output, qf_item)
    call extend(s:run_jobs[val['timestamp']], { 'status': status })
  endfor
  call setqflist(g:qf_output)
endfunction

function! _RunAlertNoFocus(content, ...)
  let options = get(a:, 1, 0)
  if type(options) != 4
    let options = {}
  endif

  call _UpdateRunJobs()
  if (!g:run_quiet_default || _IsQFOpen()) && !has_key(options, 'quiet')
    copen
  endif
  redraw | echom a:content
endfunction

function! _GetJobWithObject(job)
  let pid = job_info(a:job)['process']
  for job in s:run_jobs->values()
    if job['pid'] ==# pid
      return job
    endif
  endfor
endfunction

function! _PrintError(msg, ...)
  echohl ErrorMsg | echomsg a:msg | echohl None
endfunction

function! _PrintWarning(msg, ...)
  echohl WarningMsg | echomsg a:msg | echohl None
endfunction


" callbacks
function! _RunOutCB(channel, msg)
  let job = _GetJobWithObject(ch_getjob(a:channel))
  let fname = job['filename']
  execute 'redir >> ' . fname
    silent echo a:msg
  redir END
endfunction

function! _RunCloseCB(channel)
  let job = ch_getjob(a:channel)
  let info = _GetJobWithObject(job)
  let exitval = job_info(info['job'])['exitval']

  if s:run_killall_ongoing
    if exitval != -1
      " no action if killall ongoing
      return
    endif
    let s:run_killed_jobs += 1

    " killall finished
    if s:run_killed_jobs ==# s:run_killall_ongoing
      let s:run_killall_ongoing = 0
      let msg = s:run_killed_jobs . 
            \ (s:run_killed_jobs > 1 ? ' jobs killed.' : ' job killed.')
      call _RunAlertNoFocus(msg, {'quiet': 1})
    endif
    return
  endif

  " job stop message
  if exitval ==# -1
    call _RunAlertNoFocus('Job ' . info['timestamp'] . ' killed.', {'quiet': 1})
  else
    let msg = '[' . info['timestamp'] . '] completed.'
    call _RunAlertNoFocus(msg, info['options'])
  endif
endfunction
