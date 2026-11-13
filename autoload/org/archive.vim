" autoload/org/archive.vim — Archive subtree, the way Emacs' org-archive-subtree
" does with its default settings.

" Move the subtree at the cursor to the archive location, stamped with the
" ARCHIVE_* context properties. With {first} and {last} lines (a visual
" selection), archive every headline in those lines instead, as Emacs does
" with org-loop-over-headlines-in-active-region: a headline inside a subtree
" already taken goes with it.
function! org#archive#subtree(...) abort
  let [afile, heading] = s:location()
  if a:0
    let hls = s:region_headlines(a:1, a:2, afile ==# expand('%:p') ? heading : '')
    if empty(hls)
      echohl WarningMsg | echo 'No headlines in the region' | echohl None
      return
    endif
  else
    let hl = org#core#current_headline()
    if empty(hl)
      echohl WarningMsg | echo 'Not on a headline' | echohl None
      return
    endif
    let hls = [hl]
  endif

  " Take every entry (and its context) before deleting anything
  let spans   = map(copy(hls), '[v:val.lnum, org#core#subtree_end(v:val.lnum)]')
  let entries = map(copy(hls), 's:with_context(v:val, getline(spans[v:key][0], spans[v:key][1]))')

  if afile ==# expand('%:p')
    " Archiving into this same file (location '::* Heading')
    call s:delete(spans)
    let lines = getline(1, '$')
    for entry in entries
      let lines = org#core#file_entry(lines, heading, entry)
    endfor
    silent %delete _
    call setline(1, lines)
  else
    let lines = filereadable(afile) ? readfile(afile)
          \ : ['', 'Archived entries from file ' . expand('%:p'), '']
    for entry in entries
      let lines = heading ==# ''
            \ ? lines + org#core#set_level(entry, 1)
            \ : org#core#file_entry(lines, heading, entry)
    endfor
    call writefile(lines, afile)
    call s:delete(spans)
  endif
  echo 'Archived ' . (len(entries) == 1 ? '' : len(entries) . ' entries ')
        \ . 'to: ' . fnamemodify(afile, ':~') . (heading ==# '' ? '' : ' under ' . heading)
endfunction

" Delete the [first, last] line {spans} (top-down, disjoint) bottom-up, so
" the line numbers still hold.
function! s:delete(spans) abort
  for [first, last] in reverse(copy(a:spans))
    execute 'silent' first . ',' . last . 'delete _'
  endfor
endfunction

" Headlines on lines {first}..{last}, top-down, leaving out those inside an
" earlier one's subtree and the {skip} headline's subtree (the archive heading
" of a same-file location).
function! s:region_headlines(first, last, skip) abort
  let hls  = []
  let lnum = a:first
  while lnum <= a:last
    let m = matchlist(getline(lnum), '^\(\*\+\)\s\+\(.*\)$')
    if empty(m)
      let lnum += 1
      continue
    endif
    if a:skip ==# '' || getline(lnum) !=# a:skip
      call add(hls, {'lnum': lnum, 'level': len(m[1]), 'text': m[2], 'line': m[0]})
    endif
    let lnum = org#core#subtree_end(lnum) + 1
  endwhile
  return hls
endfunction

" [archive file, heading] from g:org_archive_location, in Emacs' syntax
" 'FILE::HEADING': %s in FILE is the current file name, an empty FILE means
" the current file, and an empty HEADING appends at top level.
" Default '%s_archive::' → 'notes.org_archive'.
function! s:location() abort
  let loc   = get(g:, 'org_archive_location', '%s_archive::')
  let parts = split(loc, '::', 1)
  let file  = substitute(parts[0], '%s', escape(expand('%:p'), '\&'), 'g')
  let file  = file ==# '' ? expand('%:p') : fnamemodify(expand(file), ':p')
  return [file, trim(get(parts, 1, ''))]
endfunction

" Return the subtree {lines} with ARCHIVE_TIME, ARCHIVE_FILE, ARCHIVE_OLPATH,
" ARCHIVE_CATEGORY and ARCHIVE_TODO added to its :PROPERTIES: drawer. The
" drawer is edited in a scratch buffer so org#core#set_property's placement
" rules apply unchanged.
function! s:with_context(hl, lines) abort
  let props = [
        \ ['ARCHIVE_TIME',     strftime('%Y-%m-%d %a %H:%M')],
        \ ['ARCHIVE_FILE',     fnamemodify(expand('%:p'), ':~')],
        \ ['ARCHIVE_OLPATH',   s:olpath(a:hl)],
        \ ['ARCHIVE_CATEGORY', s:category()],
        \ ['ARCHIVE_TODO',     s:todo(a:lines[0])],
        \ ]

  noautocmd silent new
  setlocal buftype=nofile bufhidden=wipe noswapfile
  call setline(1, a:lines)
  for [key, value] in props
    if value !=# ''
      call org#core#set_property(1, key, value)
    endif
  endfor
  let result = getline(1, '$')
  noautocmd silent close
  return result
endfunction

" Titles of the ancestors of {hl}, outermost first, joined with '/'.
function! s:olpath(hl) abort
  let path  = []
  let level = a:hl.level
  let lnum  = a:hl.lnum - 1
  while lnum > 0 && level > 1
    let m = matchlist(getline(lnum), '^\(\*\+\)\s\+\(.*\)$')
    if !empty(m) && len(m[1]) < level
      call insert(path, org#core#headline_title(m[2]))
      let level = len(m[1])
    endif
    let lnum -= 1
  endwhile
  return join(path, '/')
endfunction

" #+CATEGORY of the file, or its name without extension.
function! s:category() abort
  for lnum in range(1, min([line('$'), 200]))
    let m = matchstr(getline(lnum), '^\c#+CATEGORY:\s*\zs.*')
    if m !=# ''
      return trim(m)
    endif
  endfor
  return expand('%:t:r')
endfunction

function! s:todo(headline) abort
  for kw in org#core#keywords().all
    if a:headline =~# '^\*\+\s\+\V' . escape(kw, '\') . '\m\%(\s\|$\)'
      return kw
    endif
  endfor
  return ''
endfunction
