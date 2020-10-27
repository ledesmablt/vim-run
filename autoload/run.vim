if exists('s:loaded_run')
  finish
endif
let s:loaded_run = 1

" script vars
let s:runcmdpath              = get(s:, 'runcmdpath', '/tmp/vim-run-cmd')
let s:run_jobs                = get(s:, 'run_jobs', {})
let s:run_last_command        = get(s:, 'run_last_command', '')
let s:run_last_options        = get(s:, 'run_last_options', {})
let s:run_killall_ongoing     = get(s:, 'run_killall_ongoing', 0)
let s:run_timestamp_format    = get(s:, 'run_timestamp_format', '%Y-%m-%d %H:%M:%S')

" init rundir
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" main functions
function! run#Run(cmd, ...)
  " check if command provided
  if len(trim(a:cmd)) ==# 0
    call run#print_formatted('ErrorMsg', 'Please provide a command.')
    return
  endif

  " format filename timestamp (should be unique)
  let fname_ts_format = '%Y%m%d_%H%M%S'
  if exists('*strftime')
    let timestamp = strftime(fname_ts_format)
  else
    let timestamp = trim(system('date +"' . fname_ts_format . '"'))
  endif
  if has_key(s:run_jobs, timestamp)
    call run#print_formatted('ErrorMsg', 'Please wait at least 1 second before starting a new job.')
    return
  endif

  " get options dict
  let options = get(a:, 1, 0)
  if type(options) != 4
    let options = {}
  endif
  let s:run_last_command = a:cmd
  let s:run_last_options = options

  let shortcmd = run#clean_cmd_name(a:cmd)
  let fname = timestamp . '__' . shortcmd . '.log'
  let fpath = g:rundir . '/' . fname
  let temppath = '/tmp/vim-run.' . timestamp . '.log'
  let execpath = s:runcmdpath . '-exec'
  
  " run job as shell command to tempfile w/ details
  let date_cmd = 'date +"' . s:run_timestamp_format . '"'
  call writefile([a:cmd], s:runcmdpath)
  call writefile([
        \ 'printf "COMMAND: "', 'cat ' .  s:runcmdpath,
        \ 'echo WORKDIR: ' . getcwd(),
        \ 'printf "STARTED: "',
        \ date_cmd,
        \ 'printf "\n"',
        \ $SHELL . ' ' . s:runcmdpath,
        \ 'EXITVAL=$?',
        \ 'STATUS=$([ $EXITVAL -eq 0 ] && echo "FINISHED" || echo "FAILED (status $EXITVAL)")',
        \ 'printf "\n$STATUS: "',
        \ date_cmd,
        \ 'exit $EXITVAL',
        \ ], execpath)

  let job_options = {
        \ 'cwd': getcwd(),
        \ 'out_msg': 0, 'out_modifiable': 0,
        \ 'close_cb': 'run#close_cb',
        \ 'pty': 1 
        \ }

  let is_nostream = get(options, 'nostream') || g:run_nostream_default
  if is_nostream
    call extend(job_options, {
        \ 'out_io': 'file', 'out_name': fpath
        \ })
  else
    call extend(job_options, {
        \ 'out_io': 'buffer', 'out_name': temppath,
        \ 'out_cb': 'run#out_cb'
        \ })
  endif
  let job = job_start([$SHELL, execpath]->join(' '), job_options)
  
  " get job info for global job dict
  let info = job_info(job)
  let job_obj = {
        \ 'pid': info['process'],
        \ 'command': a:cmd,
        \ 'bufname': (is_nostream ? fpath : temppath),
        \ 'filename': fpath,
        \ 'timestamp': timestamp,
        \ 'job': job,
        \ 'status': 'RUNNING',
        \ 'save': g:run_autosave_logs,
        \ 'options': options
        \ }
  let s:run_jobs[timestamp] = job_obj
  let msg = '[' . timestamp . '] started - ' . trim(a:cmd)

  if get(options, 'watch')
    silent exec 'e ' . temppath
  elseif get(options, 'split')
    silent exec 'belowr sp ' . temppath
  elseif get(options, 'vsplit')
    silent exec 'rightb vs ' . temppath
  endif
  call run#alert_and_update(msg, options)
