" autoload/org/dispatch.vim — Context-sensitive "do the right thing" command
" Mirrors Emacs org-mode's C-c C-c: inspect what's under the cursor and
" dispatch to whichever org# function applies (clock, checkbox, clocktable…).

" Is lnum inside a #+BEGIN: clocktable … #+END: block?
function! s:in_clocktable(lnum) abort
  let l = a:lnum
  while l > 0
    let gl = getline(l)
    if gl =~? '^#+BEGIN:\s*clocktable' | return 1 | endif
    if gl =~? '^#+END:'                | return 0 | endif
    let l -= 1
  endwhile
  return 0
endfunction

function! org#dispatch#ctrl_c() abort
  let lnum = line('.')
  let l    = getline(lnum)

  " Closed CLOCK entry → recalculate its duration
  if l =~# '^\s*CLOCK:\s*\[.\{-}\]--\[.\{-}\]'
    call org#clock#update()
    return
  endif

  " Open (running) CLOCK entry → close it
  if l =~# '^\s*CLOCK:\s*\[[^]]*\]\s*$'
    call org#clock#out()
    return
  endif

  " Checkbox item → toggle, and refresh any parent [n/m] cookie
  if l =~# '^\s*\%([-*+]\|\d\+[.)]\)\s\+\[[ xX-]\?\]'
    call org#checkbox#toggle()
    return
  endif

  " On or inside a clocktable block → refresh its contents
  if l =~? '^#+\%(BEGIN\|END\):\?\s*clocktable' || s:in_clocktable(lnum)
    call org#clockreport#update()
    return
  endif

  " On a link → open/follow it
  if l =~# '\[\[.\{-}\]\]'
    call org#link#open()
    return
  endif

  echo 'org: nothing to update here'
endfunction
