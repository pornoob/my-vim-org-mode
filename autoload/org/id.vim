" autoload/org/id.vim — ID property management

function! org#id#set() abort
  let hl = org#core#current_headline()
  if empty(hl)
    echohl WarningMsg | echo 'Not on a headline' | echohl None
    return
  endif

  let existing = s:get_existing_id(hl.lnum)
  if existing !=# ''
    echo 'ID already set: ' . existing
    return
  endif

  echo 'ID set: ' . org#id#ensure(hl.lnum)
endfunction

" The :ID: of the headline at {headline_lnum}, created when it has none
" (Emacs' org-id-get-create).
function! org#id#ensure(headline_lnum) abort
  let id = s:get_existing_id(a:headline_lnum)
  if id ==# ''
    let id = s:generate_uuid()
    call org#core#set_property(a:headline_lnum, 'ID', id)
  endif
  return id
endfunction

function! s:generate_uuid() abort
  if executable('uuidgen')
    return substitute(trim(system('uuidgen')), '[ \r\n]', '', 'g')
  endif
  if has('win32') || has('win64')
    let cmd = 'powershell -NoProfile -Command "[guid]::NewGuid().ToString()"'
    return substitute(trim(system(cmd)), '[ \r\n]', '', 'g')
  endif
  let seed = localtime() . getpid() . reltimestr(reltime())
  let hash = sha256(seed)
  return hash[0:7] . '-' . hash[8:11] . '-4' . hash[13:15] . '-' .
        \ printf('%02x', (8 + and(str2nr(hash[16], 16), 3))) . hash[17:19] . '-' .
        \ hash[20:31]
endfunction

function! s:get_existing_id(headline_lnum) abort
  let props = org#core#scan_header(a:headline_lnum).props
  if props[0] == 0
    return ''
  endif
  for lnum in range(props[0] + 1, props[1] - 1)
    let pl = getline(lnum)
    if pl =~# '^\s*:ID:\s\+\S'
      return substitute(matchstr(pl, '^\s*:ID:\s\+\zs\S\+'), '\s', '', 'g')
    endif
  endfor
  return ''
endfunction
