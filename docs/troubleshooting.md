# Machine Rites Troubleshooting Guide

## Quick Diagnosis

### Health Check First

Always start with the health check:

```bash
make doctor
```

This will identify most common issues. Look for red ❌ indicators and follow the specific guidance below.

### Common Symptoms and Solutions

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| SSH keys not loaded | Agent not running | `rm ~/.local/state/ssh/agent.env && exec bash -l` |
| Environment vars missing | Secrets not loaded | `source ~/.bashrc.d/30-secrets.sh` |
| Command not found | PATH issues | `exec bash -l` |
| Permission denied | File permissions | `chmod +x script.sh` |
| GPG errors | No GPG key | `make gpg-setup` |
| Chezmoi conflicts | Dirty state | `chezmoi status && chezmoi diff` |

## Detailed Troubleshooting

### SSH Agent Issues

#### Problem: Multiple SSH Agents

**Symptoms:**
```bash
$ ps aux | grep ssh-agent
user  1234  ssh-agent
user  5678  ssh-agent
user  9012  ssh-agent  # Multiple agents!
```

**Solution:**
```bash
# Kill all agents
pkill ssh-agent

# Remove state file
rm -f ~/.local/state/ssh/agent.env

# Restart shell
exec bash -l

# Verify single agent
ps aux | grep ssh-agent  # Should show only one
ssh-add -l              # Should show your keys
```

#### Problem: SSH Keys Not Persisting

**Symptoms:**
```bash
$ ssh-add -l
The agent has no identities loaded.
```

**Solution:**
```bash
# Check if keys exist
ls -la ~/.ssh/id_*

# If no keys, generate them
make ssh-setup

# Add keys manually
ssh-add ~/.ssh/id_ed25519
ssh-add ~/.ssh/id_rsa

# Verify persistence
exec bash -l
ssh-add -l  # Keys should still be there
```

#### Problem: SSH Agent Not Starting

**Symptoms:**
```bash
$ ssh-add -l
Could not open a connection to your authentication agent.
```

**Solution:**
```bash
# Check if ssh-agent is available
which ssh-agent

# Check SSH module
source ~/.bashrc.d/35-ssh.sh

# Manual start for debugging
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Fix persistent start
rm -f ~/.local/state/ssh/agent.env
exec bash -l
```

### GPG and Pass Issues

#### Problem: No GPG Keys

**Symptoms:**
```bash
$ gpg --list-secret-keys
gpg: keyring '/home/user/.gnupg/secring.gpg' created
# No output
```

**Solution:**
```bash
# Generate new key
make gpg-setup

# Or manually
gpg --full-generate-key
# Choose: RSA and RSA, 4096 bits, no expiration
# Enter real name and email

# Verify
gpg --list-secret-keys
```

#### Problem: Pass Store Not Initialized

**Symptoms:**
```bash
$ pass ls
Error: password store is empty. Try "pass init".
```

**Solution:**
```bash
# Get your GPG key ID
GPG_KEY=$(gpg --list-secret-keys --keyid-format LONG | grep sec | awk '{print $2}' | cut -d'/' -f2 | head -1)

# Initialize pass
pass init "$GPG_KEY"

# Verify
pass ls
```

#### Problem: GPG Agent Not Running

**Symptoms:**
```bash
$ pass show test
gpg: can't connect to the agent: No such file or directory
```

**Solution:**
```bash
# Start GPG agent
gpg-agent --daemon

# Or restart
gpg-connect-agent reloadagent /bye

# Test
echo "test" | gpg --encrypt -r your-email@domain.com
```

#### Problem: Pass Migration Failed

**Symptoms:**
```bash
$ source ~/.bashrc.d/30-secrets.sh
Error: Failed to migrate secrets from ~/.config/secrets.env
```

**Solution:**
```bash
# Check source file
cat ~/.config/secrets.env

# Manual migration
while IFS='=' read -r key value; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue  # Skip comments
    [[ -z "$key" ]] && continue                 # Skip empty lines
    echo "$value" | pass insert -m "personal/${key,,}"
done < ~/.config/secrets.env

# Verify migration
pass ls
```

### Chezmoi Issues

#### Problem: Pending Changes

**Symptoms:**
```bash
$ chezmoi status
A .bashrc
M .bashrc.d/40-tools.sh
```

**Solution:**
```bash
# See exact differences
chezmoi diff

# If changes look good, apply them
chezmoi apply

# If you want to keep current versions
chezmoi forget ~/.bashrc
chezmoi add ~/.bashrc
```

