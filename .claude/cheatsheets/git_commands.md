# Git Commands Cheatsheet

## Common Operations

### Branching
```bash
git checkout -b feature/new-feature  # Create and switch to new branch
git branch -d branch-name           # Delete local branch
git push origin --delete branch-name # Delete remote branch
```

### Stashing
```bash
git stash                   # Save current changes
git stash pop              # Apply and remove latest stash
git stash list             # List all stashes
git stash apply stash@{2}  # Apply specific stash
```

### Undoing Changes
```bash
git reset --soft HEAD~1    # Undo last commit, keep changes staged
git reset --hard HEAD~1    # Undo last commit, discard changes
git checkout -- file.txt   # Discard changes in file
git revert commit-hash     # Create new commit that undoes changes
```

### Viewing History
```bash
git log --oneline -10              # Last 10 commits, one line each
git log --graph --all --decorate   # Visual branch history
git diff HEAD~1                    # Changes since last commit
git show commit-hash               # Show specific commit
```

### Remote Operations
```bash
git remote -v                      # List remotes
git fetch --all                    # Fetch all branches
git pull --rebase origin main      # Pull with rebase
git push -u origin branch-name     # Push and set upstream
```

## Advanced

### Interactive Rebase
```bash
git rebase -i HEAD~3  # Rewrite last 3 commits
# Commands: pick, reword, edit, squash, fixup, drop
```

### Cherry Pick
```bash
git cherry-pick commit-hash  # Apply specific commit to current branch
```

### Bisect (Find Bad Commit)
```bash
git bisect start
git bisect bad                 # Current version is bad
git bisect good commit-hash    # Known good commit
# Test and mark as good/bad until found
git bisect reset
```