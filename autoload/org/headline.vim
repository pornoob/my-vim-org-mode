" ── Subtree helpers ──────────────────────────────────────────────────────────

" Return the last line of the subtree rooted at headline_lnum / level.
" Stops before the next headline of equal or higher rank (fewer stars).
function! s:subtree_end(headline_lnum, level) abort
  let lnum = a:headline_lnum + 1
  while lnum <= line('$')
    let m = matchlist(getline(lnum), '^\(\*\+\)\s')
    if !empty(m) && len(m[1]) <= a:level
      return lnum - 1
    endif
    let lnum += 1
  endwhile
  return line('$')
endfunction

" Add delta stars to the headline on lnum. Minimum level is 1.
function! s:adjust_stars(lnum, delta) abort
  let l = getline(a:lnum)
  let m = matchlist(l, '^\(\*\+\)\(\s\+.*\)$')
  if empty(m) | return | endif
  let new_level = max([1, len(m[1]) + a:delta])
  call setline(a:lnum, repeat('*', new_level) . m[2])
endfunction

" Shared promote/demote implementation.
" Operates on the entire subtree (current headline + all children).
function! s:shift(delta) abort
  let hl = org#core#current_headline()
  if empty(hl)
    echo 'org: not under a headline'
    return
  endif

  if a:delta < 0 && hl.level <= 1
    echo 'org: already at top level'
    return
  endif

  let end_lnum = s:subtree_end(hl.lnum, hl.level)

  for lnum in range(hl.lnum, end_lnum)
    if getline(lnum) =~# '^\*\+\s'
      call s:adjust_stars(lnum, a:delta)
    endif
  endfor
endfunction

" ── Public API ────────────────────────────────────────────────────────────────

" Promote the subtree at the cursor: remove one * from every headline in it.
function! org#headline#promote() abort
  call s:shift(-1)
endfunction

" Demote the subtree at the cursor: add one * to every headline in it.
function! org#headline#demote() abort
  call s:shift(1)
endfunction

" Promote/demote every headline line in the last visual selection.
" Non-headline lines are skipped silently. Level-1 headlines are clamped (not blocked).
function! org#headline#shift_visual(delta) abort
  let start = line("'<")
  let end   = line("'>")
  for lnum in range(start, end)
    if getline(lnum) =~# '^\*\+\s'
      call s:adjust_stars(lnum, a:delta)
    endif
  endfor
endfunction