#### Problem: Template Errors

**Symptoms:**
```bash
$ chezmoi apply
template: .bashrc:5:2: executing ".bashrc" at <.email>: map has no entry for key "email"
```

**Solution:**
```bash
# Check chezmoi data
chezmoi data

# Fix missing data in chezmoi.toml
$EDITOR ~/.config/chezmoi/chezmoi.toml

# Example fix:
cat >> ~/.config/chezmoi/chezmoi.toml <<EOF
[data]
  email = "your-email@domain.com"
  name = "Your Name"
EOF

# Try again
chezmoi apply
```

#### Problem: Source Directory Issues

**Symptoms:**
```bash
$ chezmoi status
chezmoi: ~/git/machine-rites/.chezmoi: not a directory
```

**Solution:**
```bash
# Re-initialize
cd ~/git/machine-rites
chezmoi init --apply .

# Or fix source directory
chezmoi init ~/git/machine-rites
```

### Environment and PATH Issues

#### Problem: Command Not Found

**Symptoms:**
```bash
$ nvm
bash: nvm: command not found
```

**Solution:**
```bash
# Check if tool module loaded
source ~/.bashrc.d/40-tools.sh

# Check PATH
echo $PATH | tr ':' '\n' | grep -E "(nvm|node)"

# Reload shell
exec bash -l

# Check specific tool
ls -la ~/.local/share/nvm/
```

#### Problem: Environment Variables Missing

**Symptoms:**
```bash
$ echo $GITHUB_TOKEN
# Empty output
```

**Solution:**
```bash
# Check if secrets loaded
source ~/.bashrc.d/30-secrets.sh

# Check pass store
pass ls

# Re-export variables
pass_env

# Check again
env | grep GITHUB_TOKEN
```

#### Problem: PATH Pollution

**Symptoms:**
```bash
$ echo $PATH
/usr/local/bin:/usr/bin:/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/bin...
```

**Solution:**
```bash
# Clean start
export PATH="/usr/local/bin:/usr/bin:/bin"

# Source hygiene module only
source ~/.bashrc.d/00-hygiene.sh

# Check clean PATH
echo $PATH

# If still polluted, check for duplicates in modules
grep -n "PATH.*=" ~/.bashrc.d/*.sh
```

### Performance Issues

#### Problem: Slow Shell Startup

**Symptoms:**
```bash
$ time bash -lc 'echo hello'
real    0m5.432s  # Too slow!
```

**Solution:**
```bash
# Profile startup
bash -x -l 2>&1 | head -50

# Check expensive operations
grep -n "command.*-v" ~/.bashrc.d/*.sh

# Optimize tool loading
# Move expensive checks to lazy functions
nvm() {
    unset nvm
    source ~/.local/share/nvm/nvm.sh
    nvm "$@"
}
```

#### Problem: High Memory Usage

**Symptoms:**
```bash
$ ps aux | grep bash
user  1234  5.2  1.2  bash  # High memory
```

**Solution:**
```bash
# Check for memory leaks
unset large_arrays
unalias expensive_aliases

# Restart shell
exec bash -l

# Check modules for large variables
grep -n "declare.*array" ~/.bashrc.d/*.sh
```

### Network and Connectivity

#### Problem: GitHub Access Issues

**Symptoms:**
```bash
$ git push
git@github.com: Permission denied (publickey).
```

**Solution:**
```bash
# Check SSH connection
ssh -T git@github.com

# Check SSH key
ssh-add -l

# Test with specific key
ssh -i ~/.ssh/id_ed25519 -T git@github.com

# Add key to GitHub if needed
cat ~/.ssh/id_ed25519.pub
```

#### Problem: Package Manager Issues

**Symptoms:**
```bash
$ make update
Error: Unable to fetch package lists
```

**Solution:**
```bash
# Check network connectivity
ping -c 3 google.com

# Update package lists
sudo apt update

# Check for proxy issues
echo $http_proxy $https_proxy

# Clear proxy if needed
unset http_proxy https_proxy
```

### Bootstrap Issues

#### Problem: Bootstrap Fails Midway

**Symptoms:**
```bash
$ ./bootstrap_machine_rites.sh
Installing chezmoi...
Error: Failed to install chezmoi
```

