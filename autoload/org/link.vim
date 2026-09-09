" autoload/org/link.vim — Open links under cursor

function! org#link#open() abort
  let pos = getcurpos()
  let line = getline('.')
  let col = pos[2]

  let link = s:link_at_pos(line, col)
  if empty(link)
    echohl WarningMsg | echo 'No link at cursor' | echohl None
    return
  endif

  call s:open(link)
endfunction

function! s:link_at_pos(line, col) abort
  let idx = 0
  while 1
    let start = stridx(a:line, '[[', idx)
    if start < 0 | break | endif

    let end = stridx(a:line, ']]', start)
    if end < 0 | break | endif

    if a:col >= start + 1 && a:col <= end + 2
      let inner = a:line[start+2 : end-1]
      let sep = stridx(inner, '][')
      if sep >= 0
        return {'url': inner[0 : sep-1], 'desc': inner[sep+2 :]}
      endif
      return {'url': inner, 'desc': ''}
    endif

    let idx = end + 2
  endwhile
  return {}
endfunction

function! s:open(link) abort
  let url = a:link.url

  if url =~# '^https\?://'
    call s:open_browser(url)
  elseif url =~# '^file:'
    call s:open_file(url)
  elseif url =~# '^id:'
    call s:open_id(url)
  else
    echohl WarningMsg | echo 'Unknown link scheme: ' . url | echohl None
  endif
endfunction

function! s:open_browser(url) abort
  let url = shellescape(a:url)
  if has('win32') || has('win64')
    call system('start "" ' . url)
  elseif has('mac') || has('macunix')
    call system('open ' . url)
  else
    call system('xdg-open ' . url . ' 2>/dev/null &')
  endif
endfunction

function! s:open_file(url) abort
  let parts = matchlist(a:url, '^file:\(.\{-}\)\%(::\(\d\+\)\)\=$')
  if empty(parts) || parts[1] ==# ''
    echohl WarningMsg | echo 'Invalid file link: ' . a:url | echohl None
    return
  endif

  let path = parts[1]
  let line = parts[2]

  let path = tr(path, '/', '\')
  try
    execute 'edit' fnameescape(path)
  catch
    echohl WarningMsg | echo 'Cannot open file: ' . path | echohl None
    return
  endtry

  if line !=# ''
    call cursor(str2nr(line), 1)
    normal! zz
  endif
endfunction

function! s:open_id(url) abort
  let uuid = substitute(a:url, '^id:', '', '')
  let found = s:find_id_in_files(uuid, org#core#agenda_files())
  if empty(found)
    echohl WarningMsg | echo 'No headline found with ID: ' . uuid | echohl None
    return
  endif

  execute 'edit' fnameescape(found.file)
  call cursor(found.lnum, 1)
  normal! zz
endfunction

function! s:find_id_in_files(uuid, files) abort
  for f in a:files
    if !filereadable(f) | continue | endif
    let lines = readfile(f)
    let in_props = 0
    let prop_start = 0
    for lnum in range(len(lines))
      let line = lines[lnum]
      if line =~# '^\s*:PROPERTIES:'
        let in_props = 1
        let prop_start = lnum
      elseif line =~# '^\s*:END:'
        let in_props = 0
      elseif in_props && line =~# '^\s*:ID:\s\+' . a:uuid . '\s*$'
        let hl_lnum = s:find_headline_before(lines, prop_start)
        if hl_lnum > 0
          return {'file': f, 'lnum': hl_lnum}
        endif
      endif
    endfor
  endfor
  return {}
endfunction

function! s:find_headline_before(lines, lnum) abort
  let lnum = a:lnum - 1
  while lnum >= 0
    if a:lines[lnum] =~# '^\*\+ '
      return lnum + 1
    endif
    let lnum -= 1
  endwhile
  return 0
endfunction

