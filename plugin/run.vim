if exists('g:loaded_run') || &compatible
  " finish
endif
let g:loaded_run = 1

" vars
if !exists('g:run_jobs')
  let g:run_jobs = {}
endif
if !exists('g:run_quiet')
  let g:run_quiet = 0
endif
if !exists('g:rundir')
  let g:rundir = $HOME . '/.vim/rundir'
endif
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" commands
command -nargs=* Run :call Run(<q-args>)
command RunList :call RunList()


" main functions
function! RunList()
  call _UpdateRunJobs
  copen
endfunction

function! Run(cmd)
  let tempfname = trim(system('mktemp'))
  let job = job_start(a:cmd, {
        \ 'cwd': getcwd(),
        \ 'out_io': 'buffer', 'out_name': tempfname,
        \ 'out_msg': 0, 'out_modifiable': 0,
        \ 'out_cb': '_RunOutCB',
        \ 'close_cb': '_RunCloseCB',
        \ 'pty': 1 
        \ })
  let info = job_info(job)
  let pid = info['process']
  let timestamp = strftime('%Y%m%d_%H%M%S')
  let shortcmd = _CleanCmdName(info['cmd'][0])
  let fname = g:rundir . '/' . timestamp . '__' . shortcmd . '.log'
  let job_obj = {
        \ 'pid': pid,
        \ 'command': a:cmd,
        \ 'bufname': tempfname,
        \ 'filename': fname,
        \ 'timestamp': timestamp,
        \ 'info': info,
        \ 'job': job,
        \ }
  let g:run_jobs[pid] = job_obj
  execute 'badd ' . tempfname
  let msg = "Job " . pid . " - " . a:cmd . " - output streaming to buffer "
        \ . bufnr(tempfname)
  call _RunAlertNoFocus(msg)
endfunction


" utility
function! _IsQFOpen()
  return len(filter(range(1, winnr('$')), 'getwinvar(v:val, "&ft") == "qf"')) > 0
endfunction

function! _CleanCmdName(cmd)
  " replace dir-breaking chars
  return substitute(a:cmd, '[\/]', '', 'g')
endfunction

function! _UpdateRunJobs()
  let g:qf_output = []
  for [pid, val] in g:run_jobs->items()
    let qf_item = {
      \ 'lnum': 1
      \ }
    if job_status(val['job']) == 'run'
      let qf_item['bufnr'] = bufnr(val['bufname'])
      let qf_item['text'] = 'RUNNING'
    else
      let qf_item['filename'] = val['filename']
      let qf_item['text'] = 'DONE'
    endif
    call add(g:qf_output, qf_item)
  endfor
  call setqflist(g:qf_output)
endfunction

function! _RunAlertNoFocus(content, ...)
  call _UpdateRunJobs()
  if !g:run_quiet || _IsQFOpen()
    copen
  endif
  redraw | echom a:content
endfunction

function! _RunGetJobDetails(job)
  let info = job_info(a:job)
  return g:run_jobs[info['process']]
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
  let pid = job_info(job)['process']
  let fname = _RunGetJobDetails(job)['filename']
  call _RunAlertNoFocus('Job ' . pid . ' completed, run :RunList to view.')
endfunction
