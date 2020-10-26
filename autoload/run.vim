if exists('g:loaded_run')
  " finish
endif
let g:loaded_run = 1

" user vars
let g:rundir                  = get(g:, 'rundir',  $HOME . '/.vim/rundir')
let g:runcmdpath              = get(g:, 'runcmdpath', '/tmp/vim-run-cmd')
let g:run_quiet_default       = get(g:, 'run_quiet_default', 0)

" script vars
let s:run_jobs                = get(s:, 'run_jobs', {})
let s:run_last_command        = get(s:, 'run_last_command', '')
let s:run_last_options        = get(s:, 'run_last_options', {})
let s:run_killall_ongoing     = get(s:, 'run_killall_ongoing', 0)

" init
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" main functions
function! run#RunListToggle()
  if run#_IsQFOpen()
    cclose
  else
    call run#_UpdateRunJobs()
    silent copen
  endif
endfunction

function! run#RunClear(status_list)
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
  call run#_RunAlertNoFocus('Cleared ' . clear_count . ' jobs.', {'quiet': 1})
endfunction

function! run#RunKill(job_key)
  if !has_key(s:run_jobs, a:job_key)
    call run#_PrintFormatted('ErrorMsg', 'Job key not found.')
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

function! run#RunKillAll()
  " user confirm
  let running_jobs = run#_ListRunningJobs()->split("\n")
  if len(running_jobs) ==# 0
    call run#_PrintFormatted('WarningMsg', 'No jobs are running.')
    return
  endif

  let confirm = input('Kill all running jobs? (Y/n) ')
  if confirm !=? 'Y'
    return
  endif
  let s:run_killed_jobs = 0
  let s:run_killall_ongoing = len(running_jobs)
  for job_key in running_jobs
    call run#RunKill(job_key)
  endfor
endfunction

function! run#RunDeleteLogs()
  " user confirm
  if len(run#_ListRunningJobs()) > 0
    call run#_PrintFormatted('ErrorMsg', 'Cannot delete logs while jobs are running.')
    return
  endif
  let confirm = input('Delete all logs from ' . g:rundir . '? (Y/n) ')
  if confirm !=? 'Y'
    return
  endif
  call system('rm ' . g:rundir . '/*.log')
  call run#_PrintFormatted('WarningMsg', 'Deleted all logs.')
endfunction

function! run#RunQuiet(cmd)
  call run#Run(a:cmd, { 'quiet': 1 })
endfunction

function! run#RunWatch(cmd)
  call run#Run(a:cmd, { 'watch': 1, 'quiet': 1 })
endfunction

function! run#RunAgain()
  if len(s:run_last_command) ==# 0
    call run#_PrintFormatted('ErrorMsg', 'Please run a command first.')
    return
  endif
  call run#Run(s:run_last_command, s:run_last_options)
endfunction

function! run#Run(cmd, ...)
  " check if command provided
  if len(trim(a:cmd)) ==# 0
    call run#_PrintFormatted('ErrorMsg', 'Please provide a command.')
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
    call run#_PrintFormatted('ErrorMsg', 'Please wait at least 1 second before starting a new job.')
    return
  endif
  let shortcmd = run#_CleanCmdName(a:cmd)
  let fname = timestamp . '__' . shortcmd . '.log'
  let fpath = g:rundir . '/' . fname
  let temppath = '/tmp/vim-run.' . timestamp . '.log'
  let execpath = g:runcmdpath . '-exec'
  
  " run job as shell command to tempfile w/ details
  call writefile([a:cmd], g:runcmdpath)
  call writefile([
        \ 'printf COMMAND:\ ', 'cat ' .  g:runcmdpath,
        \ 'echo WORKDIR: ' . getcwd(),
        \ 'echo STARTED: ' . strftime('%Y-%m-%d %H:%M:%S'),
        \ 'printf "\n"',
        \ $SHELL . ' ' . g:runcmdpath
        \], execpath)
  let job = job_start([$SHELL, execpath]->join(' '), {
        \ 'cwd': getcwd(),
        \ 'out_io': 'buffer', 'out_name': temppath,
        \ 'out_msg': 0, 'out_modifiable': 0,
        \ 'out_cb': 'run#_RunOutCB',
        \ 'close_cb': 'run#_RunCloseCB',
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
  let msg = '[' . timestamp . '] started - ' . trim(a:cmd)

  if get(options, 'watch')
    exec 'e ' . temppath
  endif
  call run#_RunAlertNoFocus(msg, options)
endfunction


" utility
function! run#_ListRunningJobs(...)
  return deepcopy(s:run_jobs)->filter('v:val.status ==# "RUNNING"')
        \ ->keys()->join("\n")
endfunction

function! run#_IsQFOpen()
  return len(filter(range(1, winnr('$')), 'getwinvar(v:val, "&ft") ==# "qf"')) > 0
endfunction

function! run#_CleanCmdName(cmd)
  " replace dir-breaking chars
  return substitute(split(a:cmd, ' ')[0], '[\/]', '', 'g')
endfunction

function! run#_UpdateRunJobs()
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
  silent call setqflist(g:qf_output)
endfunction

function! run#_RunAlertNoFocus(content, ...)
  let options = get(a:, 1, 0)
  if type(options) != 4
    let options = {}
  endif

  call run#_UpdateRunJobs()
  if (!g:run_quiet_default || run#_IsQFOpen()) && !get(options, 'quiet')
    silent copen
  endif
  let msg_format = get(options, 'msg_format', 'Normal')
  call run#_PrintFormatted(msg_format, a:content)
endfunction

function! run#_GetJobWithObject(job)
  let pid = job_info(a:job)['process']
  for job in s:run_jobs->values()
    if job['pid'] ==# pid
      return job
    endif
  endfor
endfunction

function! run#_PrintFormatted(format, msg)
  exec 'redraw | echohl ' . a:format . ' | echomsg a:msg | echohl None'
endfunction


" callbacks
function! run#_RunOutCB(channel, msg)
  let job = run#_GetJobWithObject(ch_getjob(a:channel))
  let fname = job['filename']
  call writefile([a:msg], fname, "a")
endfunction

function! run#_RunCloseCB(channel)
  let job = ch_getjob(a:channel)
  let info = run#_GetJobWithObject(job)
  let exitval = job_info(info['job'])['exitval']

  let kill_options = {'quiet': 1, 'msg_format': 'WarningMsg'}
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
      call run#_RunAlertNoFocus(msg, kill_options)
    endif
    return
  endif

  " job stop message
  let options = deepcopy(info['options'])
  if exitval ==# -1
    let msg = '[' . info['timestamp'] . '] killed.'
    let options = {'quiet': 1, 'msg_format': 'WarningMsg'}
  elseif exitval ==# 0
    let msg = '[' . info['timestamp'] . '] completed.'
    let options['msg_format'] = 'Green'
  else
    let msg = '[' . info['timestamp'] . '] failed.'
    let options['msg_format'] = 'Red'
  endif
  call run#_RunAlertNoFocus(msg, options)
endfunction