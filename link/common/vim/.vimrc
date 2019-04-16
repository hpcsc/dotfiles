" David Nguyen's .vimrc

" Vim Settings {{{

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

" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright

color slate


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

" Diff Settings  {{{

" change highlight background color when using vimdiff as git difftool
highlight DiffChange   cterm=bold   gui=none    ctermfg=NONE          ctermbg=60
highlight DiffText   cterm=bold   gui=none    ctermfg=NONE          ctermbg=52
highlight DiffDelete   cterm=bold   gui=none    ctermfg=NONE          ctermbg=89
highlight DiffAdd   cterm=bold    gui=none    ctermfg=NONE          ctermbg=49

" }}}

" }}}

" NeoVim Settings {{{

if has('nvim')
  " force neovim terminal to use zsh available in PATH instead of /bin/zsh
  execute "set shell=". system('which zsh')
endif

" }}}

" VimPlug {{{
call plug#begin('~/.vim/plugged')

Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
Plug 'vim-airline/vim-airline'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'mileszs/ack.vim'
Plug 'tpope/vim-unimpaired'
Plug 'christoomey/vim-tmux-navigator'
Plug 'SirVer/ultisnips'
Plug 'will133/vim-dirdiff'
Plug 'junegunn/vim-peekaboo'
Plug 'mhinz/vim-signify'
Plug 'osyo-manga/vim-over'
Plug 'google/vim-searchindex'
Plug 'jiangmiao/auto-pairs'
Plug 'kana/vim-textobj-user'
Plug 'rhysd/vim-textobj-anyblock'
Plug 'michaeljsmith/vim-indent-object'
Plug 'ludovicchabant/vim-gutentags'

if has('nvim')
  Plug 'autozimu/LanguageClient-neovim', { 'branch': 'next', 'do': 'bash install.sh' }
  Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
endif

call plug#end()
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

" }}}

" airline Settings {{{

let g:airline#extensions#tabline#enabled = 1

" }}}
"
" fzf Settings {{{

if executable('rg')
  " Use rg over Grep
  set grepprg=rg\ --vimgrep
endif

" }}}

" Ack.Vim Settings {{{

let g:ackprg = 'rg --vimgrep --no-heading'

" }}}

" LanguageClient Settings {{{

let g:deoplete#enable_at_startup = 1
let g:LanguageClient_serverCommands = {
    \ 'haskell': ['hie', '--lsp'],
    \ 'rust': ['~/.cargo/bin/rustup', 'run', 'stable', 'rls'],
    \ }

nnoremap <F5> :call LanguageClient_contextMenu()<CR>

" }}}

" NERDTree Settings {{{

let NERDTreeShowHidden=1
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

" }}}

" Ultisnips Settings {{{

let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-n>"
let g:UltiSnipsJumpBackwardTrigger="<c-p>"
let g:UltiSnipsSnippetDir="~/.vim/UltiSnips"
let g:UltiSnipsSnippetDirectories=["~/.vim/UltiSnips", "UltiSnips"]

" }}}

" DirDiff Settings {{{

" Sets the diff window (bottom window) height (rows)
let g:DirDiffWindowSize = 5

" }}}

" vim-gutentags Settings {{{

" Enable displaying status of gutentags in vim-airline
let g:airline#extensions#gutentags#enabled = 1

" Cache directory to store all tags files created by vim-gutentags for universal-ctags
let g:gutentags_cache_dir="~/.ctags_cache"

" }}}

" vim:foldmethod=marker:foldlevel=0
