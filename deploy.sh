#!/usr/bin/env bash
#
# deploy.sh - ship the approved local state to GitHub and Vercel together.
#
#   ./deploy.sh "commit message"   commit everything, push, then deploy
#   ./deploy.sh                    tree must already be clean; push + deploy
#
# Git is pushed FIRST. If the push fails, nothing is deployed, so the live
# site can never contain code that is missing from GitHub.

set -euo pipefail

cd "$(dirname "$0")"

BRANCH="main"
DOMAIN="https://redrock435.com"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

fail() { red "FAILED: $*"; exit 1; }

# --- Preflight -------------------------------------------------------------

step "Preflight"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$current_branch" = "$BRANCH" ] || fail "on branch '$current_branch', expected '$BRANCH'"

command -v vercel >/dev/null || fail "vercel CLI not found (brew install vercel)"
vercel whoami >/dev/null 2>&1 || fail "not logged in to Vercel (run: vercel login)"

echo "branch: $current_branch"
echo "vercel: $(vercel whoami 2>/dev/null | tail -1)"

# --- Commit ----------------------------------------------------------------

if [ -n "$(git status --porcelain)" ]; then
  if [ $# -lt 1 ]; then
    red "You have uncommitted changes:"
    git status --short
    echo
    fail "pass a commit message:  ./deploy.sh \"what changed\""
  fi
  step "Committing"
  git add -A
  git commit -q -m "$1"
  git --no-pager log --oneline -1
else
  step "Committing"
  echo "nothing to commit, tree is clean"
  [ $# -ge 1 ] && echo "(ignoring commit message, no changes to commit)"
fi

# --- Push ------------------------------------------------------------------
# Must succeed before anything goes live.

step "Pushing to GitHub"
git push origin "$BRANCH" || fail "git push failed - NOTHING was deployed"
green "pushed $(git rev-parse --short HEAD) to origin/$BRANCH"

# --- Deploy ----------------------------------------------------------------

step "Deploying to Vercel"
if ! vercel --prod --yes; then
  red "Vercel deploy failed, but the commit IS on GitHub."
  fail "re-run ./deploy.sh once the Vercel issue is resolved"
fi

# --- Verify ----------------------------------------------------------------

step "Verifying live site"
sleep 3
all_ok=1
for path in "" /about /services /contact; do
  code="$(curl -sL -o /dev/null -w '%{http_code}' "${DOMAIN}${path}" || echo 000)"
  printf '  %-40s %s\n' "${DOMAIN}${path}" "$code"
  [ "$code" = "200" ] || all_ok=0
done

echo
if [ "$all_ok" = "1" ]; then
  green "Done. Local, GitHub, and $DOMAIN are all in sync."
else
  red "Deploy finished but some pages did not return 200 - check the site."
  exit 1
fi
