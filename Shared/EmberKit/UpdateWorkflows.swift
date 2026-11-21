import Foundation

/**
 * Ember's Update Ember workflows, as the web bundles them (apps/worker/scripts/update-ember.yml and
 * update-ember-beta.yml at 479e3bf9), which the release card's Add GitHub action links fill in on GitHub.
 */
public enum UpdateWorkflows {
  public static let workflowFile = ".github/workflows/update-ember.yml"
  public static let betaWorkflowFile = ".github/workflows/update-ember-beta.yml"

  /** GitHub's editor for a new workflow file on the copy's branch, filled in to commit (`newFileLinkOf`). */
  public static func newFileLink(_ copy: CopyOnGitHub, beta: Bool) -> String {
    let branch = copy.branch.split(separator: "/", omittingEmptySubsequences: false).map { URIComponent.encode(String($0)) }.joined(separator: "/")
    let query = [("filename", beta ? betaWorkflowFile : workflowFile), ("value", beta ? betaWorkflow : workflow)]
      .map { "\(formEncoded($0.0))=\(formEncoded($0.1))" }.joined(separator: "&")
    return "https://github.com/\(copy.repository)/new/\(branch)?\(query)"
  }

  /** `URLSearchParams`' encoding: spaces as +, and only `*-._` and alphanumerics left as they are. */
  static func formEncoded(_ text: String) -> String {
    let kept = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._ ")
    guard let encoded = text.addingPercentEncoding(withAllowedCharacters: kept) else { preconditionFailure("Unencodable text") }
    return encoded.replacingOccurrences(of: " ", with: "+")
  }

  public static let workflow = #"""
name: Update Ember

# Brings this copy of Ember up to Ember's newest release, from github.com/NYLLON-SOFTWARE/ember-cloudflare:
# once a week, and whenever it's run from the Actions tab, it opens a pull request with the update,
# and merging that deploys it (docs/self-hosting.md#updating). apps/worker/scripts/update-ember.ts does
# the work, so updates bring changes to how it works; this file stays as the copy has it, since a
# workflow can't change workflows. A new repository doesn't let workflows open pull requests until its
# Settings, under Actions, General, allow it, so until then it opens an issue that links to the pull
# request, for whoever reads it to open in a click. It brings releases alone, unless it's run with
# Take Ember's newest beta ticked, or the copy runs a beta already (docs/self-hosting.md#betas).
on:
  schedule:
    - cron: "23 14 * * 1"
  workflow_dispatch:
    inputs:
      beta:
        description: Take Ember's newest beta, where one is newer than its newest release
        type: boolean
        default: false

# To push the update's branch and open its pull request, or the issue, and close those it replaces.
permissions:
  contents: write
  pull-requests: write
  issues: write

concurrency:
  group: update-ember
  cancel-in-progress: false

jobs:
  update:
    # Ember's own repository is where the releases come from, so it has nothing to update.
    if: github.repository != 'NYLLON-SOFTWARE/ember-cloudflare'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      # Pinned to commits, not tags, because this job can push to the repository: a moved tag can't
      # change what runs. These are the commits the tags beside them pointed at.
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
        with:
          # All of it: the copy's first commit and its updates' say which of Ember's it has.
          fetch-depth: 0
      - uses: actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38 # v6
        with:
          node-version: 22
      - name: Update
        env:
          GH_TOKEN: ${{ github.token }}
          # Whether the box for a beta was ticked, which a weekly run leaves blank.
          EMBER_BETA: ${{ inputs.beta }}
          GIT_AUTHOR_NAME: github-actions[bot]
          GIT_AUTHOR_EMAIL: 41898282+github-actions[bot]@users.noreply.github.com
          GIT_COMMITTER_NAME: github-actions[bot]
          GIT_COMMITTER_EMAIL: 41898282+github-actions[bot]@users.noreply.github.com
        run: node apps/worker/scripts/update-ember.ts --publish

"""#

  public static let betaWorkflow = #"""
name: Update Ember to its newest beta

# Brings this copy of Ember up to Ember's newest beta, from github.com/NYLLON-SOFTWARE/ember-cloudflare,
# whenever it's run from the Actions tab: it opens a pull request with the beta, and merging that deploys
# it (docs/self-hosting.md#betas). It runs the update script from Ember's newest release or beta rather
# than the copy's own, which can't see betas in copies from before them. Update Ember goes on bringing
# releases alone until the copy runs a beta, then brings the betas after it, then the release, and after
# that releases alone again.
on:
  workflow_dispatch:

# To push the update's branch and open its pull request, or the issue, and close those it replaces.
permissions:
  contents: write
  pull-requests: write
  issues: write

# Update Ember's group, since the two push the same branches, so they never run at once.
concurrency:
  group: update-ember
  cancel-in-progress: false

jobs:
  update:
    # Ember's own repository is where the betas come from, so it has nothing to update.
    if: github.repository != 'NYLLON-SOFTWARE/ember-cloudflare'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      # Pinned to commits, not tags, because this job can push to the repository: a moved tag can't
      # change what runs. These are the commits the tags beside them pointed at.
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
        with:
          # All of it: the copy's first commit and its updates' say which of Ember's it has.
          fetch-depth: 0
      - uses: actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38 # v6
        with:
          node-version: 22
      - name: Fetch Ember's newest update script
        run: |
          ember=https://github.com/NYLLON-SOFTWARE/ember-cloudflare.git
          # Ember's newest tag, a release's or a beta's, with each beta sorted before its release.
          tag=$(git -c versionsort.suffix=- ls-remote --tags --refs --sort=-version:refname "$ember" 'v*' | head -n 1 | sed 's|.*refs/tags/||')
          git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" --filter=blob:none --sparse "$ember" "$RUNNER_TEMP/ember"
          git -C "$RUNNER_TEMP/ember" sparse-checkout set apps/worker/scripts
      - name: Update
        env:
          GH_TOKEN: ${{ github.token }}
          GIT_AUTHOR_NAME: github-actions[bot]
          GIT_AUTHOR_EMAIL: 41898282+github-actions[bot]@users.noreply.github.com
          GIT_COMMITTER_NAME: github-actions[bot]
          GIT_COMMITTER_EMAIL: 41898282+github-actions[bot]@users.noreply.github.com
        run: node "$RUNNER_TEMP/ember/apps/worker/scripts/update-ember.ts" --publish --beta

"""#
}
