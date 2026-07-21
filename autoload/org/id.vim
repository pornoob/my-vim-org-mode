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

function! s:get_existing_id(headline_lnum) abort
  let lnum = a:headline_lnum + 1
  while lnum <= line('$')
    let l = getline(lnum)
    if l =~# '^\s*:PROPERTIES:'
      let lnum += 1
      while lnum <= line('$')
        let pl = getline(lnum)
        if pl =~# '^\s*:END:'
          break
        elseif pl =~# '^\s*:ID:\s\+\(\S\+\)'
          return substitute(matchstr(pl, '^\s*:ID:\s\+\zs\S\+'), '\s', '', 'g')
        endif
        let lnum += 1
      endwhile
      break
    elseif l =~# '^\s*:LOGBOOK:'
      break
    elseif l =~# '^\s*\(SCHEDULED:\|DEADLINE:\|CLOSED:\)'
      let lnum += 1
    elseif l =~# '^\*'
      break
    else
      break
    endif
  endwhile
  return ''
endfunction

function! s:ensure_property(headline_lnum, key, value) abort
  let lnum = a:headline_lnum + 1
  let insert_after = a:headline_lnum

  while lnum <= line('$')
    let l = getline(lnum)

    if l =~# '^\s*$'
      let lnum += 1

    elseif l =~# '^\s*:PROPERTIES:'
      let lnum += 1
      while lnum <= line('$')
        let pl = getline(lnum)
        if pl =~# '^\s*:END:'
          call append(lnum - 1, '  :' . a:key . ':     ' . a:value)
          return
        endif
        let lnum += 1
      endwhile

    elseif l =~# '^\s*:LOGBOOK:'
      call append(insert_after, ['  :PROPERTIES:', '  :END:'])
      call append(insert_after + 1, '  :' . a:key . ':     ' . a:value)
      return

    elseif l =~# '^\s*\%(SCHEDULED:\|DEADLINE:\|CLOSED:\)'
      let insert_after = lnum
      let lnum += 1

    elseif l =~# '^\*'
      break

    else
      break
    endif
  endwhile

  call append(insert_after, ['  :PROPERTIES:', '  :END:'])
  call append(insert_after + 1, '  :' . a:key . ':     ' . a:value)
endfunction
