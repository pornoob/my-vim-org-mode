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
      " start / end: byte index of the opening '[[' and just past the ']]'
      let inner = a:line[start+2 : end-1]
      let sep = stridx(inner, '][')
      if sep >= 0
        return {'url': inner[0 : sep-1], 'desc': inner[sep+2 :], 'start': start, 'end': end + 2}
      endif
      return {'url': inner, 'desc': '', 'start': start, 'end': end + 2}
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


" ── Inserting, editing and storing links ──────────────────────────────────────

" [[url][desc]], or [[url]] without a description.
function! s:format(url, desc) abort
  return '[[' . a:url . ']' . (a:desc ==# '' ? '' : '[' . a:desc . ']') . ']'
endfunction

" Insert a link at the cursor, or edit the one under it (Emacs' C-c C-l).
" Prompts for the target, offering stored links, then the description. With
" {visual} set, the last visual selection is replaced and becomes the default
" description.
function! org#link#insert(visual) abort
  let line = getline('.')
  let cur  = a:visual ? {} : s:link_at_pos(line, col('.'))
  if a:visual
    let [l1, c1] = [line("'<"), col("'<")]
    let [l2, c2] = [line("'>"), col("'>")]
    if l1 != l2
      echohl WarningMsg | echo 'org: select text on one line to link it' | echohl None
      return
    endif
    let c2 = min([c2, len(line)])
    let c2 += len(matchstr(line[c2 - 1 :], '^.')) - 1     " include a multibyte last char
    let cur = {'url': '', 'desc': line[c1 - 1 : c2 - 1], 'start': c1 - 1, 'end': c2}
  endif

  let url = trim(input('Link (<Tab>: id: * file: https:// …): ', get(cur, 'url', ''),
        \ 'customlist,org#link#complete'))
  if url ==# ''
    echo ''
    return
  endif
  " A headline title picked after id: becomes that headline's ID
  let title = ''
  if url =~# '^id:'
    let hl = s:id_target(url[3:])
    if !empty(hl)
      let url   = 'id:' . s:ensure_id(hl)
      let title = hl.title
    endif
  elseif url =~# '^\%(file:.*::\)\=\*'
    let title = matchstr(url, '\*\zs.*')
  endif
  let line   = getline('.')     " an ID added above the cursor moved this line
  let stored = filter(copy(get(g:, 'org_stored_links', [])), 'v:val.link ==# url')
  let default = get(cur, 'desc', '') !=# '' ? cur.desc
        \ : !empty(stored) ? stored[0].desc : title
  let desc = trim(input('Description: ', default))
  echo ''

  let text = s:format(url, desc)
  if has_key(cur, 'start')
    call setline('.', strpart(line, 0, cur.start) . text . strpart(line, cur.end))
    call cursor(line('.'), cur.start + 1)
  else
    let at = col('.') - 1 + (line ==# '' ? 0 : len(matchstr(line[col('.') - 1 :], '^.')))
    call setline('.', strpart(line, 0, at) . text . strpart(line, at))
    call cursor(line('.'), at + 1)
  endif
endfunction

" Completion for the Link: prompt. After id: the headlines of this buffer and
" the agenda files, by title; after * this buffer's headlines; after file:
" paths, and after file:PATH::* that file's headlines. Otherwise the stored
" links, then the link types. Titles match anywhere, ignoring case.
function! org#link#complete(lead, line, pos) abort
  let typed = a:line
  if typed =~# '^id:'
    return s:matching(map(s:labelled(s:headlines()), '"id:" . v:val.label'), 3, typed)
  elseif typed =~# '^\*'
    return s:matching(map(s:scan(getline(1, '$'), expand('%:p')), '"*" . v:val.title'), 1, typed)
  elseif typed =~# '^file:.*::\*'
    let [path, search] = matchlist(typed, '^file:\(.\{-}\)::\(.*\)')[1:2]
    let file  = s:resolve_path(path)
    let lines = filereadable(file) ? readfile(file) : []
    let pre   = 'file:' . path . '::*'
    return s:matching(map(s:scan(lines, file), 'pre . v:val.title'), len(pre), typed)
  elseif typed =~# '^file:'
    return map(getcompletion(typed[5:], 'file'), '"file:" . v:val')
  endif
  let links = map(copy(get(g:, 'org_stored_links', [])), 'v:val.link')
  let types = ['id:', '*', 'file:', 'https://', 'http://', 'mailto:']
  return filter(links, 'stridx(v:val, typed) >= 0')
        \ + filter(types, 'stridx(v:val, typed) == 0')
endfunction

" The {candidates} whose text after the first {skip} bytes holds what was
" typed after them, ignoring case.
function! s:matching(candidates, skip, typed) abort
  let want = tolower(a:typed[a:skip :])
  return filter(a:candidates, 'stridx(tolower(v:val[a:skip :]), want) >= 0')
endfunction

" A link's PATH as a full file name: ~ and $VARS expanded, relative to the
" current file's directory.
function! s:resolve_path(path) abort
  let path = expand(a:path)
  if path !~# '^\%(/\|\a:[\\/]\)'
    let path = expand('%:p:h') . '/' . path
  endif
  return simplify(path)
endfunction

" The headlines of {lines} (the text of {file}):
" [{'file', 'lnum', 'title', 'id'}], id '' when the headline has none.
function! s:scan(lines, file) abort
  let out      = []
  let in_props = 0
  for i in range(len(a:lines))
    let l = a:lines[i]
    let m = matchstr(l, '^\*\+\s\+\zs.*')
    if m !=# ''
      call add(out, {'file': a:file, 'lnum': i + 1,
            \ 'title': org#core#headline_title(m), 'id': ''})
      let in_props = 0
    elseif l =~? '^\s*:PROPERTIES:\s*$'
      let in_props = !empty(out)
    elseif l =~? '^\s*:END:\s*$'
      let in_props = 0
    elseif in_props && out[-1].id ==# '' && l =~# '^\s*:ID:\s\+\S'
      let out[-1].id = matchstr(l, '^\s*:ID:\s\+\zs\S\+')
    endif
  endfor
  return out
endfunction

" The headlines of this buffer (unsaved text included) and of every agenda file.
function! s:headlines() abort
  let cur = expand('%:p')
  let out = s:scan(getline(1, '$'), cur)
  for f in org#core#agenda_files()
    let f = fnamemodify(f, ':p')
    if f !=# cur && filereadable(f)
      call extend(out, s:scan(readfile(f), f))
    endif
  endfor
  return out
endfunction

" Give each headline its 'label': the title, plus FILE:LINE when another
" headline has the same title.
function! s:labelled(headlines) abort
  let seen = {}
  for h in a:headlines
    let seen[h.title] = get(seen, h.title, 0) + 1
  endfor
  for h in a:headlines
    let h.label = seen[h.title] > 1
          \ ? printf('%s (%s:%d)', h.title, fnamemodify(h.file, ':t'), h.lnum)
          \ : h.title
  endfor
  return a:headlines
endfunction

" The headline an id: link points at: by its ID, or by the label completion
" offered. {} when it is neither.
function! s:id_target(text) abort
  let hls = s:labelled(s:headlines())
  for h in hls
    if h.id !=# '' && h.id ==# a:text
      return h
    endif
  endfor
  for h in hls
    if h.label ==# a:text
      return h
    endif
  endfor
  return {}
endfunction

" The ID of headline {hl}, created (and its file saved) when it has none.
function! s:ensure_id(hl) abort
  if a:hl.id !=# ''
    return a:hl.id
  endif
  if a:hl.file ==# expand('%:p')
    return org#id#ensure(a:hl.lnum)
  endif
  let [buf, view] = [bufnr('%'), winsaveview()]
  execute 'keepalt hide edit ' . fnameescape(a:hl.file)
  let id = org#id#ensure(a:hl.lnum)
  silent update
  execute 'keepalt hide buffer ' . buf
  call winrestview(view)
  return id
endfunction

" Store a link to the headline at the cursor for org#link#insert (Emacs'
" C-c l): id:UUID when it has an :ID:, else file:PATH::*Title.
function! org#link#store() abort
  let hl   = org#core#current_headline()
  let file = fnamemodify(expand('%:p'), ':~')
  if empty(hl)
    let entry = {'link': 'file:' . file, 'desc': expand('%:t')}
  else
    let title = org#core#headline_title(hl.text)
    let props = org#core#scan_header(hl.lnum).props
    let id    = ''
    if props[0] > 0
      for l in range(props[0] + 1, props[1] - 1)
        let id = matchstr(getline(l), '^\s*:ID:\s\+\zs\S\+')
        if id !=# '' | break | endif
      endfor
    endif
    let entry = {'link': id !=# '' ? 'id:' . id : 'file:' . file . '::*' . title, 'desc': title}
  endif
  let g:org_stored_links = [entry]
        \ + filter(get(g:, 'org_stored_links', []), 'v:val.link !=# entry.link')
  echo 'Stored: ' . s:format(entry.link, entry.desc)
endfunction

" Show every link raw in this window, or back to descriptions only (Emacs'
" org-toggle-link-display).
function! org#link#toggle_display() abort
  let &l:conceallevel = &l:conceallevel ? 0 : 2
  echo 'org: links shown ' . (&l:conceallevel ? 'as descriptions' : 'raw')
endfunction
