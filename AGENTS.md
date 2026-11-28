# Landing work

The same in every repository. The source is `github/AGENTS.md` in the `dev` repository and Develop's Set Up Repositories workflow copies it; change it there, never here. This repository's own rules are in `CLAUDE.md`; read that too.

- Commit and open a pull request only when the user says to land.
- In Develop, land with the `open_pr` tool: it commits, pushes, opens the pull request and waits for its checks. `gh` and a push of your own don't work from a Develop session's sandbox. Outside Develop (a cloud session), commit on a branch, push it and open the pull request yourself.
- The PR Review checks (`claude` and `codex`) are the gate. Each posts its review as a pull request comment and fails on a Critical or High finding.
- When a check fails, read both review comments, fix every Critical and High finding and push again (in Develop, run `open_pr` again). Every push is reviewed afresh. Dismiss a finding only with the reason stated in a pull request comment. After three rounds, stop and state what is still failing.
- Never push to a default branch, force-push or merge. Develop's run merges when the checks pass; the user merges everything else and decides what is released.
- No Claude or Codex attribution or session links in commit messages or pull requests.
