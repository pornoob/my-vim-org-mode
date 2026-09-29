" autoload/org/capture.vim — Template-based quick capture

" {from_visual} (optional, default 0): capture was started on a visual
" selection, which then fills %i. Otherwise %i is empty, like Emacs' %i with
" no active region -- not whatever was selected last.
function! org#capture#open(...) abort
  let s:from_visual = a:0 && a:1
  let templates = get(g:, 'org_capture_templates', [])
  if empty(templates)
    echohl WarningMsg
    echo 'No capture templates configured. Set g:org_capture_templates.'
    echohl None
    return
  endif

  let choice = len(templates) == 1 ? templates[0] : s:pick_template(templates)
  if empty(choice)
    return
  endif

  call s:open_capture(choice)
endfunction

function! s:pick_template(templates) abort
  echo 'Capture templates:'
  for t in a:templates
    echo '  ' . t.key . '  ' . t.desc
  endfor
  echo '  q   Cancel'

  let ch = getchar()
  let char = type(ch) == type(0) ? nr2char(ch) : ch
  echo ''

  if char ==# 'q' || char ==# "\<Esc>"
    return {}
  endif

  for t in a:templates
    if t.key ==# char
      return t
    endif
  endfor

  echohl WarningMsg | echo 'Unknown: ' . char | echohl None
  return {}
endfunction

function! s:open_capture(template) abort
  let template_str = a:template.template
  let raw = s:expand_template(template_str)

  let lines = split(raw, '\n', 1)
  let cursor_line = 0
  let cursor_col = 0
  for i in range(len(lines))
    let idx = stridx(lines[i], '%?')
    if idx >= 0
      let lines[i] = substitute(lines[i], '%?', '', '')
      let cursor_line = i + 1
      let cursor_col = idx + 1
      break
    endif
  endfor

  new
  setlocal buftype=acwrite bufhidden=wipe noswapfile nobuflisted
  setlocal filetype=org
  call setline(1, lines)

  if cursor_line > 0
    call cursor(cursor_line, cursor_col > 0 ? cursor_col : 1)
  endif

  let b:org_capture_file = expand(a:template.file)
  let b:org_capture_headline = get(a:template, 'headline', '')
  setlocal nomodified

  nnoremap <buffer> <silent> <C-c><C-c> :call org#capture#finalize()<CR>
  nnoremap <buffer> <silent> <C-c><C-k> :call org#capture#abort()<CR>
  inoremap <buffer> <silent> <C-c><C-c> <Esc>:call org#capture#finalize()<CR>
  inoremap <buffer> <silent> <C-c><C-k> <Esc>:call org#capture#abort()<CR>
endfunction

function! org#capture#finalize() abort
  let target = get(b:, 'org_capture_file', '')
  if target ==# ''
    echohl WarningMsg | echo 'No capture target' | echohl None
    return
  endif

  let existing = filereadable(target) ? readfile(target) : []
  let headline = get(b:, 'org_capture_headline', '')
  call writefile(headline ==# ''
        \ ? existing + getline(1, '$')
        \ : org#core#file_entry(existing, '* ' . headline, getline(1, '$')), target)

  echo 'Captured to: ' . target
  bwipeout!
endfunction

function! org#capture#abort() abort
  echo 'Capture aborted'
  bwipeout!
endfunction

function! s:expand_template(template) abort
  let result = a:template
  let result = substitute(result, '%T', strftime('<%Y-%m-%d %a %H:%M>'), 'g')
  let result = substitute(result, '%t', strftime('[%Y-%m-%d %a %H:%M]'), 'g')
  let result = substitute(result, '%f', escape(expand('%:p'), '\&'), 'g')
  let result = substitute(result, '%F', escape(expand('%:t'), '\&'), 'g')

  let sel = get(s:, 'from_visual', 0) ? s:get_visual_selection() : ''
  if sel !=# ''
    let result = substitute(result, '%i', escape(sel, '\&'), 'g')
  else
    let result = substitute(result, '%i', '', 'g')
  endif

  return result
endfunction

function! s:get_visual_selection() abort
  try
    let start = getpos("'<")
    let end   = getpos("'>")
    let lines = getline(start[1], end[1])
    if empty(lines)
      return ''
    endif
    let lines[-1] = lines[-1][: end[2] - 2]
    let lines[0]  = lines[0][start[2] - 1 :]
    return join(lines, "\n")
  catch
    return ''
  endtry
endfunction
