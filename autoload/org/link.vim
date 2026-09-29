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

  if url =~# '^id:'
    call s:open_id(url)
  elseif url =~# '^file:'
    call s:open_file(url[5:])
  elseif url =~# '^\%(/\|\./\|\.\./\|\~/\)'
    " A bare path is a file link, as in Emacs: [[~/org/x.org]]
    call s:open_file(url)
  elseif url =~# '^[*#]'
    " Internal link: [[*Heading]] or [[#custom-id]] in this file
    if !s:search_here(url)
      echohl WarningMsg | echo 'No match for: ' . url | echohl None
    endif
  elseif url =~# '^\a[[:alnum:]+.-]*:'
    call s:open_external(url)
  else
    echohl WarningMsg | echo 'Unknown link: ' . url | echohl None
  endif
endfunction

" Hand {url} (https:, mailto:, …) to the system's opener.
function! s:open_external(url) abort
  let url = shellescape(a:url)
  if has('win32') || has('win64')
    call system('start "" ' . url)
  elseif has('mac') || has('macunix')
    call system('open ' . url)
  else
    call system('xdg-open ' . url . ' >/dev/null 2>&1 &')
  endif
endfunction

" Open 'PATH' or 'PATH::SEARCH'. PATH may use ~ or $VARS and is relative to
" the current file's directory; SEARCH is a line number, *Heading, #custom-id
" or text, as in Emacs file links.
function! s:open_file(target) abort
  let parts  = split(a:target, '::', 1)
  let path   = expand(parts[0])
  let search = join(parts[1:], '::')
  if path ==# ''
    echohl WarningMsg | echo 'Invalid file link: ' . a:target | echohl None
    return
  endif
  if path !~# '^\%(/\|\a:[\\/]\)'
    let path = expand('%:p:h') . '/' . path
  endif

  try
    execute 'hide edit' fnameescape(simplify(path))
  catch
    echohl WarningMsg | echo 'Cannot open file: ' . path | echohl None
    return
  endtry

  if search !=# '' && !s:search_here(search)
    echohl WarningMsg | echo 'No match for: ' . search | echohl None
  endif
endfunction

" Move the cursor to {search} in the current buffer: a line number, *Heading
" (compared without keyword, priority or tags), #custom-id (the CUSTOM_ID
" property) or plain text. Returns 1 when found.
function! s:search_here(search) abort
  let lnum = 0
  if a:search =~# '^\d\+$'
    let lnum = min([str2nr(a:search), line('$')])
  elseif a:search[0] ==# '*'
    let title = trim(a:search[1:])
    for l in range(1, line('$'))
      let m = matchstr(getline(l), '^\*\+\s\+\zs.*')
      if m !=# '' && org#core#headline_title(m) ==# title
        let lnum = l
        break
      endif
    endfor
  elseif a:search[0] ==# '#'
    let l = search('^\s*:CUSTOM_ID:\s\+\V' . escape(a:search[1:], '\') . '\m\s*$', 'nw')
    let lnum = l > 0 ? s:headline_above(l) : 0
  else
    let lnum = search('\V' . escape(a:search, '\'), 'nw')
  endif

  if lnum <= 0
    return 0
  endif
  call cursor(lnum, 1)
  normal! zvzz
  return 1
endfunction

function! s:headline_above(lnum) abort
  let l = a:lnum
  while l > 0 && getline(l) !~# '^\*\+\s'
    let l -= 1
  endwhile
  return l
endfunction

function! s:open_id(url) abort
  let uuid = substitute(a:url, '^id:', '', '')
  " The current buffer first: it may hold the ID unsaved, or not be an
  " agenda file at all
  let l = search('^\s*:ID:\s\+\V' . escape(uuid, '\') . '\m\s*$', 'nw')
  if l > 0 && s:headline_above(l) > 0
    call cursor(s:headline_above(l), 1)
    normal! zvzz
    return
  endif

  let found = s:find_id_in_files(uuid, org#core#agenda_files())
  if empty(found)
    echohl WarningMsg | echo 'No headline found with ID: ' . uuid | echohl None
    return
  endif

  execute 'hide edit' fnameescape(found.file)
  call cursor(found.lnum, 1)
  normal! zvzz
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
      elseif in_props && line =~# '^\s*:ID:\s\+\V' . escape(a:uuid, '\') . '\m\s*$'
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

