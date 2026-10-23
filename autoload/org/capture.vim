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
  " 'template_file' is Emacs' (file "…"): the template is the file's text
  if has_key(a:template, 'template_file')
    let tpl = readfile(expand(a:template.template_file))
    while !empty(tpl) && tpl[-1] =~# '^\s*$'
      call remove(tpl, -1)
    endwhile
    let template_str = join(tpl, "\n")
  else
    let template_str = a:template.template
  endif
  let raw = s:expand_template(template_str, a:template)

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

  " 'file' may be a Funcref of the prompts' answers (Emacs' (file (lambda …)))
  let File = a:template.file
  let b:org_capture_file = expand(type(File) == v:t_func ? call(File, [s:answers]) : File)
  let b:org_capture_headline = get(a:template, 'headline', '')
  let b:org_capture_prepend = get(a:template, 'prepend', 0)
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
  let entry    = getline(1, '$')
  if headline !=# ''
    let lines = org#core#file_entry(existing, '* ' . headline, entry)
  elseif get(b:, 'org_capture_prepend', 0)
    " Emacs' :prepend: before the first headline, after the file's preamble
    let first = match(existing, '^\*\+\s')
    let lines = first < 0 ? existing + entry
          \ : existing[: first - 1] + entry + existing[first :]
  else
    let lines = existing + entry
  endif
  call writefile(lines, target)

  echo 'Captured to: ' . target
  bwipeout!
endfunction

function! org#capture#abort() abort
  echo 'Capture aborted'
  bwipeout!
endfunction

function! s:expand_template(template, tpl) abort
  let result = a:template
  " %<FORMAT>: the current time through strftime, first so that a prompt's
  " default can use it
  let result = substitute(result, '%<\([^>]*\)>', '\=strftime(submatch(1))', 'g')
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

  " Prompts, asked in order of appearance; %\N repeats the Nth answer.
  "   %^{Prompt|default|choice…}  text, <Tab> completing the choices and
  "                                the template's 'complete'[Prompt]()
  "   %^{Prompt}t / T / u / U       a date (+1w, a day name, YYYY-MM-DD, an
  "                                optional HH:MM) as an active / inactive
  "                                timestamp; its %\N is the YYYY-MM-DD
  let s:answers = []
  let pat = '%^{\([^}]*\)}\([tTuU]\=\)'
  while 1
    let m = matchlist(result, pat)
    if empty(m)
      break
    endif
    let parts = split(m[1], '|', 1)
    if m[2] ==# ''
      let s:choices = parts[1:]
      let Extra = get(get(a:tpl, 'complete', {}), parts[0], v:null)
      if Extra isnot v:null
        let s:choices += call(Extra, [])
      endif
      let answer = input(parts[0] . ': ', get(parts, 1, ''), 'customlist,org#capture#complete')
      let text   = answer
    else
      let [answer, text] = s:read_date(parts[0], get(parts, 1, ''), m[2])
    endif
    call add(s:answers, answer)
    let result = substitute(result, pat, '\=text', '')
  endwhile
  for n in range(len(s:answers), 1, -1)
    let result = substitute(result, '%\\' . n, '\=s:answers[n - 1]', 'g')
  endfor
  redraw

  " A timestamp typed without a day name (<2026-10-29 20:30>) gets one, and
  " a wrong one is corrected
  let result = substitute(result,
        \ '[[<]\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)\ze\%(\s\+\d\|[]>]\)',
        \ '\=submatch(0) . " " . org#core#dow(submatch(1) + 0, submatch(2) + 0, submatch(3) + 0)',
        \ 'g')
  return join(map(split(result, '\n', 1), 'org#core#fix_dow(v:val)'), "\n")
endfunction

" <Tab> in a text prompt: the choices that start with what was typed.
function! org#capture#complete(lead, line, pos) abort
  return filter(copy(get(s:, 'choices', [])),
        \ 'stridx(tolower(v:val), tolower(a:line)) == 0')
endfunction

" Ask {prompt} for a date until one can be read. Returns [YYYY-MM-DD, the
" timestamp]: active for {kind} t / T, inactive for u / U.
function! s:read_date(prompt, default, kind) abort
  while 1
    let raw  = input(a:prompt . ' (YYYY-MM-DD, +1w, day name [HH:MM]): ', a:default)
    let date = s:parse_date(raw)
    if !empty(date)
      break
    endif
    echohl WarningMsg | echo 'org: cannot read a date in "' . raw . '"' | echohl None
  endwhile
  let [y, m, d] = org#core#jdn_to_ymd(date[0])
  let ymd   = printf('%04d-%02d-%02d', y, m, d)
  let stamp = ymd . ' ' . org#core#dow(y, m, d) . (date[1] ==# '' ? '' : ' ' . date[1])
  return [ymd, a:kind =~# '[tT]' ? '<' . stamp . '>' : '[' . stamp . ']']
endfunction

" {raw} as [jdn, 'HH:MM' or ''], or [] when it is not a date. Read as
" Emacs' org-read-date does: empty or . is today, +N / +Nd / +Nw / +Nm / +Ny
" counts from today, a day name is the next such day (today included), and
" a trailing H:MM is the time.
function! s:parse_date(raw) abort
  let s    = tolower(trim(a:raw))
  let time = ''
  let m = matchlist(s, '^\(.\{-}\)\s*\<\(\d\{1,2}\):\(\d\d\)$')
  if !empty(m) && m[2] < 24 && m[3] < 60
    let [s, time] = [m[1], printf('%02d:%s', m[2], m[3])]
  endif
  let today = org#core#jdn(strftime('%Y') + 0, strftime('%m') + 0, strftime('%d') + 0)

  if s =~# '^\%(\|\.\|today\|hoy\)$'
    return [today, time]
  elseif s =~# '^\%(tomorrow\|mañana\)$'
    return [today + 1, time]
  endif

  let m = matchlist(s, '^+\(\d\+\)\([dwmy]\=\)$')
  if !empty(m)
    let n = str2nr(m[1])
    if m[2] =~# '[my]'
      let [y, mo, d] = org#core#jdn_to_ymd(today)
      let months = (y * 12 + mo - 1) + (m[2] ==# 'y' ? 12 * n : n)
      let [y, mo] = [months / 12, months % 12 + 1]
      return [org#core#jdn(y, mo, min([d, org#core#days_in_month(y, mo)])), time]
    endif
    return [today + (m[2] ==# 'w' ? 7 * n : n), time]
  endif

  let m = matchlist(s, '^\(\d\{4}\)-\(\d\{1,2}\)-\(\d\{1,2}\)$')
  if !empty(m) && m[2] >= 1 && m[2] <= 12
        \ && m[3] >= 1 && m[3] <= org#core#days_in_month(m[1] + 0, m[2] + 0)
    return [org#core#jdn(m[1] + 0, m[2] + 0, m[3] + 0), time]
  endif

  " A day name in the user's locale (jue, jueves, mié) or in English (thu)
  let plain   = tr(s, 'áéíóú', 'aeiou')
  let english = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
  if strchars(plain) >= 2
    for k in range(7)
      let [y, mo, d] = org#core#jdn_to_ymd(today + k)
      for name in [tr(tolower(org#core#dow(y, mo, d)), 'áéíóú', 'aeiou'),
            \      english[(today + k) % 7]]
        if stridx(name, plain) == 0 || stridx(plain, name) == 0
          return [today + k, time]
        endif
      endfor
    endfor
  endif
  return []
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
