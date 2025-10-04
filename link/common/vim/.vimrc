" David Nguyen's .vimrc

" General Vim Settings {{{

set nocompatible " turn off vi compatibility
set cursorline " highlight current line
set tabstop=2 " number of visual spaces per TAB
set softtabstop=2 " number of spaces in tab when editing
set shiftwidth=2 " number of spaces when indenting with '>'
set expandtab " tabs are spaces
set wildmenu " visual autocomplete for command menu
set lazyredraw " redraw only when we need
set showmatch " highlight matching [{()}]
set incsearch " search as characters are entered
set hlsearch " highlight matches
set modelines=1 " enable modeline at the bottom of the file
set hidden " hide current unsaved buffer when opening a new file instead of closing it
set backspace=indent,eol,start
set number relativenumber " show relative line number by default
set clipboard=unnamed " yank to clipboard
set showcmd " show incomplete command
set autoindent " copy indent from current line when starting a new line
set smartindent " indent based on code syntax
set nowrap " not wrap lines
set linebreak " wrap lines at convenient points
set encoding=utf-8 " to fix NERDTree rendering issue in ubuntu
set backupdir=~/.vim/tmp/backup// " set custom location for backup files
set directory=~/.vim/tmp/swap// " set custom location for swap files
set undodir=~/.vim/tmp/undo// " set custom location for undo files
set ignorecase
set smartcase " smart case insensitive search
set mouse=a " enable mouse for scrolling and resizing
set scrolloff=1 " always keep 1 line above and below the cursor for context
set background=dark

set complete-=i " disable scanning included files for keyword completion

" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright

" make jumplist behaves like a stack
set jumpoptions=stack

" Highlight yanked text for a brief period, compatible with some themes that use `HighlightedyankRegion`
autocmd TextYankPost * silent! lua vim.highlight.on_yank {higroup=(vim.fn['hlexists']('HighlightedyankRegion') > 0 and 'HighlightedyankRegion' or 'IncSearch'), timeout=500}

" Folding Settings  {{{

set foldenable " enable folding
set foldlevelstart=10 " open most folds by default
set foldnestmax=10 " 10 nested fold max
set foldmethod=syntax " fold based on filetype syntax
let javaScript_fold=1
let xml_syntax_folding=1

" }}}

augroup numbertoggle
    " set absolute line number in insert mode, hybrid line number otherwise
    autocmd!
    autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
    autocmd BufLeave,FocusLost,InsertEnter * set norelativenumber
augroup end

filetype plugin indent on " load filetype-specific indent files at ~/.vim/indent/*.vim
autocmd FileType cs setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab " use 4 spaces indentation for C# files

syntax on

" }}}

" NeoVim Settings {{{

if has('nvim')
  " force neovim terminal to use zsh available in PATH instead of /bin/zsh
  execute "set shell=". system('which zsh')
endif

" }}}

" VimPlug {{{
call plug#begin('~/.vim/plugged')

function! Cond(cond, ...)
  let opts = get(a:000, 0, {})
  return a:cond ? opts : extend(opts, { 'on': [], 'for': [] })
endfunction

Plug 'tpope/vim-repeat'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-unimpaired'
Plug 'kana/vim-textobj-user'
Plug 'rhysd/vim-textobj-anyblock'
Plug 'michaeljsmith/vim-indent-object'
Plug 'mileszs/ack.vim'
Plug 'morhetz/gruvbox'
Plug 'scrooloose/nerdtree', Cond(!exists('g:vscode'), { 'on':  'NERDTreeToggle' })
Plug 'vim-airline/vim-airline', Cond(!exists('g:vscode'))
Plug 'christoomey/vim-tmux-navigator', Cond(!exists('g:vscode'))
Plug 'junegunn/vim-peekaboo', Cond(!exists('g:vscode'))
Plug 'mhinz/vim-signify', Cond(!exists('g:vscode'))
Plug 'osyo-manga/vim-over', Cond(!exists('g:vscode'))
Plug 'google/vim-searchindex', Cond(!exists('g:vscode'))
Plug 'jiangmiao/auto-pairs', Cond(!exists('g:vscode'))
Plug 'ludovicchabant/vim-gutentags', Cond(!exists('g:vscode'))
Plug 'vim-scripts/argtextobj.vim'

if has('nvim')
  Plug 'nvim-lua/plenary.nvim'
  Plug 'nvim-telescope/telescope.nvim', { 'tag': '0.1.8' }
endif

call plug#end()
" }}}

" Theme Settings  {{{

" gruvbox is provided by plugin so this line needs to be after VimPlug settings
colorscheme gruvbox

" }}}

" Custom Keybindings {{{

source ~/.keybindings.vim

" }}}

" Custom Functions {{{

" custom function to rename current file
function! RenameFile()
  let old_name = expand('%')
  let new_name = input('New file name: ', expand('%'), 'file')
  if new_name != '' && new_name != old_name
    exec ':saveas ' . new_name
    exec ':silent !rm ' . old_name
    redraw!
  endif
endfunction

map <leader>n :call RenameFile()<cr>

" allow running a macro on a visual selection of a section
function! ExecuteMacroOverVisualRange()
  echo "@".getcmdline()
  execute ":'<,'>normal @".nr2char(getchar())
endfunction

xnoremap @ :<C-u>call ExecuteMacroOverVisualRange()<CR>

" Check if NERDTree is open or active
function! IsNERDTreeOpen()
  return exists("t:NERDTreeBufName") && (bufwinnr(t:NERDTreeBufName) != -1)
endfunction

" Call NERDTreeFind iff NERDTree is active, current window contains a modifiable
" file, and we're not in vimdiff
function! SyncTree()
  if &modifiable && IsNERDTreeOpen() && strlen(expand('%')) > 0 && !&diff
    NERDTreeFind
    wincmd p
  endif
endfunction

nnoremap <leader>/ :call SyncTree()<CR>

" }}}

" Autocommands {{{

" automatically mark a buffer using mO whenever leaving a buffer
" so that we can always come back with `O
function! MarkBuf()
    if bufname('') !~ 'fzf'
      normal! mO
    endif
endfunction

augroup bufmark
  autocmd!
  autocmd BufLeave * call MarkBuf()
augroup end

" }}}

" airline Settings {{{

let g:airline#extensions#tabline#enabled = 1
" airline uses `0x2632` character (wide character) to show trailing whitespaces, which NeoVim 0.10.* doesn't handle well
" change to use other character to temporarily work around the issue
" once https://github.com/neovim/neovim/issues/31956 is fixed and merged, this can be removed
let g:airline#extensions#whitespace#symbol = '!'

" }}}

" fzf Settings {{{

if executable('rg')
  " Use rg over Grep
  set grepprg=rg\ --vimgrep
endif

" }}}

" Ack.Vim Settings {{{

let g:ackprg = 'rg --vimgrep --no-heading'

" }}}

" NERDTree Settings {{{

let NERDTreeShowHidden=1
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

" }}}

" DirDiff Settings {{{

" Sets the diff window (bottom window) height (rows)
let g:DirDiffWindowSize = 5

" }}}

" telescope Settings {{{
"
nnoremap <leader>ff <cmd>Telescope find_files<cr>
nnoremap <leader>fg <cmd>Telescope live_grep<cr>
nnoremap <leader>fb <cmd>Telescope buffers<cr>
nnoremap <leader>fh <cmd>Telescope help_tags<cr>

" }}}

" vim:foldmethod=marker:foldlevel=0
