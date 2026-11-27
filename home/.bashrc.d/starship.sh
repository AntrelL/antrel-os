# Prompt; hides user@host unless connected over SSH. Fedora's ~/.bashrc sources ~/.bashrc.d/*.
if command -v starship >/dev/null; then
  eval "$(starship init bash)"
fi
