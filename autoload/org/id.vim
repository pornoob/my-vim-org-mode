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

  let uuid = s:generate_uuid()
  call s:ensure_property(hl.lnum, 'ID', uuid)
  echo 'ID set: ' . uuid
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

" Scan the header block of the entry at {headline_lnum}: planning lines, blank
" lines and complete drawers, in whatever order the file happens to use. Some
" files put :LOGBOOK: before :PROPERTIES:, so the scan must step over a whole
" drawer instead of giving up at the first one it meets.
" Returns {'props': [start, end], 'insert_after': lnum, 'indent': str};
" props is [0, 0] when the entry has no :PROPERTIES: drawer.
function! s:scan_header(headline_lnum) abort
  let lnum         = a:headline_lnum + 1
  let last         = line('$')
  let insert_after = a:headline_lnum
  let props        = [0, 0]
  let indent       = ''

  while lnum <= last
    let l = getline(lnum)

    if l =~# '^\s*$'
      let lnum += 1

    elseif l =~# '^\s*\%(SCHEDULED:\|DEADLINE:\|CLOSED:\)'
      " A new :PROPERTIES: drawer belongs just after the planning lines
      let insert_after = lnum
      if empty(indent) | let indent = matchstr(l, '^\s*') | endif
      let lnum += 1

    elseif l =~# '^\s*:\a[[:alnum:]_-]*:\s*$' && l !~? '^\s*:END:\s*$'
      let is_props = l =~? '^\s*:PROPERTIES:\s*$'
      let dstart   = lnum
      let lnum    += 1
      while lnum <= last && getline(lnum) !~? '^\s*:END:\s*$'
            \ && getline(lnum) !~# '^\*'
        let lnum += 1
      endwhile
      if lnum > last || getline(lnum) !~? '^\s*:END:\s*$'
        break   " unterminated drawer: do not walk off into the rest of the file
      endif
      if is_props && props[0] == 0
        let props  = [dstart, lnum]
        let indent = matchstr(l, '^\s*')
      elseif empty(indent)
        let indent = matchstr(l, '^\s*')
      endif
      let lnum += 1

    else
      break
    endif
  endwhile

  return {'props': props, 'insert_after': insert_after, 'indent': indent}
endfunction

function! s:get_existing_id(headline_lnum) abort
  let props = s:scan_header(a:headline_lnum).props
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

function! s:ensure_property(headline_lnum, key, value) abort
  let hdr  = s:scan_header(a:headline_lnum)
  let line = hdr.indent . ':' . a:key . ':     ' . a:value

  " Reuse the entry's existing drawer wherever it sits
  if hdr.props[0] > 0
    call append(hdr.props[1] - 1, line)
    return
  endif

  call append(hdr.insert_after, [hdr.indent . ':PROPERTIES:', hdr.indent . ':END:'])
  call append(hdr.insert_after + 1, line)
endfunction
