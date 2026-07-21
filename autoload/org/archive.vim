" autoload/org/archive.vim — Archive subtree to .org_archive

function! org#archive#subtree() abort
  let hl = org#core#current_headline()
  if empty(hl)
    echohl WarningMsg | echo 'Not on a headline' | echohl None
    return
  endif

  let archive_file = s:archive_path()
  let subtree_end  = s:find_subtree_end(hl.lnum)
  if subtree_end < 0
    return
  endif

  let lines = getline(hl.lnum, subtree_end)
  let headers = s:build_archive_headers()

  let existing = filereadable(archive_file) ? readfile(archive_file) : []

  if empty(existing)
    let result = headers + [''] + lines
  else
    let date_idx = s:find_or_create_month_entry(existing, headers)
    let result = existing[:date_idx] + [''] + lines + existing[date_idx+1 :]
  endif

  call writefile(result, archive_file)
  execute 'delete' (subtree_end - hl.lnum + 1)
  echohl WarningMsg | echo 'Archived to: ' . archive_file | echohl None
endfunction

function! s:archive_path() abort
  let loc = get(g:, 'org_archive_location', '')
  if loc !=# ''
    return substitute(loc, '%s', expand('%:p:r'), '')
  endif
  return expand('%:p:r') . '.org_archive'
endfunction

function! s:find_subtree_end(headline_lnum) abort
  let level = len(matchstr(getline(a:headline_lnum), '^\*\+'))
  let lnum  = a:headline_lnum + 1
  while lnum <= line('$')
    let m = matchstr(getline(lnum), '^\*\+')
    if len(m) > 0 && len(m) <= level
      return lnum - 1
    endif
    let lnum += 1
  endwhile
  return line('$')
endfunction

function! s:build_archive_headers() abort
  let now = localtime()
  let ym = strftime('%Y-%m', now)
  let day = strftime('%Y-%m-%d %a', now)
  return ['* Archived tasks :ARCHIVE:', '** ' . ym]
endfunction

function! s:find_or_create_month_entry(lines, headers) abort
  let top = a:headers[0]
  let month_h = a:headers[1]

  let top_idx = -1
  for i in range(len(a:lines))
    if a:lines[i] ==# top
      let top_idx = i
      break
    endif
  endfor

  if top_idx < 0
    call extend(a:lines, ['', top, '', month_h])
    return len(a:lines) - 1
  endif

  for i in range(top_idx + 1, len(a:lines) - 1)
    if a:lines[i] ==# month_h
      return i
    endif
    if a:lines[i] =~# '^\*\{2,} ' && a:lines[i] ># month_h
      call insert(a:lines, month_h, i)
      return i
    endif
    if a:lines[i] =~# '^\* '
      call insert(a:lines, month_h, i)
      return i
    endif
  endfor

  call add(a:lines, '')
  call add(a:lines, month_h)
  return len(a:lines) - 1
endfunction
