# Landing work

The same in every repository. The source is `AGENTS.md` in the `dev` repository and Develop's Update PR Review workflow copies it; change it there, never here. This repository's own rules are in `CLAUDE.md`; read that too.

- Commit and open a pull request only when the user says to land.
- In Develop, land with the `open_pr` tool: it commits, pushes, opens the pull request and waits for its checks. `gh` and a push of your own don't work from a Develop session's sandbox. Outside Develop (a cloud session), commit on a branch, push it and open the pull request yourself.
- The PR Review checks (`review / claude` and `review / codex`) are the gate. Each posts its review as a pull request comment and fails on a Critical finding, or a High one that is likely and that untrusted input can trigger.
- When a check fails, read both review comments, fix every finding that failed the check and push again (in Develop, run `open_pr` again). Every push is reviewed afresh, and the reviewers read the pull request's comments. Leave a finding unfixed only with the reason stated in a pull request comment; where the fix is small, fix it instead. Keep going while each round fixes what failed. Stop and state what is failing only when a finding fails the check again after it was fixed or answered.
- Never push to a default branch, force-push or merge. Develop's run merges when the checks pass; the user merges everything else and decides what is released.
- No Claude or Codex attribution or session links in commit messages or pull requests.
