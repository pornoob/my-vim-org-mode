" autoload/org/sparse.vim — Sparse trees (Emacs' C-c /): fold the buffer so
" only matching lines and their parent headlines stay visible.

" Ask which kind of sparse tree, then build it. {kind} skips the prompt:
" 'r' regexp, 't' TODO entries, 'm' headlines with a tag.
function! org#sparse#tree(...) abort
  let kind = a:0 ? a:1 : ''
  if kind ==# ''
    echo 'Sparse tree: [r]egexp  [t]odo  [m]atch tag'
    let ch   = getchar()
    let kind = type(ch) == type(0) ? nr2char(ch) : ch
    echo ''
  endif

  if kind ==# 'r'
    let pat = input('Regexp: ')
  elseif kind ==# 't'
    let active = org#core#keywords().active
    if empty(active)
      echo 'org: no active TODO keywords'
      return
    endif
    let pat = '\C^\*\+\s\+\%(' . join(map(copy(active), 'escape(v:val, "\\")'), '\|') . '\)\>'
  elseif kind ==# 'm'
    let tag = trim(input('Tag: ', '', 'customlist,org#tags#complete'))
    let pat = tag ==# '' ? '' : '\C^\*\+\s.*\s:\%(\S*:\)\=' . escape(tag, '\.*$^~[]') . ':\%(\S*:\)\=\s*$'
  else
    return
  endif
  echo ''
  if pat ==# ''
    return
  endif
  call s:show(pat)
endfunction

" Fold everything, reveal each line matching {pat} (and so its parent
" headlines), highlight the matches and make n / N jump between them.
function! s:show(pat) abort
  call org#sparse#clear()
  let hits = []
  for lnum in range(1, line('$'))
    " =~ like a search: a typed regexp follows 'ignorecase'; the TODO and
    " tag patterns carry \C
    if getline(lnum) =~ a:pat
      call add(hits, lnum)
    endif
  endfor
  if empty(hits)
    echo 'org: no match for ' . a:pat
    return
  endif

  let view = winsaveview()
  normal! zM
  for lnum in hits
    execute lnum . 'normal! zv'
  endfor
  call winrestview(view)

  let w:org_sparse_match = matchadd('orgSparseMatch', a:pat, 20)
  let @/ = a:pat
  call histadd('/', a:pat)
  echo 'org: ' . len(hits) . ' match' . (len(hits) == 1 ? '' : 'es') . '  (n/N to jump, <C-c><C-c> clears)'
endfunction

" Remove the sparse-tree highlighting. Returns 1 when there was some, so
" <C-c><C-c> can clear it first, as Emacs does.
function! org#sparse#clear() abort
  if !exists('w:org_sparse_match')
    return 0
  endif
  silent! call matchdelete(w:org_sparse_match)
  unlet w:org_sparse_match
  return 1
endfunction
