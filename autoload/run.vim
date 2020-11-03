if exists('s:loaded_run')
  finish
endif
let s:loaded_run = 1

" script vars
let s:run_jobs                = get(s:, 'run_jobs', {})
let s:run_last_command        = get(s:, 'run_last_command', '')
let s:run_last_options        = get(s:, 'run_last_options', {})
let s:run_killall_ongoing     = get(s:, 'run_killall_ongoing', 0)
let s:run_timestamp_format    = get(s:, 'run_timestamp_format', '%Y-%m-%d %H:%M:%S')
let s:run_jobs_to_kill_nvim   = get(s:, 'run_jobs_to_kill_nvim', [])

let s:run_edit_path           = get(s:, 'run_edit_path')
let s:run_edit_cmd_ongoing    = get(s:, 'run_edit_cmd_ongoing', 0)
let s:run_edit_options        = get(s:, 'run_edit_options', {})

let s:run_send_path           = get(s:, 'run_send_path')
let s:run_send_cmd_ongoing    = get(s:, 'run_send_cmd_ongoing', 0)
let s:run_send_timestamp      = get(s:, 'run_send_timestamp', 0)

" constants
let s:run_cmd_path            = '/tmp/vim-run.'
let s:edit_msg                = '# Edit your command here. Save and quit to start running.'

" autocmds
augroup RunCmdBufInput
  let editglob = '/tmp/vim-run.edit*.sh'
  let sendglob = '/tmp/vim-run.send*.sh'
  let tempglob = '/tmp/vim-run.*.log'
  let rundirglob = g:rundir . '/*.log'

  autocmd!
  exec 'autocmd BufWinEnter ' . join([editglob, sendglob, rundirglob], ',')
        \ . ' setlocal bufhidden=wipe'
  exec 'autocmd BufWinEnter ' . join([rundirglob, tempglob], ',')
        \ . ' setlocal ft=log'
  exec 'autocmd BufWinEnter ' . join([rundirglob, tempglob], ',')
        \ . ' setlocal noma'
  exec 'autocmd BufWinLeave ' . editglob . ' call run#cmd_input_finished()'
  exec 'autocmd BufWinLeave ' . sendglob . ' call run#cmd_input_finished({"send":1})'
augroup END

" init rundir
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif


