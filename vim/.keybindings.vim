let mapleader = "\<space>"

" disable arrow navigation keys :(
noremap <Up> <NOP>
noremap <Down> <NOP>
noremap <Left> <NOP>
noremap <Right> <NOP>

noremap <silent> <leader>h :wincmd h<CR>
noremap <silent> <leader>j :wincmd j<CR>
noremap <silent> <leader>k :wincmd k<CR>
noremap <silent> <leader>l :wincmd l<CR>
noremap <silent> <leader>ws :wincmd s<CR>
noremap <silent> <leader>wv :wincmd v<CR>
noremap <silent> <leader>wc :wincmd c<CR>
noremap <leader>s :update<CR>
"stop highlighting search
nnoremap <leader><space> :nohlsearch<CR> 
nnoremap <leader>z za " toggle folding
nnoremap <leader>ew :e <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <leader>es :sp <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <leader>ev :vsp <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <leader>et :tabe <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <silent> <leader>[ :exe "resize " . (winheight(0) * 3/2)<CR>
nnoremap <silent> <leader>] :exe "resize " . (winheight(0) * 2/3)<CR>
nnoremap <silent> <leader>< :exe "vertical resize " . (winwidth(0) * 2/3)<CR>
nnoremap <silent> <leader>> :exe "vertical resize " . (winwidth(0) * 3/2)<CR>
nnoremap <silent> <leader>= :winc =<CR>
nnoremap <silent> <leader>y o<Esc>
inoremap jk <esc>

" Allow saving of files as sudo when I forgot to start vim using sudo.
cnoremap w!! w !sudo tee > /dev/null %

" NERDTree Mappings {{{

nnoremap <leader>n :NERDTreeToggle<cr>

" }}}

" fzf  Mappings {{{

nnoremap <c-b> :Buffers<cr>
nnoremap <c-t> :Files<cr>

" }}}

" Easymotion Mappings {{{
" }}}

" vim:foldmethod=marker:foldlevel=0
