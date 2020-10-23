if exists("g:loaded_run") || &compatible
  " finish
endif
let g:loaded_run = 1
command -nargs=* Run :call Run()

function! Run()
  let fname = trim(system('mktemp'))
  let cmd = 'python3 test.py'
  let job = job_start(cmd,
        \ { 'out_io': 'buffer', 'out_name': fname,
        \ 'cwd': getcwd(),
        \ 'pty': 1 }
        \ )
  execute 'edit' . fname
endfunction