" main functions
function! run#Run(cmd, ...) abort
  let options = get(a:, 1, {})
  if has('nvim')
    let options['nostream'] = 1
    if get(options, 'split') || get(options, 'vsplit')
      call run#print_formatted('ErrorMsg',
            \ 'Streaming output to a buffer is not supported in Neovim.')
      return
    endif
  endif

  " finish editing first
  if s:run_edit_cmd_ongoing
    call run#print_formatted('ErrorMsg', 'Please finish editing the current command.')
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
  
  if empty(trim(a:cmd))
    " no text provided in cmd input
    if get(options, 'is_from_editor') && !get(options, 'edit_last')
      call run#print_formatted('WarningMsg', 'User cancelled command input.')
      return
    endif
    
    " split conflicts with BufWinLeave autocmd
    if get(options, 'split') || get(options, 'vsplit')
      call run#print_formatted('ErrorMsg', 'Command editing not available for split mode.')
      return
    endif

    " open file for editing
    let s:run_edit_options = options
    let s:run_edit_path = s:run_cmd_path . 'edit-' . timestamp . '.sh'
    let editor_lines = [s:edit_msg, '']
    if get(options, 'edit_last')
      call extend(editor_lines, split(s:run_last_command, "\n"))
    else
      call add(editor_lines, '')
    endif

    call run#cmd_input_open_editor(editor_lines, timestamp)
    return
  endif

  let s:run_last_command = a:cmd
  let s:run_last_options = options
  let shortcmd = run#clean_cmd_name(a:cmd)
  let fname = timestamp . '__' . shortcmd . '.log'
  let fpath = g:rundir . '/' . fname
  let temppath = s:run_cmd_path . timestamp . '.log'
  let execpath = s:run_cmd_path . 'exec-' . timestamp
  let currentcmdpath = execpath . '.sh'
  
  " run job as shell command to tempfile w/ details
  let date_cmd = 'date +"' . s:run_timestamp_format . '"'
  call writefile(split(a:cmd, "\n"), currentcmdpath)
  call writefile([
        \ 'printf "COMMAND: "',
        \ 'cat ' .  currentcmdpath . " | sed '2,${s/^/         /g}'",
        \ 'echo WORKDIR: ' . getcwd(),
        \ 'printf "STARTED: "',
        \ date_cmd,
        \ 'printf "\n"',
        \ g:run_shell . ' ' . currentcmdpath,
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
  let is_save = g:run_autosave_logs || is_nostream
  let ext_options = {}
  if is_nostream
    let ext_options['out_io'] = 'file'
    let ext_options['out_name'] = fpath
  else
    let ext_options['out_io'] = 'buffer'
    let ext_options['out_name'] = temppath
    if g:run_autosave_logs
      " append to saved file on every stdout
      let ext_options['out_cb'] = 'run#out_cb'
    endif
  endif

  " nvim overrides
  if has('nvim')
    let ext_options = {}
    let ext_options['on_exit'] = 'run#close_cb'
    let ext_options['on_stdout'] = 'run#out_cb'
    let ext_options['out_name'] = fpath
    " let ext_options['stdout_buffered'] = v:true
  endif

  call extend(job_options, ext_options)
  if has('nvim')
    let job = jobstart(join([g:run_shell, execpath], ' '), job_options)
    let pid = job
  else
    let job = job_start(join([g:run_shell, execpath], ' '), job_options)
    let pid = job_info(job)['process']
  endif
  
  " get job info for global job dict
  let job_obj = {
        \ 'pid': pid,
        \ 'command': a:cmd,
        \ 'bufname': (is_nostream ? fpath : temppath),
        \ 'filename': fpath,
        \ 'timestamp': timestamp,
        \ 'job': job,
        \ 'status': 'RUNNING',
        \ 'save': is_save,
        \ 'options': options
        \ }
  let s:run_jobs[timestamp] = job_obj
  let msg = '[' . timestamp . '] started - ' . trim(a:cmd)

  if get(options, 'watch')
    silent exec 'e ' . temppath
  elseif get(options, 'split')
    silent exec 'sp ' . temppath
  elseif get(options, 'vsplit')
    silent exec 'wincmd k | rightb vs ' . temppath
  endif
  call run#alert_and_update(msg, options)
endfunction

function! run#RunQuiet(cmd) abort
  call run#Run(a:cmd, { 'quiet': 1 })
endfunction

function! run#RunWatch(cmd) abort
  call run#Run(a:cmd, { 'watch': 1, 'quiet': 1 })
endfunction

function! run#RunSplit(cmd) abort
  call run#Run(a:cmd, { 'split': 1 })
endfunction

function! run#RunVSplit(cmd) abort
  call run#Run(a:cmd, { 'vsplit': 1 })
endfunction

function! run#RunNoStream(cmd) abort
  call run#Run(a:cmd, { 'nostream': 1 })
endfunction

function! run#RunAgain() abort
  if empty(s:run_last_command)
    call run#print_formatted('ErrorMsg', 'Please run a command first.')
    return
  endif
  call run#Run(s:run_last_command, s:run_last_options)
endfunction

function! run#RunAgainEdit() abort
  if empty(s:run_last_command)
    call run#print_formatted('ErrorMsg', 'Please run a command first.')
    return
  endif
  let new_opts = deepcopy(s:run_last_options)
  let new_opts['edit_last'] = 1
  call run#Run('', new_opts)
  unlet new_opts['edit_last']
  let s:run_last_options = new_opts
endfunction

function! run#RunSendKeys(cmd, ...) abort
  let options = get(a:, 1, {})

  " finish editing first
  if s:run_send_cmd_ongoing
    call run#print_formatted('ErrorMsg', 'Please finish editing the current command.')
    return
  endif

  let is_from_editor = get(options, 'is_from_editor')
  if is_from_editor
    if !has_key(s:run_jobs, s:run_send_timestamp)
      call run#print_formatted('ErrorMsg', 'Job already cleared.')
      return
    endif
    let job = s:run_jobs[s:run_send_timestamp]['job']
    let s:run_send_timestamp = ''
  else
    let job = run#get_current_buf_job()
  endif

  if empty(job)
    if type(job) ==# v:t_job
      call run#print_formatted('WarningMsg', 'Job already finished.')
      return
    endif
    call run#print_formatted('ErrorMsg',
        \ 'Please focus your cursor on the window of an active log buffer.'
        \ )
    return
  endif

  let job_info = run#get_job_with_object(job)
  let timestamp = job_info['timestamp']
  let editor_lines = [s:edit_msg, '', '']

  if empty(trim(a:cmd))
    if is_from_editor
      call run#print_formatted('WarningMsg', 'User cancelled command input.')
    else
      call run#cmd_input_open_editor(editor_lines, timestamp, {'is_send': 1})
    endif
    return
  endif

  " send keys if it checks out
  call ch_sendraw(job, a:cmd . "\n")
endfunction

function! run#RunKill(...) abort
  let job_key = get(a:, 1)
  if empty(job_key)
    let job = run#get_current_buf_job()
    if empty(job)
      if type(job) ==# v:t_job
        call run#print_formatted('WarningMsg', 'Job already finished.')
        return
      endif
      call run#print_formatted('ErrorMsg',
          \ 'Please provide a job key or focus your cursor on the window'
          \ . ' of an active log buffer.'
          \ )
      return
    endif
    let job_key = job['timestamp']
  endif

  if !has_key(s:run_jobs, job_key)
    call run#print_formatted('ErrorMsg', 'Job key not found.')
    return
  endif
  let job = s:run_jobs[job_key]
  if job['status'] !=# 'RUNNING'
    if !s:run_killall_ongoing
      call run#print_formatted('WarningMsg', 'Job already finished.')
    endif
    return 0
  else
    if has('nvim')
      call jobstop(job['job'])
    else
      call job_stop(job['job'], 'kill')
    endif
    return 1
  endif
