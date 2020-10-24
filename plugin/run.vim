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
command -nargs=* -complete=file Run :call Run(<q-args>)
command RunList :call RunList()


" main functions
function! RunList()
  call _UpdateRunJobs()
  copen
endfunction

function! Run(cmd)
  if len(trim(a:cmd)) == 0
    echoerr 'Please provide a command.'
    return
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
  let info = job_info(job)
  let pid = info['process']
  let job_obj = {
        \ 'pid': pid,
        \ 'command': a:cmd,
        \ 'bufname': temppath,
        \ 'filename': fpath,
        \ 'timestamp': timestamp,
        \ 'job': job,
        \ }
  let g:run_jobs[pid] = job_obj
  execute 'badd ' . temppath
  let msg = "[" . timestamp . "] " . a:cmd . " - output streaming to buffer "
        \ . bufnr(temppath)
  call _RunAlertNoFocus(msg)
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
  let keys = reverse(sort(g:run_jobs->keys()))
  for key in keys
    let val = g:run_jobs[key]
    let qf_item = {
      \ 'lnum': 1
      \ }
    if job_status(val['job']) == 'run'
      let qf_item['bufnr'] = bufnr(val['bufname'])
      let qf_item['text'] = 'RUNNING'
    else
      let qf_item['filename'] = val['filename']
      let exitval = job_info(val['job'])['exitval']
      if exitval == 0
        let qf_item['text'] = 'DONE'
      else
        let qf_item['text'] = 'FAIL'
      endif
    endif
    let qf_item['text'] = qf_item['text'] . ' - ' . val['command']
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
  let info = _RunGetJobDetails(job)
  call _RunAlertNoFocus('[' . info['timestamp'] . '] completed, run :RunList to view.')
endfunction
