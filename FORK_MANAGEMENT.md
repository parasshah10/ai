# Fork Management & Update Workflow

This document outlines the standard process for keeping this customized fork in sync with the official [OpenWebUI](https://github.com/open-webui/open-webui) repository.

## The Architecture
1.  **`dev` Branch:** A clean, untouched mirror of `upstream/dev`. **Never** commit directly to this branch.
2.  **`my-changes` Branch:** Where all customizations live. This branch is always rebased on top of `dev`.
3.  **`upstream` Remote:** Points to `https://github.com/open-webui/open-webui.git`.

## The Sync Workflow (Run this when OpenWebUI updates)

### Step 1: Update the Mirror
Reset your local `dev` to match the official latest code.
```bash
git checkout dev
git fetch upstream
git reset --hard upstream/dev
```

### Step 2: Rebase Customizations
Move your work on top of the new version.
```bash
git checkout my-changes
git rebase dev
```

### Step 3: Conflict Resolution
If conflicts occur, resolve them file-by-file. Since customizations are squashed into a single commit, each conflict only needs to be solved once. Use the following guidelines:
*   **Backend:** Always adopt `async` changes and new dependency versions. Re-insert MeiliSearch hooks in lifecycle methods.
*   **Frontend:** Preserve custom props (like `role` or `messageId`) and high-performance rendering logic.
*   **Logic:** Combine custom features (Cloudinary, Minimap) with new upstream security/stability fixes.

### Step 4: Finalize
Once conflicts are resolved:
```bash
git add <resolved-files>
git rebase --continue
```

## Key Rules
1.  **Squash Frequently:** Keep your customizations in a single (or very few) commits to make rebasing painless.
2.  **Rerere:** Ensure `git config --global rerere.enabled true` is on so Git remembers your conflict resolutions.
3.  **Backup:** Always create a `backup-before-update` branch before starting a rebase.
