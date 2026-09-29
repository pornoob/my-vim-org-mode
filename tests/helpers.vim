" Shared helpers for the .vader files. Expectations that contain today's date
" build it with these, so the suite passes on any day and in any locale.

" Inactive timestamp for now, exactly as the plugin writes it.
function! Now() abort
  return org#core#format_ts(localtime(), 0)
endfunction

" 'YYYY-MM-DD dow' for today + {offset} days (dow in the current locale).
function! Ymd(offset) abort
  let [y, m, d] = org#core#jdn_to_ymd(org#core#jdn(
        \ strftime('%Y') + 0, strftime('%m') + 0, strftime('%d') + 0) + a:offset)
  return printf('%04d-%02d-%02d %s', y, m, d, org#core#dow(y, m, d))
endfunction

" 'YYYY-MM-DD dow' for a fixed date.
function! Date(y, m, d) abort
  return printf('%04d-%02d-%02d %s', a:y, a:m, a:d, org#core#dow(a:y, a:m, a:d))
endfunction

" Funcref to script-local function {name} of autoload/org/{file}.vim, for
" testing internals that are only reachable through interactive UI (the
" calendar popup). Loads the script first.
function! SFunc(file, name) abort
  execute 'runtime autoload/org/' . a:file . '.vim'
  let sid = getscriptinfo({'name': 'autoload/org/' . a:file . '.vim'})[0].sid
  return function('<SNR>' . sid . '_' . a:name)
endfunction
