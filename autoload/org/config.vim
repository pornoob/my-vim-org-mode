" Compute the plugin root from this file's location:
" autoload/org/config.vim → :h → autoload/org → :h → autoload → :h → root
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h')

" Reload org-mode syntax and ftplugin for the current buffer.
" Safe to call after changing any g:org_* variable or #+SEQ_TODO: directive.
function! org#config#reload() abort
  let l:in_agenda = bufname('%') ==# '[Org Agenda]'

  if !l:in_agenda && &filetype !=# 'org'
    echohl WarningMsg
    echo 'org: OrgReload must be called from an org buffer or the agenda'
    echohl None
    return
  endif

  " ── Steps 1–2: buffer-specific (syntax + ftplugin) — org buffers only ─────
  if !l:in_agenda
    unlet! b:org_kw_cache

    let l:syn = s:root . '/syntax/org.vim'
    if !filereadable(l:syn)
      echohl ErrorMsg | echo 'org: cannot find ' . l:syn | echohl None
      return
    endif
    unlet! b:current_syntax
    syntax clear
    for l:g in ['orgHeadline1','orgHeadline2','orgHeadline3','orgHeadline4',
              \ 'orgHeadline5','orgHeadline6','orgHeadline7','orgHeadline8',
              \ 'orgStars1','orgStars2','orgStars3','orgStars4',
              \ 'orgStars5','orgStars6','orgStars7','orgStars8',
              \ 'orgPriority','orgPriorityA','orgPriorityB','orgPriorityC',
              \ 'orgTag','orgTimestampActive','orgTimestampInactive',
              \ 'orgPlanning','orgPropertyKey','orgProperties','orgLogbook',
              \ 'orgClockLine','orgClockDuration','orgBlockBound','orgMetaKey',
              \ 'orgComment','orgLink','orgBold','orgItalic','orgCode',
              \ 'orgVerbatim','orgStrike','orgListBullet','orgListNum',
              \ 'orgCheckboxDone','orgCheckboxIndet','orgCheckboxTodo',
              \ 'orgCheckboxSummary','orgHRule']
      execute 'silent! highlight clear ' . l:g
    endfor
    unlet l:g
    execute 'source ' . fnameescape(l:syn)

    let l:ftp = s:root . '/ftplugin/org.vim'
    if !filereadable(l:ftp)
      echohl ErrorMsg | echo 'org: cannot find ' . l:ftp | echohl None
      return
    endif
    if exists('b:undo_ftplugin')
      try
        execute b:undo_ftplugin
      catch
      endtry
      unlet b:undo_ftplugin
    endif
    unlet! b:did_ftplugin
    execute 'source ' . fnameescape(l:ftp)
  endif

  " ── Steps 3–4: global (commands + autoload) — always ──────────────────────
  let l:plug = s:root . '/plugin/org.vim'
  if filereadable(l:plug)
    unlet! g:loaded_org
    execute 'source ' . fnameescape(l:plug)
  endif

  let l:auto = substitute(s:root . '/autoload/org', '\\', '/', 'g')
  for l:af in glob(l:auto . '/*.vim', 0, 1)
    if l:af =~# 'config\.vim$' | continue | endif
    execute 'source ' . fnameescape(l:af)
  endfor

  " ── Step 5: finalize ──────────────────────────────────────────────────────
  if l:in_agenda
    call org#agenda#refresh()
  else
    syntax sync fromstart
    call org#fold#update_block_bg()
  endif

  redraw!
  echo 'org: reloaded'
endfunction
