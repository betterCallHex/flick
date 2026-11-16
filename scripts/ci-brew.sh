#!/bin/sh
set -eu

archive=$1
shift
prefix=$(brew --prefix)

if [ -f "$archive" ]; then
  tar -xpf "$archive" -C "$prefix"
  brew link --overwrite "$@" >/dev/null
  exit 0
fi

work=$(mktemp -d)
touch "$work/marker"
(cd "$prefix/Cellar" && ls -d */* | sort) > "$work/before"

brew install "$@"

cd "$prefix"
{
  (cd Cellar && ls -d */* | sort) | comm -13 "$work/before" - | sed 's|^|Cellar/|'
  find opt -type l -newer "$work/marker"
} > "$work/files"
tar -cf "$archive" -T "$work/files"
