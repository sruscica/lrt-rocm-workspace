---
name: setup
description: Use when setting up the lrt-rocm workspace for the first time, or when a new team member installs the plugin
---

Set up the ROCm development workspace. This skill discovers the TheRock repository on the filesystem (or clones it), generates a directory map, and scaffolds the workspace structure. Optionally configures rocm-systems for monorepo workflows.

## 1. Check if already set up

Look for `directory-map.md` in the current working directory.
- If it exists and has populated paths, ask: "Workspace already configured. Re-run setup to update paths?"
- If user declines, stop.

## 2. Select operating system

Ask the user which OS they are developing on:

> "Which operating system are you developing on?
> 1. **Linux** (Ubuntu)
> 2. **Windows**"

Auto-detect when possible:
```bash
uname -s 2>/dev/null
```

If detection succeeds, confirm with the user:
> "Detected **Linux**. Is this correct?"

Store the result — it will be written to `directory-map.md` in step 6 and used by OS-specific skills like `lrt-rocm:the-rock`.

## 3. Find TheRock repository

Search for TheRock directories. Check these locations in order:

```bash
# Common locations to search
for dir in /develop /home/$USER /opt /workspace ~/src ~/projects ~/code; do
  find "$dir" -maxdepth 4 -name "TheRock" -type d 2>/dev/null
done
```

### If TheRock is found:

Report the discovered paths and ask user to confirm:
> "Found TheRock at `<path>`. Is this the correct repository?"

If multiple are found, list them and ask which is the primary working copy.

### If TheRock is NOT found:

Ask the user:
> "I couldn't find a TheRock repository on this system. Would you like to:
> 1. Clone it now (I'll need a target directory)
> 2. Provide the path manually
> 3. Skip for now (you can update directory-map.md later)"

If cloning:
```bash
cd <user-chosen-dir>
git clone https://github.com/ROCm/TheRock.git
```

**Note:** TheRock builds happen in-tree (within the TheRock directory). There is no need to configure a separate build directory.

## 4. Find rocm-systems repository (optional)

Ask the user if they also work with rocm-systems directly:
> "Do you also work with the rocm-systems monorepo directly? (This is separate from TheRock — only needed if you build HIP/OCL via the rocm-systems workflow.)"

If yes, search for rocm-systems:

```bash
for dir in /develop /home/$USER /opt /workspace ~/src ~/projects ~/code; do
  find "$dir" -maxdepth 4 -name "rocm-systems" -type d 2>/dev/null
done
```

If found, confirm the path. If not found, offer to clone, provide path manually, or skip.

If the user works with rocm-systems, also ask about build directories:

> "Build directories (relative to rocm-systems root):
> - **CLR build:** `projects/clr/build` — for HIP/OCL runtime builds
> - **hip-tests build:** `projects/hip-tests/build` — for HIP test builds
>
> Accept defaults or provide custom paths?"

If a directory doesn't exist, ask if they want to create it.

If the user does **not** work with rocm-systems, skip build directory setup entirely.

## 5. Detect GPU architecture

```bash
# Try to detect GPU
rocminfo 2>/dev/null | grep "Name:" | head -5
```

If rocminfo is available, show detected GPUs and ask user to confirm the target architecture.
If not available, ask the user to specify their target GPU family (e.g., gfx1201, gfx942, gfx90a).

## 6. Scaffold workspace

Copy template files into the current working directory:

```bash
PLUGIN_ROOT="<path to this plugin>"

# Core files
cp "$PLUGIN_ROOT/templates/CLAUDE.md" ./CLAUDE.md
cp "$PLUGIN_ROOT/templates/ACTIVE-TASKS.md" ./ACTIVE-TASKS.md
cp "$PLUGIN_ROOT/templates/adding-third-party-dep.md" ./adding-third-party-dep.md

# Task management structure
mkdir -p tasks/active tasks/completed
cp "$PLUGIN_ROOT/templates/example-task.md" ./tasks/active/example-task.md
```

## 7. Generate directory-map.md

Using the discovered paths and OS selection, write `directory-map.md` with populated values:

```markdown
# ROCm Directory Map

This document maps out where all ROCm-related directories live on this system.
It is auto-populated by `/lrt-rocm:setup` or can be edited manually.

## Environment

| Setting | Value |
|---------|-------|
| OS | <linux or windows> |

## Repository Aliases

| Alias | Path | Notes |
|-------|------|-------|
| therock | <discovered_therock_path> | Main ROCm build repo |
| workspace | <cwd> | This meta-workspace |
```

If the user also works with rocm-systems, add these rows to the aliases table:

```markdown
| rocm-systems | <discovered_rocm_systems_path> | ROCm Systems Superrepo (submodule) |
```

If additional TheRock or rocm-systems checkouts were discovered, add:

```markdown
## Additional Checkouts

| Path | Notes |
|------|-------|
| <additional_path> | <notes> |
```

Only include the Build Trees section if the user works with rocm-systems:

```markdown
## Build Trees

### Active Builds
- **CLR build:** `<rocm_systems_path>/projects/clr/build`
  - For: HIP and OCL runtime builds
  - Configuration: Release
  - Target architecture: [<detected_gpu>]
  - Built ROCm installation is under `dist/rocm`
- **hip-tests build:** `<rocm_systems_path>/projects/hip-tests/build`
  - For: HIP unit tests and stress tests
  - Configuration: Debug
  - Target architecture: [<detected_gpu>]
```

## 8. Update CLAUDE.md paths

Replace placeholder paths in `CLAUDE.md` with the discovered values:
- `<therock-dir>` with the actual TheRock directory path
- `<your-gpu-family>` with the detected/chosen GPU family

If the user also works with rocm-systems, additionally replace:
- `<clr-build-dir>` with the actual CLR build directory (default: `<rocm_systems_path>/projects/clr/build`)
- `<hip-tests-build-dir>` with the actual hip-tests build directory (default: `<rocm_systems_path>/projects/hip-tests/build`)

## 9. VSCode integration (optional)

Ask: "Do you use VSCode for code review? The plugin includes an MCP extension for opening diffs directly in VSCode."

If yes:
1. Determine VSCode extensions path:
   - Remote: `~/.vscode-server/extensions/`
   - Local: `~/.vscode/extensions/`
2. Symlink the extension:
   ```bash
   ln -s "$PLUGIN_ROOT/vscode-plugins/stella-ide-mcp" <extensions_path>/stella-ide-mcp
   ```
3. Tell user to reload VSCode
4. Configure MCP: `claude mcp add --transport sse vscode http://127.0.0.1:3742/sse`

## 10. Summary

Report what was set up:
- Operating system
- TheRock directory
- rocm-systems path (if configured)
- CLR build directory (if configured)
- hip-tests build directory (if configured)
- Target GPU architecture
- Files created/updated
- VSCode integration status

Say: "Workspace setup complete. Run `/lrt-rocm:setup` again anytime to update paths."