endfunction

function! run#RunKillAll() abort
  " user confirm
  let running_jobs = split(run#list_running_jobs(), "\n")
  if empty(running_jobs)
    call run#print_formatted('WarningMsg', 'No jobs are running.')
    return
  endif

  let confirm = input('Kill all running jobs? (Y/n) ')
  if confirm !=? 'Y'
    return
  endif

  " in case user confirms late and jobs have stopped
  let running_jobs = split(run#list_running_jobs(), "\n")
  if empty(running_jobs)
    call run#print_formatted('WarningMsg', 'All jobs have finished running.')
    return
  endif

  let s:run_killed_jobs = 0
  let s:run_killall_ongoing = len(running_jobs)
  if has('nvim')
    let s:run_jobs_to_kill_nvim = running_jobs
  endif
  for job_key in running_jobs
    call run#RunKill(job_key)
  endfor
endfunction

function! run#RunListToggle() abort
  if run#is_qf_open()
    cclose
  else
    call run#update_run_jobs()
    silent copen
  endif
endfunction

function! run#RunClear(status_list) abort
  if len(s:run_jobs) == 0
    call run#print_formatted('WarningMsg', 'The RunList is already clear.')
    return
  endif
  " user confirm
  let confirm = input(
        \ 'Clear all jobs with status ' . join(a:status_list, '/') . '? (Y/n) '
        \ )
  if confirm !=? 'Y'
    return
  endif

  " remove all jobs that match status_list
  let clear_count = 0
  for job in values(s:run_jobs)
    let status_match = index(a:status_list, job['status']) >= 0
    if status_match
      if get(job, 'bufname')
        silent exec 'bw! ' . job['bufname']
      endif
      unlet s:run_jobs[job['timestamp']]
      let clear_count += 1
    endif
  endfor
  call run#alert_and_update(
        \ 'Cleared ' . clear_count . (clear_count !=# 1 ? ' jobs.' : ' job.'),
        \ {'quiet': 1}
        \ )
endfunction

function! run#RunSaveLog(...) abort
  let job_key = get(a:, 1)
  let is_from_current_buf = 0
  if empty(job_key)
    let job = run#get_current_buf_job()
    if type(job) !=# v:t_job
      call run#print_formatted('ErrorMsg',
          \ 'Please provide a job key or focus your cursor on the window'
          \ . ' of an active log buffer.'
          \ )
      return
    else
      let job_key = run#get_job_with_object(job)['timestamp']
    endif
    let is_from_current_buf = 1
  endif

  if !has_key(s:run_jobs, job_key)
    call run#print_formatted('ErrorMsg', 'Job key not found.')
    return
  endif
  let job = s:run_jobs[job_key]
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
    unlet s:run_jobs[job_key]
    return
  endif

  " write from the job buffer if all checks passed
  if is_from_current_buf
    silent exec 'w! ' . job['filename']
  else
    silent exec 'e ' . job['bufname'] . ' | keepalt w! ' . job['filename']
  endif
  let s:run_jobs[job_key]['save'] = 1
  call run#alert_and_update('Logs saved to ' . job['filename'], {'quiet': 1})
endfunction

function! run#RunBrowseLogs(...) abort
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
  let qf_output = []
  for entry in split(trim(system(cmd_get_files)), "\n")
    let qf_item = {}
    let split_str = ' COMMAND: '
    let split_cmd = split(entry, split_str)
    let qf_item['filename'] = split_cmd[0]
    let qf_item['text'] = 'SAVED - ' . join(split_cmd[1:], split_str)
    call add(qf_output, qf_item)
  endfor

  silent call setqflist(qf_output)
  silent call setqflist([], 'a', {'title': 'RunLogs'})
  let limit = min([limit, len(qf_output)])
  let msg = 'Showing the last ' . limit . ' saved logs.'
  call run#print_formatted('Normal', msg)
  if !run#is_qf_open()
    silent copen
  endif
endfunction

function! run#RunDeleteLogs() abort
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

  let qf_title = get(getqflist({'title': 1}), 'title')
  if run#is_qf_open() && qf_title ==# 'RunLogs'
    silent call setqflist([])
    silent call setqflist([], 'a', {'title': 'RunLogs'})
  endif
  call run#print_formatted('WarningMsg', 'Deleted all logs.')
endfunction


" utility
function! run#cmd_input_open_editor(editor_lines, timestamp, ...)
  let options = get(a:, 1, {})
  let is_send = get(options, 'is_send')
  let prefix = is_send ? 'send-' : 'edit-'

  let editorpath = s:run_cmd_path . prefix . a:timestamp . '.sh'
  if is_send
    let s:run_send_cmd_ongoing = 1
    let s:run_send_path = editorpath
    let s:run_send_timestamp = a:timestamp
  else
    let s:run_edit_cmd_ongoing = 1
    let s:run_edit_path = editorpath
  endif
  call writefile(a:editor_lines, editorpath)
  silent exec 'sp ' . editorpath . ' | normal! G'
endfunction

function! run#cmd_input_finished(...)
  let options = get(a:, 1, {})
  " goto window
  let fname = expand('<afile>')
  let win = bufwinnr(fname)
  silent exec win . 'wincmd w'

  " keep only non-comment lines w/ text, join to one line
  let cmd_text = join(filter(getline(1, '$'),
        \ 'trim(v:val) !~ "^#" && len(trim(v:val)) > 0'),
        \ "\n")

  call extend(s:run_edit_options, {'is_from_editor': 1})
  if !get(options, 'send')
    let s:run_edit_cmd_ongoing = 0
    call run#Run(cmd_text, s:run_edit_options)
    let s:run_edit_options = {}
  else
    let s:run_send_cmd_ongoing = 0
    call run#RunSendKeys(cmd_text, {'is_from_editor': 1})
  endif
  call delete(fname)
endfunction

function! run#get_current_buf_job(...)
  " check if current buffer is an active job
  let options = get(a:, 1, {})
  let curr = bufname('%')

  for job_info in values(s:run_jobs)
    if job_info['bufname'] ==# curr
      return job_info['job']
    endif
  endfor
endfunction

function! run#update_run_jobs()
  let qf_output = []
  let run_jobs_sorted = reverse(sort(values(s:run_jobs), {
        \ v1, v2 -> v1.timestamp ==# v2.timestamp ? 0 
        \ : v1.timestamp > v2.timestamp ? 1 : -1
        \ }))
  for val in run_jobs_sorted
    let qf_item = {}
    let is_nostream = get(val['options'], 'nostream')

    " set the qf buffer / file to open
    let status = val['status']
    if is_nostream || (status !=# 'RUNNING' && val['save'])
      let qf_item['filename'] = val['filename']
    else
      let qf_item['bufnr'] = bufnr(val['bufname'])
    endif
    " set the qf message (status)
    let qf_item['text'] = status . ' - ' . val['command']

    " update output and global jobs dict
    call add(qf_output, qf_item)
    call extend(s:run_jobs[val['timestamp']], { 'status': status })
  endfor

  silent call setqflist(qf_output)
  silent call setqflist([], 'a', {'title': 'RunList'})
endfunction

function! run#alert_and_update(content, ...)
  let options = get(a:, 1, 0)
  if type(options) !=# 4
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
  let pid = has('nvim') ? a:job : job_info(a:job)['process']
  for job in values(s:run_jobs)
    if job['pid'] ==# pid
      return job
    endif
  endfor
endfunction

function! run#list_running_jobs(...)
  return join(keys(
        \ filter(deepcopy(s:run_jobs),
        \ 'v:val.status ==# "RUNNING"')
        \  ), "\n")
endfunction

function! run#list_unsaved_jobs(...)
  return join(keys(
        \ filter(deepcopy(s:run_jobs),
        \ 'v:val.save ==# 0 && v:val.status !=# "RUNNING"')
        \  ), "\n")
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
function! run#out_cb(channel, msg, ...)
  " write logs to output file while running
  let job_obj = has('nvim') ? a:channel : ch_getjob(a:channel)
  let job = run#get_job_with_object(job_obj)
  let fname = job['filename']
  let output = has('nvim') ? a:msg : [a:msg]
  call writefile(output, fname, "a")
endfunction

function! run#close_cb(channel, ...)
  if has('nvim')
    let job = a:channel
    let info = run#get_job_with_object(job)
    " nvim exitval is unreliable
    let kill_idx = index(s:run_jobs_to_kill_nvim, info['timestamp'])
    let exitval = get(a:, 1, 0)
    if kill_idx > -1
      let exitval = -1
      call remove(s:run_jobs_to_kill_nvim, kill_idx)
    endif
  else
    let job = ch_getjob(a:channel)
    let info = run#get_job_with_object(job)
    let exitval = job_info(info['job'])['exitval']
  endif

  " calculate status here
  let status = (exitval == -1) ? 'KILLED' : (exitval == 0) ? 'DONE' : 'FAILED'
  let s:run_jobs[info['timestamp']]['exitval'] = exitval
  let s:run_jobs[info['timestamp']]['status'] = status

  " if saved and window unfocused, wipe temp buffer
  let bufexists = bufnr(info['bufname']) !=# -1
  let bufisopen = bufwinnr(info['bufname']) ==# -1
  if info['save'] && bufexists && bufisopen
    silent exec 'bw! ' . bufnr(info['bufname'])
  endif

  let kill_options = {'quiet': 1, 'msg_format': 'WarningMsg'}
  if s:run_killall_ongoing
    if exitval !=# -1
      " no action if killall ongoing
      return
    endif
    let s:run_killed_jobs += 1

    " killall finished
    if len(run#list_running_jobs()) == 0
      let s:run_killall_ongoing = 0
      let s:run_jobs_to_kill_nvim = []
      let msg = s:run_killed_jobs . 
            \ (s:run_killed_jobs !=# 1 ? ' jobs killed.' : ' job killed.')
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
