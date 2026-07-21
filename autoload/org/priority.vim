" autoload/org/priority.vim — Priority cycling [#A] [#B] [#C]

function! org#priority#cycle() abort
  call s:cycle(1)
endfunction

function! org#priority#cycle_back() abort
  call s:cycle(-1)
endfunction

let s:priorities = ['[#A]', '[#B]', '[#C]']

function! s:cycle(dir) abort
  let hl = org#core#current_headline()
  if empty(hl)
    echohl WarningMsg | echo 'Not on a headline' | echohl None
    return
  endif

  let line = getline(hl.lnum)

  let cur = matchstr(line, '\[#[A-Z]\]')

  if empty(cur)
    let next = a:dir > 0 ? s:priorities[0] : s:priorities[-1]
  else
    let idx = index(s:priorities, cur)
    if idx < 0
      let next = a:dir > 0 ? s:priorities[0] : s:priorities[-1]
    else
      let new_idx = idx + a:dir
      if new_idx < 0 || new_idx >= len(s:priorities)
        let next = ''
      else
        let next = s:priorities[new_idx]
      endif
    endif
  endif

  let line = substitute(line, '\s*\[#[A-Z]]', '', '')

  if next !=# ''
    let kw = org#core#keywords()
    let found = 0
    for state in kw.all
      if line =~# '^\*\+ ' . escape(state, '\') . '\>'
        let line = substitute(line,
              \ '^\(\*\+ ' . escape(state, '\') . '\)\(\s\+\)',
              \ '\1 ' . next . '\2', '')
        let found = 1
        break
      endif
    endfor
    if !found
      let line = substitute(line, '^\(\*\+ \)\s*', '\1' . next . ' ', '')
    endif
  endif

  call setline(hl.lnum, line)
  echo 'Priority: ' . (empty(next) ? '(no priority)' : next)
endfunction
