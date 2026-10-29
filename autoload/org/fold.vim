" ── Fold expression ─────────────────────────────────────────────────────────
" Absolute levels, computed for the whole buffer in one pass and cached per
" b:changedtick:
"   headline ('*'s then a space)          → '>N'  (N = number of stars)
"   its body                              → N
"   #+BEGIN_* / :PROPERTIES: / :LOGBOOK:  → '>N+1', through its closing
"   #+END_* / :END: line, then back to N
" Absolute levels matter: a drawer that opens right after another one closes
" (:LOGBOOK: then :PROPERTIES:) starts a sibling fold instead of nesting.

function! org#fold#expr(lnum) abort
  if get(b:, 'org_fold_tick', -1) != b:changedtick
    let b:org_fold_levels = s:levels()
    let b:org_fold_tick   = b:changedtick
  endif
  return get(b:org_fold_levels, a:lnum - 1, '=')
endfunction

function! s:levels() abort
  let levels = []
  let hlevel = 0
  let inside = ''      " '' | 'block' | 'drawer'
  for line in getline(1, '$')
    let stars = matchstr(line, '^\*\+\ze\s')
    if !empty(stars)
      let hlevel = len(stars)
      let inside = ''
      call add(levels, '>' . hlevel)
    elseif inside ==# '' && line =~? '^#+BEGIN_\w\+'
      let inside = 'block'
      call add(levels, '>' . (hlevel + 1))
    elseif inside ==# '' && line =~? '^\s*:\%(PROPERTIES\|LOGBOOK\):\s*$'
      let inside = 'drawer'
      call add(levels, '>' . (hlevel + 1))
    elseif inside !=# ''
      " The closing line still belongs to the fold
      if (inside ==# 'block' && line =~? '^#+END_\w\+')
            \ || (inside ==# 'drawer' && line =~? '^\s*:END:\s*$')
        let inside = ''
      endif
      call add(levels, hlevel + 1)
    else
      call add(levels, hlevel)
    endif
  endfor
  return levels
endfunction

" ── Keyword helpers ──────────────────────────────────────────────────────────
" s:buf_kws(): keyword list that mirrors what syntax/org.vim sees.
" Reads #+SEQ_TODO / #+TODO from the current buffer (first 200 lines) so that
" file-local keywords (WAITING, PAYED, CANCELLED …) are included.
" Cached in b:org_kw_cache until the buffer changes (b:org_kw_tick), so a
" #+SEQ_TODO line added or edited later is picked up; OrgReload clears it too.
function! s:buf_kws() abort
  if exists('b:org_kw_cache') && get(b:, 'org_kw_tick', -1) == b:changedtick
    return b:org_kw_cache
  endif
  let b:org_kw_tick = b:changedtick
  for l:n in range(1, min([line('$'), 200]))
    let l:m = matchlist(getline(l:n),
          \ '^\c\s*#+\%(SEQ_TODO\|TODO\):\s*\(.*\)$')
    if !empty(l:m)
      let l:kws = []
      for l:tok in split(l:m[1], '\s\+')
        if l:tok !=# '|'
          let l:kw = substitute(l:tok, '([^)]*)$', '', '')
          if !empty(l:kw) | call add(l:kws, l:kw) | endif
        endif
      endfor
      let b:org_kw_cache = l:kws
      return l:kws
    endif
  endfor
  let l:raw = get(g:, 'org_todo_keywords', ['TODO', '|', 'DONE'])
  if type(get(l:raw, 0, '')) == type([])
    let b:org_kw_cache = l:raw[0] + get(l:raw, 1, [])
  else
    let b:org_kw_cache = filter(copy(l:raw), {_, v -> v !=# '|'})
  endif
  return b:org_kw_cache
endfunction

" ── Fold text ─────────────────────────────────────────────────────────────────
function! org#fold#text() abort
  let line  = getline(v:foldstart)
  let nlines = v:foldend - v:foldstart

  " Block / drawer fold: show the opening line verbatim with line count
  if line =~? '^#+BEGIN_\w\+\|^\s*:\%(PROPERTIES\|LOGBOOK\):$'
    return line . '  (' . nlines . 'L)'
  endif

  " Headline fold
  let level = len(matchstr(line, '^\*\+'))
  let text  = matchstr(line, '^\*\+\s\+\zs.*')

  " Extract TODO state
  let state = ''
  for kw in s:buf_kws()
    if text =~# '^\C' . kw . '\%(\s\|$\)'
      let state = kw
      let text  = substitute(text, '^\C' . kw . '\s*', '', '')
      break
    endif
  endfor

  " Extract priority [#X]
  let prio = matchstr(text, '^\[#.\]')
  if prio !=# ''
    let text = substitute(text, '^\[#.\]\s*', '', '')
  endif

  let prefix = (state !=# '' ? state . ' ' : '') . (prio !=# '' ? prio . ' ' : '')
  return repeat('*', level) . ' ' . prefix . text . '  (' . nlines . 'L)'
endfunction

" ── Coloured keywords on closed folds ────────────────────────────────────────
" Vim paints a closed fold with Folded alone: matchadd(), syntax and text
" properties never reach fold text (Neovim's List 'foldtext' has no Vim
" equivalent). So each closed headline fold on screen gets a small popup over
" its "TODO [#A]" prefix, drawn in orgKw_{KW} / orgPriority on the Folded
" background. org#fold#kw_popups() runs on SafeState (after zc/zo/zM, <Tab>,
" scrolling, edits, resizes) and only rebuilds a window's popups when what it
" shows changed. Popups belong to the tab page they were made in.

let s:kw_pops = {}     " winid -> {'sig': [...], 'ids': [popup ids]}

function! org#fold#setup_hl() abort
  call org#fold#kw_popups()
endfunction

function! org#fold#kw_popups() abort
  if !exists('*popup_create') || !exists('*prop_type_add')
    return
  endif
  let l:tab = tabpagenr()
  for l:wid in keys(s:kw_pops)
    if win_id2tabwin(l:wid)[0] == 0
      call s:close_pops(l:wid)       " the window was closed
    endif
  endfor
  for l:win in getwininfo()
    if l:win.tabnr != l:tab || win_gettype(l:win.winid) !=# ''
      continue
    endif
    let l:items = getbufvar(l:win.bufnr, '&filetype') ==# 'org'
          \ && getwinvar(l:win.winid, '&foldenable')
          \ ? s:closed_heads(l:win) : []
    let l:sig = [l:win.bufnr, l:win.winrow, l:win.wincol, l:win.width,
          \ l:win.textoff, l:items, hlID('Folded')]
    let l:old = get(s:kw_pops, l:win.winid, {})
    if get(l:old, 'sig', []) == l:sig
      continue
    endif
    call s:close_pops(l:win.winid)
    let s:kw_pops[l:win.winid] = {'sig': l:sig,
          \ 'ids': map(copy(l:items), {_, it -> s:kw_popup(l:win, it)})}
  endfor
endfunction

" [[screen row, column inside the text area, prefix, [[hl group, col, len]…]]…]
" for the closed headline folds visible in window {win}.
function! s:closed_heads(win) abort
  let l:kws = []
  call win_execute(a:win.winid, 'let l:kws = s:buf_kws()')
  let l:out = []
  let l:lnum = a:win.topline
  let l:bot = a:win.botline
  let l:lines = {}
  call win_execute(a:win.winid,
        \ 'for l:n in range(a:win.topline, a:win.botline)'
        \ . '| let l:lines[l:n] = [foldclosed(l:n), foldclosedend(l:n)] | endfor')
  while l:lnum <= l:bot
    let [l:start, l:end] = get(l:lines, l:lnum, [-1, -1])
    if l:start == -1
      let l:lnum += 1
      continue
    endif
    let l:line = getbufline(a:win.bufnr, l:start)[0]
    let l:m = matchlist(l:line, '^\(\*\+\)\s\+\(\S\+\)\%(\s\+\(\[#.\]\)\)\=')
    if !empty(l:m)
      let l:groups = []
      let l:prefix = ''
      if index(l:kws, l:m[2]) >= 0 && hlexists('orgKw_' . l:m[2])
        let l:prefix = l:m[2]
        call add(l:groups, ['orgKw_' . l:m[2], 1, len(l:m[2])])
      endif
      let l:prio = l:prefix !=# '' ? l:m[3] : matchstr(l:line, '^\*\+\s\+\zs\[#.\]')
      if l:prio !=# '' && hlexists('orgPriority')
        let l:col = l:prefix ==# '' ? 1 : len(l:prefix) + 2
        let l:prefix .= (l:prefix ==# '' ? '' : ' ') . l:prio
        call add(l:groups, ['orgPriority', l:col, len(l:prio)])
      endif
      let l:pos = screenpos(a:win.winid, l:start, 1)
      if !empty(l:groups) && l:pos.row > 0
        call add(l:out, [l:pos.row, len(l:m[1]) + 1, l:prefix, l:groups])
      endif
    endif
    let l:lnum = l:end + 1
  endwhile
  return l:out
endfunction

function! s:kw_popup(win, item) abort
  let [l:row, l:offset, l:prefix, l:groups] = a:item
  if l:offset + strdisplaywidth(l:prefix) > a:win.width - a:win.textoff
    return -1                        " would spill past the window's right edge
  endif
  let l:props = []
  for [l:group, l:col, l:len] in l:groups
    let l:type = 'orgFoldPop_' . l:group
    if empty(prop_type_get(l:type))
      call prop_type_add(l:type, {'highlight': l:group, 'combine': 1})
    endif
    call add(l:props, {'type': l:type, 'col': l:col, 'length': l:len})
  endfor
  return popup_create([{'text': l:prefix, 'props': l:props}], {
        \ 'line': l:row, 'col': a:win.wincol + a:win.textoff + l:offset,
        \ 'highlight': 'Folded', 'zindex': 1, 'wrap': 0, 'fixed': 1,
        \ 'scrollbar': 0, 'tabpage': 0})
endfunction

function! s:close_pops(wid) abort
  for l:id in get(get(s:kw_pops, a:wid, {}), 'ids', [])
    if l:id > 0
      call popup_close(l:id)
    endif
  endfor
  silent! call remove(s:kw_pops, a:wid)
endfunction

" Popups this module shows, for tests: [[line, col, text]…] in screen order.
function! org#fold#kw_popup_list() abort
  let l:out = []
  for l:entry in values(s:kw_pops)
    for l:id in l:entry.ids
      if l:id > 0
        let l:p = popup_getpos(l:id)
        call add(l:out, [l:p.line, l:p.col,
              \ getbufline(winbufnr(l:id), 1)[0]])
      endif
    endfor
  endfor
  return sort(l:out)
endfunction

function! org#fold#clear_hl() abort
  call s:close_pops(win_getid())
  for id in get(b:, 'org_fold_matches', [])
    try
      call matchdelete(id)
    catch /^Vim\%((\a\+)\)\=:E80[35]:/
      " Stale ID: the match is already gone, or belongs to another window
    endtry
  endfor
  unlet! b:org_fold_matches
  for id in get(w:, 'org_fold_matches', [])
    try
      call matchdelete(id)
    catch /^Vim\%((\a\+)\)\=:E80[35]:/
      " Stale ID: the match is already gone, or belongs to another window
    endtry
  endfor
  let w:org_fold_matches = []
  for id in get(w:, 'org_block_matches', [])
    try
      call matchdelete(id)
    catch /^Vim\%((\a\+)\)\=:E80[35]:/
      " Stale ID: the match is already gone, or belongs to another window
    endtry
  endfor
  let w:org_block_matches = []
  if exists('*prop_remove')
    silent! call prop_remove({'type': 'orgBlockBar', 'all': 1})
  endif
endfunction

" ── Key handlers ─────────────────────────────────────────────────────────────

" Tab on a headline, block, or drawer open line cycles the fold; elsewhere indents.
function! org#fold#tab() abort
  if org#table#at()
    return org#table#next_field()
  endif
  let line = getline('.')
  if line =~# '^\*\+\s' || line =~? '^#+BEGIN_\w\+\|^\s*:\%(PROPERTIES\|LOGBOOK\):$'
    if foldclosed('.') >= 0
      normal! zo
    else
      normal! zc
    endif
  else
    normal! >>
  endif
endfunction

" ── Block background via matchadd ────────────────────────────────────────────
" matchadd() fills the background to the RIGHT EDGE of the window (same
" mechanism as hlsearch), unlike text-properties which only cover actual
" character cells.  One match per block using a line-range atom:
"   \%>Xl\%<Yl  — matches every character on lines X+1 … Y-1 (exclusive)
" We want lines s..n inclusive → \%>(s-1)l\%<(n+1)l
" Priority 11 overrides syntax (priority ~0) but stays under fold matches (12).
function! org#fold#update_block_bg() abort
  for l:id in get(w:, 'org_block_matches', [])
    silent! call matchdelete(l:id)
  endfor
  let w:org_block_matches = []
  if exists('*prop_remove')
    silent! call prop_remove({'type': 'orgBlockBar', 'all': 1})
  endif

  if !exists('*prop_add') || empty(prop_type_get('orgBlockBar')) | return | endif

  let l:in = 0
  let l:s  = 0
  for l:n in range(1, line('$'))
    let l:line = getline(l:n)
    if !l:in && l:line =~? '^#+BEGIN_\w\+'
      let l:in = 1
      let l:s  = l:n
    elseif l:in && l:line =~? '^#+END_\w\+'
      for l:bl in range(l:s, l:n)
        silent! call prop_add(l:bl, 1,
              \ {'type': 'orgBlockBar', 'text': '│ '})
      endfor
      let l:in = 0
    endif
  endfor
endfunction

" Toggle between OVERVIEW (all closed) and SHOW ALL (all open).
function! org#fold#toggle_all() abort
  let any_closed = 0
  for lnum in range(1, line('$'))
    if getline(lnum) =~# '^\*\+\s' && foldclosed(lnum) >= 0
      let any_closed = 1
      break
    endif
  endfor
  if any_closed
    normal! zR
    let b:org_cycle = 2
    echo 'SHOW ALL'
  else
    normal! zM
    let b:org_cycle = 0
    echo 'OVERVIEW'
  endif
endfunction

" S-Tab cycles OVERVIEW → CONTENTS → SHOW ALL
function! org#fold#shifttab() abort
  if org#table#at()
    return org#table#prev_field()
  endif
  if !exists('b:org_cycle') | let b:org_cycle = 2 | endif
  let b:org_cycle = (b:org_cycle + 1) % 3

  if b:org_cycle == 0
    normal! zM
    echo 'OVERVIEW'
  elseif b:org_cycle == 1
    " Open all headline folds but leave block folds closed
    normal! zM
    let pos = getcurpos()
    for lnum in range(1, line('$'))
      if getline(lnum) =~# '^\*\+\s' && foldlevel(lnum) > 0
        execute lnum . 'foldopen'
      endif
    endfor
    call setpos('.', pos)
    echo 'CONTENTS'
  else
    normal! zR
    echo 'SHOW ALL'
  endif
endfunction
