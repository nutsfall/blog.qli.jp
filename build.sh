#!/usr/bin/env bash

#------------------------------------------------------------------------------
# @file
# Builds a Hugo site hosted on a Cloudflare Worker.
#
# Only Hugo is installed. This site needs nothing else:
#   - Dart Sass — there are no .scss/.sass files in the project or the theme
#   - Go — the theme is a git submodule, not a Hugo Module (no `module:` in hugo.yaml)
#   - Node.js — js.Build uses Hugo's embedded esbuild, and Cloudflare runs
#     wrangler with its own Node.js before this script starts
# See ADR-0014.
#------------------------------------------------------------------------------

main() {

  HUGO_VERSION=0.165.0

  export TZ=Europe/Oslo

  # Install Hugo
  echo "Installing Hugo ${HUGO_VERSION}..."
  curl -fsSL --retry 3 --retry-delay 2 -o hugo.tar.gz \
    "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz"
  mkdir -p "${HOME}/.local/hugo"
  tar -C "${HOME}/.local/hugo" -xf hugo.tar.gz
  rm hugo.tar.gz
  export PATH="${HOME}/.local/hugo:${PATH}"

  # Verify installation
  echo "Verifying installation..."
  echo Hugo: "$(hugo version)"

  # Configure Git
  echo "Configuring Git..."
  git config core.quotepath false
  if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    git fetch --unshallow
  fi

  # Build the site
  echo "Building the site..."
  hugo --gc --minify

}

set -euo pipefail
main "$@"
