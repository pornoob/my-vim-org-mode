" ── Fold expression ─────────────────────────────────────────────────────────
" Headlines         → '>N'
" #+BEGIN_* / :X:   → 'a1'  (open relative fold; nests inside any headline)
" #+END_* / :END:   → '='   (closing line stays inside the fold)
" line after close  → 's1'  (subtract 1; fold ends after the close line)
" everything else   → '='

function! org#fold#expr(lnum) abort
  let line = getline(a:lnum)

  let stars = matchstr(line, '^\*\+')
  if !empty(stars)
    return '>' . len(stars)
  endif

  " Block / drawer open
  if line =~? '^#+BEGIN_\w\+'
    return 'a1'
  endif
  if line =~? '^\s*:\%(PROPERTIES\|LOGBOOK\):$'
    return 'a1'
  endif

  " Block / drawer close (close line stays inside the fold)
  if line =~? '^#+END_\w\+'
    return '='
  endif
  if line =~? '^\s*:END:$'
    return '='
  endif

  " Line immediately after any close: subtract 1 so the fold ends there
  let l:prev = getline(a:lnum - 1)
  if l:prev =~? '^#+END_\w\+\|^\s*:END:$'
    return 's1'
  endif

  return '='
endfunction

" ── Keyword helpers ──────────────────────────────────────────────────────────
" s:buf_kws(): keyword list that mirrors what syntax/org.vim sees.
" Reads #+SEQ_TODO / #+TODO from the current buffer (first 200 lines) so that
" file-local keywords (WAITING, PAYED, CANCELLED …) are included.
" Cached in b:org_kw_cache; OrgReload clears it with `unlet! b:org_kw_cache`.
function! s:buf_kws() abort
  if exists('b:org_kw_cache')
    return b:org_kw_cache
  endif
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
  let count = v:foldend - v:foldstart

  " Block / drawer fold: show the opening line verbatim with line count
  if line =~? '^#+BEGIN_\w\+\|^\s*:\%(PROPERTIES\|LOGBOOK\):$'
    return line . '  (' . count . 'L)'
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
  return repeat('*', level) . ' ' . prefix . text . '  (' . count . 'L)'
endfunction

" ── Fold text highlights ──────────────────────────────────────────────────────
" matchadd() applies to all window content including fold text lines —
" this is the only pure-Vim way to colour foldtext in Vim 9.x.
" IDs are window-local (w:) because matchadd() is window-local.
function! org#fold#setup_hl() abort
  call org#fold#clear_hl()
  let w:org_fold_matches = []

  " TODO/DONE/WAITING/… keywords after the stars in headline fold text
  for kw in s:buf_kws()
    if hlexists('orgKw_' . kw)
      let pat = '^\*\+\s\+\zs' . escape(kw, '\') . '\>'
      call add(w:org_fold_matches, matchadd('orgKw_' . kw, pat, 12))
    endif
  endfor

  " Priority cookie [#A] etc.
  if hlexists('orgPriority')
    call add(w:org_fold_matches,
          \ matchadd('orgPriority', '\[#[A-Z]\]', 12))
  endif

  " #+BEGIN_* / #+END_* marker in block fold text lines
  if hlexists('orgBlockBound')
    call add(w:org_fold_matches,
          \ matchadd('orgBlockBound', '\c^#+\%(BEGIN\|END\)_\w\+', 12))
  endif

  " (NL) line-count suffix
  if hlexists('FoldColumn')
    call add(w:org_fold_matches,
          \ matchadd('FoldColumn', '\s\+(\d\+L)$', 12))
  endif
endfunction

function! org#fold#clear_hl() abort
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
  let line = getline('.')
  if line =~# '^\*' || line =~? '^#+BEGIN_\w\+\|^\s*:\%(PROPERTIES\|LOGBOOK\):$'
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
    if getline(lnum) =~# '^\*' && foldclosed(lnum) >= 0
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
      if getline(lnum) =~# '^\*' && foldlevel(lnum) > 0
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
