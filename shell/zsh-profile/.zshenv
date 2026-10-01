# zsh-profile's stand-in .zshenv. `zsh-profile` points ZDOTDIR here so zprof
# is loaded before any of the user's own startup files run. It then puts
# ZDOTDIR back and hands over to the real .zshenv; zsh reads the rest
# (.zprofile, .zshrc, .zlogin) from the restored ZDOTDIR as usual.

zmodload zsh/zprof

if [[ -n ${_ZSH_PROFILE_ZDOTDIR+set} ]]; then
  ZDOTDIR=$_ZSH_PROFILE_ZDOTDIR
else
  unset ZDOTDIR
fi
unset _ZSH_PROFILE_ZDOTDIR

if [[ -r ${ZDOTDIR:-$HOME}/.zshenv ]]; then
  source "${ZDOTDIR:-$HOME}/.zshenv"
fi
