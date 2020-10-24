if exists('g:loaded_run') || &compatible
  " finish
endif
let g:loaded_run = 1

" vars
if !exists('g:run_jobs')
  let g:run_jobs = []
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


" main functions
function! RunList()
  call _UpdateRunJobs()
  copen
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
  
  " get job info for global job list
  let info = job_info(job)
  let pid = info['process']
  let job_obj = {
        \ 'pid': pid,
        \ 'command': a:cmd,
        \ 'bufname': temppath,
        \ 'filename': fpath,
        \ 'timestamp': timestamp,
        \ 'job': job,
        \ 'options': options
        \ }
  call add(g:run_jobs, job_obj)
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
  let run_jobs_sorted = reverse(sort(copy(g:run_jobs), {
        \ v1, v2 -> v1.timestamp == v2.timestamp ? 0 
        \ : v1.timestamp > v2.timestamp ? 1 : -1
        \ }))
  for val in run_jobs_sorted
    let qf_item = {
      \ 'lnum': 1
      \ }
    if job_status(val['job']) == 'run'
      let qf_item['bufnr'] = bufnr(val['bufname'])
      let qf_item['text'] = 'RUNNING'
    else
      let qf_item['filename'] = val['filename']
      let exitval = job_info(val['job'])['exitval']
      let qf_item['text'] = exitval == 0 ? 'DONE' : 'FAIL'
    endif
    let qf_item['text'] = qf_item['text'] . ' - ' . val['command']
    call add(g:qf_output, qf_item)
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
  for job in g:run_jobs
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
  call _RunAlertNoFocus(msg, info['options'])
endfunction
