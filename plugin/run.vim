if exists('g:loaded_run') || &compatible
  " finish
endif
let g:loaded_run = 1

" vars
let g:run_jobs = {}
let g:run_userbuf = bufname('%')
if !exists('g:run_msgs_tempfname')
  let g:run_msgs_tempfname = trim(system('mktemp'))
endif

let g:rundir = $HOME . '/.vim/rundir'
if !isdirectory(g:rundir)
  call mkdir(g:rundir, 'p')
endif

" commands
command -nargs=* Run :call Run()


" main functions
function! Run()
  let tempfname = trim(system('mktemp'))
  let cmd = 'python3 test.py'
  let job = job_start(cmd, {
        \ 'cwd': getcwd(),
        \ 'out_io': 'buffer', 'out_name': tempfname,
        \ 'out_msg': 0, 'out_modifiable': 0,
        \ 'out_cb': '_RunOutCB',
        \ 'close_cb': '_RunCloseCB',
        \ 'stoponexit': '',
        \ 'pty': 1 
        \ })
  let info = job_info(job)
  let pid = info['process']
  let timestamp = strftime('%Y%m%d_%H%M%S')
  let fname = g:rundir . '/' . timestamp . '__' . info['cmd'][0] . '.log'
  let job_obj = {
        \ 'pid': pid,
        \ 'command': cmd,
        \ 'bufname': tempfname,
        \ 'filename': fname,
        \ 'timestamp': timestamp,
        \ 'info': info
        \ }
  let g:run_jobs[pid] = job_obj
  execute 'badd ' . tempfname
  let msg = "Job " . pid . " - " . cmd . "Output streaming to buffer "
        \ . bufnr(tempfname) . " - " . tempfname
  call _RunAlertNoFocus(msg)
endfunction


" utility
function! _RunAlertNoFocus(content, ...)
  let clear_output = get(a:, 1, 0)
  let redirfn = '>>'
  if clear_output
    let redirfn = '>'
  endif
  let run_userbuf = bufname('%')

  " append content to msgs file
  execute 'redir! ' . redirfn . ' ' . g:run_msgs_tempfname
  silent echo a:content
  redir END

  " open msgs file and return focus
  execute 'cf ' . g:run_msgs_tempfname
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