endfunction

function! run#RunQuiet(cmd)
  call run#Run(a:cmd, { 'quiet': 1 })
endfunction

function! run#RunWatch(cmd)
  call run#Run(a:cmd, { 'watch': 1, 'quiet': 1 })
endfunction

function! run#RunSplit(cmd)
  call run#Run(a:cmd, { 'split': 1 })
endfunction

function! run#RunVSplit(cmd)
  call run#Run(a:cmd, { 'vsplit': 1 })
endfunction

function! run#RunNoStream(cmd)
  call run#Run(a:cmd, { 'nostream': 1 })
endfunction

function! run#RunAgain()
  if len(s:run_last_command) ==# 0
    call run#print_formatted('ErrorMsg', 'Please run a command first.')
    return
  endif
  call run#Run(s:run_last_command, s:run_last_options)
endfunction

function! run#RunKill(job_key)
  if !has_key(s:run_jobs, a:job_key)
    call run#print_formatted('ErrorMsg', 'Job key not found.')
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
  let running_jobs = run#list_running_jobs()->split("\n")
  if len(running_jobs) ==# 0
    call run#print_formatted('WarningMsg', 'No jobs are running.')
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

function! run#RunListToggle()
  if run#is_qf_open()
    cclose
  else
    call run#update_run_jobs()
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
      silent exec 'bw! ' . job['bufname']
      unlet s:run_jobs[job['timestamp']]
      let clear_count += 1
    endif
  endfor
  call run#alert_and_update(
        \ 'Cleared ' . clear_count . (clear_count > 1 ? ' jobs.' : ' job.'),
        \ {'quiet': 1}
        \ )
endfunction

function! run#RunSaveLog(job_key)
  if !has_key(s:run_jobs, a:job_key)
    call run#print_formatted('ErrorMsg', 'Job key not found.')
    return
  endif
  let job = s:run_jobs[a:job_key]
  if job['status'] ==# 'RUNNING'
    call run#print_formatted('ErrorMsg', 'Cannot save the logs of a running job.')
    return
  endif
  if filereadable(job['filename'])
    call run#print_formatted('WarningMsg', 'Logs already saved.')
    return
  endif
  if !bufexists(job['bufname'])
    call run#print_formatted('ErrorMsg', 'Buffer already wiped.')
    unlet s:run_jobs[a:job_key]
    return
  endif

  "  write from the job buffer if all checks passed
  silent exec 'e ' . job['bufname'] . ' | keepalt w! ' . job['filename']
  let job['save'] = 1
  call run#alert_and_update('Logs saved to ' . job['filename'], {'quiet': 1})
endfunction

function! run#RunBrowseLogs(...)
  let limit = get(a:, 1, g:run_browse_default_limit)
  if type(limit) !=# 0  || limit <= 0
    " must be positive number
    call run#print_formatted('ErrorMsg', 'Please provide a valid number.')
    return
  endif

  let cmd_get_files = "find " . g:rundir . " -type f | sort -r" .
        \ " | head -n " . limit . 
        \ " | xargs -n 1 -I FILE" .
        \ " sh -c 'printf \"FILE \" && echo $(head -1 FILE)'"
  let s:qf_output = []
  for entry in system(cmd_get_files)->trim()->split("\n")
    let qf_item = {}
    let split_str = ' COMMAND: '
    let split_cmd = entry->split(split_str)
    let qf_item['filename'] = split_cmd[0]
    let qf_item['text'] = 'SAVED - ' . split_cmd[1:]->join(split_str)
    call add(s:qf_output, qf_item)
  endfor

  silent call setqflist(s:qf_output)
  silent call setqflist([], 'a', {'title': 'RunLogs'})
  let limit = min([limit, len(s:qf_output)])
  let msg = 'Showing the last ' . limit . ' saved logs.'
  call run#print_formatted('Normal', msg)
  if !run#is_qf_open()
    silent copen
  endif
