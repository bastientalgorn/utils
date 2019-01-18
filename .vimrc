" Color scheme
colorscheme murphy 

" Syntax highlighting
syntax on
"Disable the acces to menu-bar with "alt" 
set winaltkeys=no
" Display line numbers
set number
" Use mouse to copy
set mouse=a
" Allow filetype detection
filetype on
" Allow to change buffer without saving
set hidden

"Set a tab as 4 spaces for all files
set tabstop=4 shiftwidth=4 expandtab
" For make files, do not expand tabs
autocmd FileType gmake,make set noexpandtab shiftwidth=4 softtabstop=0
" Display real tabs as #...
set list
set listchars=tab:#.

" Use ctrl+j or ctrl+k to loop through buffers
nnoremap <C-j> :bn<CR>
nnoremap <C-k> :bp<CR>
inoremap <C-j> <ESC>:bn<CR>
inoremap <C-k> <ESC>:bp<CR>
vnoremap <C-j> <ESC>:bn<CR>
vnoremap <C-k> <ESC>:bp<CR>

" Disable arrows (because otherwise I use them too much)
" But allow them in insert mod
nnoremap <Left> <ESC>
nnoremap <Right> <ESC>
nnoremap <Up> <ESC>
nnoremap <Down> <ESC>
vnoremap <Left> <ESC>
vnoremap <Right> <ESC>
vnoremap <Up> <ESC>
vnoremap <Down> <ESC>



" Map ctrl+z to undo
nnoremap <C-Z> u
" Ctrl+i to exit include mode
inoremap <C-i> <ESC>


" Move lines up and down with alt+k or alt+j
nnoremap <A-k> :m-2<CR>
nnoremap <A-j> :m+<CR>
"inoremap <A-Up> <Esc>:m-2<CR>
"inoremap <A-Down> <Esc>:m+<CR>
vnoremap <A-k> :m '<-2<CR>gv
vnoremap <A-j> :m '>+1<CR>gv 

" Map ctr+s to save file
nnoremap <C-S>        :update<CR>
vnoremap <C-S>   <ESC>:update<CR>
inoremap <C-S>   <ESC>:update<CR>

" Add remove tabs with TAB
inoremap <S-Tab> <ESC><<i
nnoremap <Tab> >>
nnoremap <S-Tab> <<

" Delete new lines
set backspace=indent,eol,start
set noendofline binary
set whichwrap+=<,>,h,l,[,]



" Use F5 to run script
function! Gvr()
    update
    echom "Current file: " @%
    echom "Current dir: " %:p:h
    if filereadable( '%:p:h/run' )
        echom "Found local run file"
        ! '%:p:h/run'
    else
        echom "Call generic gvimrc runner"
        ! exec gvimrun %
    endif
endfunction
nnoremap <F5> :call Gvr()<CR>
nnoremap <F4> :so%<CR>
