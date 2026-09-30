" autoload/org/refile.vim — Move a subtree under another headline, in this file
" or any agenda file, the way Emacs' org-refile does with Doom's settings:
" targets up to g:org_refile_maxlevel, chosen by outline path 'file.org/A/B'.

" Refile the subtree at the cursor to a target picked with completion.
function! org#refile#subtree() abort
  let hl = org#core#current_headline()
  if empty(hl)
    echohl WarningMsg | echo 'Not on a headline' | echohl None
    return
  endif
  let last    = org#core#subtree_end(hl.lnum)
  let targets = s:targets(hl.lnum, last)
  let s:paths = map(copy(targets), 'v:val.path')

  let answer = trim(input('Refile to: ', '', 'customlist,org#refile#complete'))
  echo ''
  if answer ==# ''
    return
  endif
  let hits = s:match(targets, answer)
  if len(hits) != 1
    echohl WarningMsg
    echo empty(hits) ? 'No refile target matches: ' . answer
          \ : len(hits) . ' targets match "' . answer . '"; be more specific'
    echohl None
    return
  endif

  call s:move(hl.lnum, last, hits[0])
  echo 'Refiled to ' . hits[0].path
endfunction

" Completion for the prompt: outline paths containing every word typed.
function! org#refile#complete(lead, line, pos) abort
  return map(s:match(map(copy(get(s:, 'paths', [])), '{"path": v:val}'), a:line),
        \ 'v:val.path')
endfunction

" Targets whose path equals {query}, or else contains each of its words
" (case-insensitive).
function! s:match(targets, query) abort
  let exact = filter(copy(a:targets), 'v:val.path ==# a:query')
  if !empty(exact)
    return exact
  endif
  let words = split(tolower(a:query))
  return filter(copy(a:targets),
        \ {_, t -> empty(filter(copy(words), {_, w -> stridx(tolower(t.path), w) < 0}))})
endfunction

" ── Targets ───────────────────────────────────────────────────────────────────

" All refile targets: this file and the agenda files, each as a top-level
" target ('file.org') plus its headlines down to g:org_refile_maxlevel. The
" subtree being moved (lines {first}..{last} of this buffer) is left out.
function! s:targets(first, last) abort
  let here  = expand('%:p')
  let files = [here] + filter(org#core#agenda_files(), 'fnamemodify(v:val, ":p") !=# here')
  let names = map(copy(files), 'fnamemodify(v:val, ":t")')

  let targets = []
  for i in range(len(files))
    let file = fnamemodify(files[i], ':p')
    " A file name shared by two targets is shown with its path
    let name = count(names, names[i]) > 1 ? fnamemodify(file, ':~') : names[i]
    call add(targets, {'path': name, 'file': file, 'idx': -1})
    let lines = s:lines(file)
    let skip  = file ==# here ? [a:first - 1, a:last - 1] : [-1, -1]
    call extend(targets, s:headlines(lines, file, name, skip))
  endfor
  return targets
endfunction

function! s:headlines(lines, file, name, skip) abort
  let maxlevel = get(g:, 'org_refile_maxlevel', 3)
  let out   = []
  let stack = []      " titles of the ancestors of the current line
  for idx in range(len(a:lines))
    let m = matchlist(a:lines[idx], '^\(\*\+\)\s\+\(.*\)$')
    if empty(m)
      continue
    endif
    let level = len(m[1])
    " (stack[: -1] would be the whole list, not an empty one)
    let stack = (level > 1 ? stack[: level - 2] : []) + [org#core#headline_title(m[2])]
    if level <= maxlevel && (idx < a:skip[0] || idx > a:skip[1])
      call add(out, {'path': a:name . '/' . join(stack, '/'), 'file': a:file, 'idx': idx})
    endif
  endfor
  return out
endfunction

" A file's current lines: from its buffer when loaded (it may hold unsaved
" changes), else from disk.
function! s:lines(file) abort
  if a:file ==# expand('%:p')
    return getline(1, '$')
  endif
  let bnr = bufnr(a:file)
  return bnr > 0 && bufloaded(bnr) ? getbufline(bnr, 1, '$') : readfile(a:file)
endfunction

" ── Moving ────────────────────────────────────────────────────────────────────

" Move lines {first}..{last} of this buffer under {target}. A target file that
" is loaded is changed in its buffer and left unsaved, as Emacs does; one that
" is not is written directly.
function! s:move(first, last, target) abort
  let entry = getline(a:first, a:last)
  let here  = expand('%:p')

  if a:target.file ==# here
    execute 'silent' a:first . ',' . a:last . 'delete _'
    let idx = a:target.idx > a:last - 1 ? a:target.idx - len(entry) : a:target.idx
    let lines = getline(1, '$')
    let new = idx < 0 ? lines + org#core#set_level(entry, 1)
          \ : org#core#insert_child(lines, idx, entry)
    call s:replace_buffer(bufnr('%'), lines, new)
    call cursor(min([a:first, line('$')]), 1)
    return
  endif

  let lines = s:lines(a:target.file)
  let new = a:target.idx < 0 ? lines + org#core#set_level(entry, 1)
        \ : org#core#insert_child(lines, a:target.idx, entry)
  let bnr = bufnr(a:target.file)
  if bnr > 0 && bufloaded(bnr)
    call s:replace_buffer(bnr, lines, new)
  else
    call writefile(new, a:target.file)
  endif
  execute 'silent' a:first . ',' . a:last . 'delete _'
  call cursor(min([a:first, line('$')]), 1)
endfunction

" Turn buffer {bnr} from {old} into {new}, which only differ by lines inserted
" at one point, by appending just those lines (keeps marks and undo small).
function! s:replace_buffer(bnr, old, new) abort
  let at = 0
  while at < len(a:old) && a:old[at] ==# a:new[at]
    let at += 1
  endwhile
  call appendbufline(a:bnr, at, a:new[at : at + len(a:new) - len(a:old) - 1])
endfunction
