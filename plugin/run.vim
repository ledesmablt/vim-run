if exists('g:loaded_run') || &compatible
  " finish
endif
let g:loaded_run = 1

" vars
if !exists('g:run_jobs')
  let g:run_jobs = {}
endif
if !exists('g:run_quiet_default')
  let g:run_quiet_default = 0
endif
if !exists('g:rundir')
  let g:rundir = $HOME . '/.vim/rundir'
endif
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" commands
command -nargs=* -complete=file Run :call Run(<q-args>)
command -nargs=* -complete=file RunQuiet :call RunQuiet(<q-args>)
command RunList :call RunList()
command -nargs=0 RunClear :call RunClear(['DONE', 'FAIL'])
command -nargs=0 RunClearDone :call RunClear(['DONE'])
command -nargs=0 RunClearFail :call RunClear(['FAIL'])


" main functions
function! RunList()
  call _UpdateRunJobs()
  copen
endfunction

function! RunClear(status_list)
  " user confirm
  let confirm = input(
        \ 'Clear all jobs with status ' . a:status_list->join('/') . '? (Y/n) '
        \ )
  if toupper(confirm) != 'Y'
    return
  endif

  " remove all jobs that match status_list
  let clear_count = 0
  for job in g:run_jobs->values()
    let status_match = a:status_list->index(job['status']) >= 0
    if status_match
      unlet g:run_jobs[job['timestamp']]
      let clear_count = clear_count + 1
    endif
  endfor
  call _RunAlertNoFocus('Cleared ' . clear_count . ' jobs.', {'quiet': 1})
endfunction

function! RunQuiet(cmd)
  call Run(a:cmd, { 'quiet': 1 })
endfunction

function! Run(cmd, ...)
  " check if command provided
  if len(trim(a:cmd)) == 0
    echoerr 'Please provide a command.'
    return
  endif

  " get options dict
  let options = get(a:, 1, 0)
  if type(options) != 4
    let options = {}
  endif

  let runcmdpath = trim(system('mktemp'))
  let timestamp = strftime('%Y%m%d_%H%M%S')
  let shortcmd = _CleanCmdName(a:cmd)
  let fname = timestamp . '__' . shortcmd . '.log'
  let fpath = g:rundir . '/' . fname
  let temppath = '/tmp/vim-run.' . timestamp . '.log'
  
  " run job as shell command to tempfile
  execute 'redir! > ' . runcmdpath
  silent echo a:cmd
  redir END
  let job = job_start($SHELL . ' ' . runcmdpath, {
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
  let g:run_jobs[timestamp] = job_obj
  let msg = "[" . timestamp . "] " . a:cmd . " - output streaming to buffer "
        \ . bufnr(temppath)

  call _RunAlertNoFocus(msg, options)
endfunction


" utility
function! _IsQFOpen()
  return len(filter(range(1, winnr('$')), 'getwinvar(v:val, "&ft") == "qf"')) > 0
endfunction

function! _CleanCmdName(cmd)
  " replace dir-breaking chars
  return substitute(split(a:cmd, ' ')[0], '[\/]', '', 'g')
endfunction

function! _UpdateRunJobs()
  let g:qf_output = []
  let run_jobs_sorted = reverse(sort(g:run_jobs->values(), {
        \ v1, v2 -> v1.timestamp == v2.timestamp ? 0 
        \ : v1.timestamp > v2.timestamp ? 1 : -1
        \ }))
  for val in run_jobs_sorted
    let qf_item = {
      \ 'lnum': 1
      \ }
    if job_status(val['job']) == 'run'
      let qf_item['bufnr'] = bufnr(val['bufname'])
      let status = 'RUNNING'
    else
      let qf_item['filename'] = val['filename']
      let exitval = job_info(val['job'])['exitval']
      let status = exitval == 0 ? 'DONE' : 'FAIL'
    endif
    let qf_item['text'] = status . ' - ' . val['command']

    " update output and global jobs dict
    call add(g:qf_output, qf_item)
    call extend(g:run_jobs[val['timestamp']], { 'status': status })
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

function! _RunGetJobDetails(job)
  let pid = job_info(a:job)['process']
  for job in g:run_jobs->values()
    if job['pid'] == pid
      return job
    endif
  endfor
  echoerr 'Job ' . pid . ' not found.'
endfunction


" callbacks
function! _RunOutCB(channel, msg)
  let job = ch_getjob(a:channel)
  let fname = _RunGetJobDetails(job)['filename']
  execute 'redir >> ' . fname
  silent echo a:msg
  redir END
endfunction

function! _RunCloseCB(channel)
  let job = ch_getjob(a:channel)
  let info = _RunGetJobDetails(job)
  let msg = '[' . info['timestamp'] . '] completed, run :RunList to view.'
  let todel = bufnr(info.bufname)
  if todel != bufnr('%')
    exec 'bd ' . todel
  endif
  call _RunAlertNoFocus(msg, info['options'])
endfunction
