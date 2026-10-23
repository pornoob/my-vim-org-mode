" autoload/org/note.vim — free notes on an entry (Emacs' org-add-note, C-c C-z)

" Prompt for a note and log it at the top of the entry's :LOGBOOK:, under
" Emacs' default heading "Note taken on [timestamp]". An empty note (or
" <Esc>) writes nothing.
function! org#note#add() abort
  let hl = org#core#current_headline()
  if empty(hl)
    echohl WarningMsg | echo 'Not on a headline' | echohl None
    return
  endif
  let note = trim(input('Note: '))
  if empty(note)
    return
  endif
  call org#core#log_item(hl.lnum,
        \ ['Note taken on ' . org#core#format_ts(localtime(), 0), note])
endfunction