**Solution:**
```bash
# Run with verbose output
./bootstrap_machine_rites.sh --verbose

# Check specific component
chezmoi --version

# Manual install if needed
curl -fsLS https://git.io/chezmoi | sh

# Resume bootstrap
./bootstrap_machine_rites.sh --skip-backup
```

#### Problem: Permission Errors

**Symptoms:**
```bash
$ ./bootstrap_machine_rites.sh
mkdir: cannot create directory '/root/.config': Permission denied
```

**Solution:**
```bash
# Don't run as root
whoami  # Should NOT be root

# If accidentally run as root, fix ownership
sudo chown -R $USER:$USER ~/.config ~/.local

# Run as regular user
./bootstrap_machine_rites.sh
```

#### Problem: Existing Dotfiles Conflict

**Symptoms:**
```bash
$ ./bootstrap_machine_rites.sh
Error: ~/.bashrc already exists and differs from template
```

**Solution:**
```bash
# Backup existing files manually
cp ~/.bashrc ~/.bashrc.backup.$(date +%Y%m%d)

# Run bootstrap
./bootstrap_machine_rites.sh

# Merge any custom settings from backup
$EDITOR ~/.bashrc.d/99-local.sh
```

## Advanced Debugging

### Shell Debugging

```bash
# Debug specific module
bash -x ~/.bashrc.d/35-ssh.sh

# Debug function
set -x
my_function
set +x

# Debug with timestamps
PS4='+ $(date "+%H:%M:%S"): ' bash -x script.sh
```

### Chezmoi Debugging

```bash
# Verbose output
chezmoi apply --verbose

# Dry run
chezmoi apply --dry-run

# Debug templates
chezmoi execute-template < template.tmpl

# Debug data
chezmoi data
```

### SSH Debugging

```bash
# Verbose SSH connection
ssh -vvv git@github.com

# Debug agent communication
SSH_AUTH_SOCK=/path/to/agent ssh-add -l

# Test key loading
ssh-add -t 3600 ~/.ssh/id_ed25519  # 1 hour timeout
```

### GPG Debugging

```bash
# Verbose GPG operations
gpg --verbose --decrypt file.gpg

# Debug agent
gpg-connect-agent 'keyinfo --list' /bye

# Check configuration
gpg --version
cat ~/.gnupg/gpg.conf
```

## Recovery Procedures

### Full System Recovery

If everything is broken:

```bash
# 1. Reset shell to defaults
mv ~/.bashrc ~/.bashrc.broken
cp /etc/skel/.bashrc ~/.bashrc

# 2. Clean start
exec bash -l

# 3. Re-bootstrap
cd ~/git/machine-rites
./bootstrap_machine_rites.sh --force
```

### Selective Recovery

For specific component issues:

```bash
# Reset SSH only
rm -rf ~/.local/state/ssh/
source ~/.bashrc.d/35-ssh.sh

# Reset secrets only
pass git reset --hard HEAD
source ~/.bashrc.d/30-secrets.sh

# Reset chezmoi only
chezmoi init --force ~/git/machine-rites
```

### Backup Recovery

Use timestamped backups:

```bash
# List available backups
ls -dt ~/dotfiles-backup-* | head -5

# Restore from backup
~/dotfiles-backup-20240315-142030/rollback.sh

# Verify restoration
make doctor
```

## Getting Additional Help

### Log Collection

Before asking for help, collect logs:

```bash
# System info
make doctor > system-health.log

# Shell startup trace
bash -x -l > startup-trace.log 2>&1

# Chezmoi status
chezmoi status > chezmoi-status.log
chezmoi diff > chezmoi-diff.log

# Tool versions
make check-versions > versions.log
```

### Minimal Reproduction

Create a minimal test case:

```bash
# Fresh user account
sudo adduser testuser
sudo su - testuser

# Clone and test
git clone https://github.com/williamzujkowski/machine-rites.git
cd machine-rites
./bootstrap_machine_rites.sh --verbose
```

### Support Channels

1. **GitHub Issues**: For bugs and feature requests
2. **Discussions**: For questions and community help
3. **Documentation**: Check all files in `docs/`
4. **Health Check**: Always run `make doctor` first

### Contributing Fixes

If you find and fix an issue:

1. Document the problem and solution
2. Add to this troubleshooting guide
3. Submit a pull request
4. Help others with similar issues

---

**Remember**: Most issues can be resolved by:
1. Running `make doctor`
2. Checking file permissions
3. Reloading the shell with `exec bash -l`
4. Reading the verbose output carefully