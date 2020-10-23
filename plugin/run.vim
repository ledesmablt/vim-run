if exists('g:loaded_run') || &compatible
  " finish
endif
let g:loaded_run = 1

" vars
let g:run_jobs = {}
let g:rundir = $HOME . '/.vim/rundir'
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" commands
command -nargs=* Run :call Run(<q-args>)


" main functions
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
        \ 'info': info
        \ }
  let g:run_jobs[pid] = job_obj
  execute 'badd ' . tempfname
  let msg = "Job " . pid . " - " . a:cmd . " - output streaming to buffer "
        \ . bufnr(tempfname)
  call _RunAlertNoFocus(msg)
endfunction


" utility
function! _CleanCmdName(cmd)
  " replace dir-breaking chars
  return substitute(a:cmd, '[\/]', '', 'g')
endfunction

function! _RunAlertNoFocus(content, options)
  if has_key(options, 'clear')
    call setqflist([])
  endif

  " append new content to quickfix menu
  let run_userbuf = bufname('%')
  silent caddexpr a:content
  copen
  exec bufwinnr(run_userbuf) . 'wincmd w'
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
  call _RunAlertNoFocus('Job ' . pid . ' completed, saved to ' . fname)
endfunction
