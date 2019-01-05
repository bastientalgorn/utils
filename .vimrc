
colorscheme desert

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




"Map ctrl+z to undo
nnoremap <C-Z> u

"Move lines up and down with alt+k or alt+j
nnoremap <A-k> :m-2<CR>
nnoremap <A-j> :m+<CR>
"inoremap <A-Up> <Esc>:m-2<CR>
"inoremap <A-Down> <Esc>:m+<CR>
vnoremap <A-k> :m '<-2<CR>gv
vnoremap <A-j> :m '>+1<CR>gv 

" Map ctr+s to save file
nnoremap <silent> <C-S>        :update<CR>
vnoremap <silent> <C-S>   <ESC>:update<CR>
inoremap <silent> <C-S>   <ESC>:update<CR>

" Remove/add comments at the begining of line with alt+h/alt+l
nnoremap <A-h> <<
nnoremap <A-l> >> 


