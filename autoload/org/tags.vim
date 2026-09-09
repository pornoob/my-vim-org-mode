" autoload/org/tags.vim — Tag editing and collection

function! org#tags#edit() abort
  let hl = org#core#current_headline()
  if empty(hl)
    echohl WarningMsg | echo 'Not on a headline' | echohl None
    return
  endif

  let existing = s:get_tags(hl.line)
  let default = join(existing, ',')
  let raw = input('Tags (comma-separated): ', default,
        \ 'customlist,org#tags#complete')
  echo ''

  if raw ==# ''
    return
  endif

  let new_tags = split(raw, '\s*,\s*')
  call s:set_tags(hl.lnum, new_tags)
endfunction

function! org#tags#complete(lead, line, pos) abort
  let known = s:collect_known_tags()
  if a:lead ==# ''
    return known
  endif
  return filter(copy(known), {_, v -> v =~# '^' . a:lead})
endfunction

function! s:get_tags(line) abort
  let m = matchstr(a:line, ':\zs\(\w\+\(:\w\+\)*\)\ze:\s*$')
  if m ==# ''
    return []
  endif
  return split(m, ':')
endfunction

function! s:set_tags(lnum, tags) abort
  let line = getline(a:lnum)
  let line = substitute(line, '\s*:\w\+\(:\w\+\)*:\s*$', '', '')
  if !empty(a:tags)
    let line .= ' :' . join(a:tags, ':') . ':'
  endif
  call setline(a:lnum, line)
endfunction

let s:known_tags_cache = []
let s:known_tags_mtime = 0

function! s:collect_known_tags() abort
  let files = org#core#agenda_files()
  let cache_key = join(files, "\n")
  let mtime = 0
  for f in files
    if filereadable(f)
      let mtime += getftime(f)
    endif
  endfor

  if mtime == s:known_tags_mtime && !empty(s:known_tags_cache)
    return s:known_tags_cache
  endif

  let tags = {}
  for f in files
    if !filereadable(f) | continue | endif
    for line in readfile(f)
      if line =~# '^\*\+ '
        let t = s:get_tags(line)
        for tag in t
          let tags[tag] = 1
        endfor
      endif
    endfor
  endfor

  let s:known_tags_cache = sort(keys(tags))
  let s:known_tags_mtime = mtime
  return s:known_tags_cache
endfunction