endfunction

function! run#RunDeleteLogs()
  " user confirm
  if len(run#list_running_jobs()) > 0
    call run#print_formatted('ErrorMsg', 'Cannot delete logs while jobs are running.')
    return
  endif
  let confirm = input('Delete all logs from ' . g:rundir . '? (Y/n) ')
  if confirm !=? 'Y'
    return
  endif
  call system('rm ' . g:rundir . '/*.log')
  call run#print_formatted('WarningMsg', 'Deleted all logs.')
endfunction


" utility
function! run#update_run_jobs()
  let s:qf_output = []
  let run_jobs_sorted = reverse(sort(s:run_jobs->values(), {
        \ v1, v2 -> v1.timestamp ==# v2.timestamp ? 0 
        \ : v1.timestamp > v2.timestamp ? 1 : -1
        \ }))
  for val in run_jobs_sorted
    let qf_item = {}
    let status = job_status(val['job'])
    let is_nostream = get(val['options'], 'nostream')

    " set the qf buffer / file to open
    if is_nostream || (status !=# 'run' && val['save'])
      let qf_item['filename'] = val['filename']
    else
      let qf_item['bufnr'] = bufnr(val['bufname'])
    endif
    " set the qf message (status)
    if status ==# 'run'
      let status = 'RUNNING'
    else
      let exitval = job_info(val['job'])['exitval']
      let status = exitval ==# 0 ? 'DONE' : exitval ==# -1 ? 'KILLED' : 'FAILED'
    endif
    let qf_item['text'] = status . ' - ' . val['command']

    " update output and global jobs dict
    call add(s:qf_output, qf_item)
    call extend(s:run_jobs[val['timestamp']], { 'status': status })
  endfor

  silent call setqflist(s:qf_output)
  silent call setqflist([], 'a', {'title': 'RunList'})
endfunction

function! run#alert_and_update(content, ...)
  let options = get(a:, 1, 0)
  if type(options) != 4
    let options = {}
  endif

  call run#update_run_jobs()
  if (!g:run_quiet_default || run#is_qf_open()) && !get(options, 'quiet')
    silent copen
  endif
  let msg_format = get(options, 'msg_format', 'Normal')
  call run#print_formatted(msg_format, a:content)
endfunction

function! run#get_job_with_object(job)
  let pid = job_info(a:job)['process']
  for job in s:run_jobs->values()
    if job['pid'] ==# pid
      return job
    endif
  endfor
endfunction

function! run#list_running_jobs(...)
  return deepcopy(s:run_jobs)->filter('v:val.status ==# "RUNNING"')
        \ ->keys()->join("\n")
endfunction

function! run#list_unsaved_jobs(...)
  return deepcopy(s:run_jobs)->filter('v:val.save ==# 0 && v:val.status !=# "RUNNING"')
        \ ->keys()->join("\n")
endfunction

function! run#is_qf_open()
  return len(filter(range(1, winnr('$')), 'getwinvar(v:val, "&ft") ==# "qf"')) > 0
endfunction

function! run#clean_cmd_name(cmd)
  " replace dir-breaking chars
  return substitute(split(a:cmd, ' ')[0], '[\/]', '', 'g')
endfunction

function! run#print_formatted(format, msg)
  exec 'redraw | echohl ' . a:format . ' | echomsg a:msg | echohl None'
endfunction


" callbacks
function! run#out_cb(channel, msg)
  if !g:run_autosave_logs
    return
  endif

  let job = run#get_job_with_object(ch_getjob(a:channel))
  let fname = job['filename']
  call writefile([a:msg], fname, "a")
endfunction

function! run#close_cb(channel)
  let job = ch_getjob(a:channel)
  let info = run#get_job_with_object(job)
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
      call run#alert_and_update(msg, kill_options)
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
  call run#alert_and_update(msg, options)
endfunction
