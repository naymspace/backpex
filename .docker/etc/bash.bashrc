if test -d /etc/bashrc.d; then
  for script in /etc/bashrc.d/*.sh; do
    test -r "$script" && . "$script"
  done
  unset item
fi
