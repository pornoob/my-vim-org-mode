" autoload/org/checkbox.vim — Checkbox toggle and parent summary update

" Cycle checkbox on the current line: [ ] → [X] → [-] → [ ]
" Accepts [ ] (space) and [] (empty) as unchecked.
function! org#checkbox#toggle() abort
  let lnum = line('.')
  let line = getline(lnum)

  let cb = matchstr(line, '\[\zs[ xX-]\?\ze\]')
  if cb ==# '' && line !~# '\[\]'
    echohl WarningMsg | echo 'No checkbox on this line (expected [ ] [X] or [-])' | echohl None
    return
  endif

  call setline(lnum, s:toggle_cb(line))
  call s:update_parent_summary(lnum)
endfunction

" Toggle all checkboxes in the visual selection.
" Lines without a checkbox are skipped silently.
function! org#checkbox#toggle_visual() abort
  let start = line("'<")
  let vend  = line("'>")
  let child_per_parent = {}

  for lnum in range(start, vend)
    let line = getline(lnum)
    if matchstr(line, '\[\zs[ xX-]\?\ze\]') ==# '' && line !~# '\[\]'
      continue
    endif

    call setline(lnum, s:toggle_cb(line))

    let p = s:find_parent_headline(lnum)
    if p > 0 && !has_key(child_per_parent, p)
      let child_per_parent[p] = lnum
    endif
  endfor

  for child_lnum in values(child_per_parent)
    call s:update_parent_summary(child_lnum)
  endfor
endfunction

" Return a copy of {line} with its checkbox cycled.
function! s:toggle_cb(line) abort
  let cb = matchstr(a:line, '\[\zs[ xX-]\?\ze\]')
  if cb ==# '' || cb ==# ' '
    let new_cb = 'X'
  elseif cb ==# 'x' || cb ==# 'X'
    let new_cb = '-'
  else
    let new_cb = ' '
  endif
  return substitute(a:line, '\[\zs[ xX-]\?\ze\]', new_cb, '')
endfunction

" Walk upward from {lnum}, updating every ancestor headline that carries a
" [n/m] or [%] summary token.  Stops when there are no more parent headlines.
function! s:update_parent_summary(lnum) abort
  let lnum = a:lnum
  while 1
    let parent_lnum = s:find_parent_headline(lnum)
    if parent_lnum == 0
      break
    endif

    let parent_line = getline(parent_lnum)
    let has_count = parent_line =~# '\[\d*/\d*\]'
    let has_pct   = parent_line =~# '\[\d*%\]'

    let has_own_cb = parent_line =~# '\[[ xX-]\?\]'

    if has_count || has_pct || has_own_cb
      let lines = s:get_checkbox_lines(parent_lnum)
      let done  = 0
      let total = len(lines)

      for cl in lines
        let cb = matchstr(getline(cl), '\[\zs[ xX-]\?\ze\]')
        if cb ==# 'x' || cb ==# 'X'
          let done += 1
        endif
      endfor

      " Update [n/m] or [%] summary token
      if has_count
        let summary = printf('[%d/%d]', done, total)
        let parent_line = substitute(parent_line, '\[\d*/\d*\]', summary, '')
      elseif has_pct
        let pct = total > 0 ? (done * 100 / total) : 0
        let summary = printf('[%d%%]', pct)
        let parent_line = substitute(parent_line, '\[\d*%\]', summary, '')
      endif

      " Auto-update the headline's own checkbox to reflect children's state
      if has_own_cb && total > 0
        let own_new = done == total ? 'X' : done == 0 ? ' ' : '-'
        let parent_line = substitute(parent_line, '\[[ xX-]\?\]', '[' . own_new . ']', '')
      endif

      call setline(parent_lnum, parent_line)
    endif

    let lnum = parent_lnum
  endwhile
endfunction

" Walk upward from {lnum} to find the nearest headline.
function! s:find_parent_headline(lnum) abort
  let lnum = a:lnum - 1
  while lnum > 0
    if s:headline_level(lnum) > 0
      return lnum
    endif
    let lnum -= 1
  endwhile
  return 0
endfunction

" Collect DIRECT checkbox children of the headline at {parent_lnum}.
"
" "Direct" means:
"   - Sub-headlines at exactly parent_level+1 that carry a checkbox.
"   - Non-headline list items in the heading body BEFORE any sub-headline.
"     (Once a sub-headline is encountered, list items belong to that child
"      and are excluded from the parent's count.)
function! s:get_checkbox_lines(parent_lnum) abort
  let parent_lv = s:headline_level(a:parent_lnum)
  let result    = []
  let lnum      = a:parent_lnum + 1
  let end       = line('$')
  let in_sub    = 0

  while lnum <= end
    let lv = s:headline_level(lnum)
    if lv > 0
      if lv <= parent_lv
        break
      elseif lv == parent_lv + 1
        let in_sub = 1
        let line = getline(lnum)
        if line =~# '\[\zs[ xX-]\?\ze\]' || line =~# '\[\]'
          call add(result, lnum)
        endif
      endif
      " deeper headlines (lv > parent_lv+1) are skipped; in_sub stays 1
    else
      if !in_sub
        let line = getline(lnum)
        if line =~# '\[\zs[ xX-]\?\ze\]' || line =~# '\[\]'
          call add(result, lnum)
        endif
      endif
    endif
    let lnum += 1
  endwhile

  return result
endfunction

" Return the heading level (number of leading stars) of line {lnum}, or 0.
function! s:headline_level(lnum) abort
  let m = matchlist(getline(a:lnum), '^\(\*\+\)\s')
  return empty(m) ? 0 : len(m[1])
endfunction
