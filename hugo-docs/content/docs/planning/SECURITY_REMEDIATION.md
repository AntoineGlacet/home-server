---
title: "Security Remediation: Discord Webhook Leak"
weight: 3
description: "Security remediation tasks for Discord webhook leak incident"
---

**Date**: 2026-01-19
**Issue**: Discord webhook URL was committed to public GitHub repository
**Status**: ✅ RESOLVED

---

## What Was Done

### 1. Files Cleaned
- **NEXT_STEPS.md**: Replaced hardcoded webhook URL with `${DISCORD_WEBHOOK_URL}` variable reference
- **.env**: Replaced actual webhook URL with placeholder `YOUR_DISCORD_WEBHOOK_URL_HERE`

### 2. Git History Rewritten
Used `git-filter-repo` to rewrite entire git history and remove all occurrences of the exposed webhook URL:
- Processed 118 commits
- Replaced webhook ID/token: `1461590139049607252/zRIDDC0h...` with placeholder
- Force pushed cleaned history to all branches on GitHub

### 3. Security Measures Added
Created `.git/hooks/pre-commit` hook that:
- Blocks commits containing `.env` file
- Detects Discord webhook URLs in staged files
- Warns about hardcoded DISCORD_WEBHOOK_URL values
- Can be bypassed with `--no-verify` flag (not recommended)

### 4. Backup Created
Full repository backup saved at: `/home/antoine/home-server-backup-20260119-163223`

---

## Next Steps Required

### CRITICAL: Revoke the Exposed Webhook
1. Go to Discord server settings
2. Navigate to Integrations → Webhooks
3. Find the webhook with ID `1461590139049607252`
4. Delete or regenerate the webhook URL
5. Update `.env` file with new webhook URL

### Update Local .env File
```bash
cd ~/home-server
nano .env
# Update DISCORD_WEBHOOK_URL with your new webhook URL
```

### Restart Grafana
After updating .env:
```bash
docker-compose down grafana
docker-compose up -d grafana
```

### Test the New Webhook
```bash
# Test directly
curl -X POST "${DISCORD_WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d '{"content": "Test from command line"}'

# Test in Grafana UI
# Go to Alerting → Contact points → Test
```

---

## What Was Protected

### Files That Were Hardcoded (Now Fixed)
- `NEXT_STEPS.md:70` - Troubleshooting curl command
- `.env:127` - Environment variable value

### Files That Were Already Correct
- `config/grafana/provisioning/alerting/contactpoints.yml` - Uses `${DISCORD_WEBHOOK_URL}` variable
- `.env.example` - Contains placeholder values
- `DEPLOYMENT_CHECKLIST.md` - Contains placeholder values

### Git History
All 118 commits were rewritten to remove the webhook URL. The following commits originally contained the webhook:
- `74bfb55` → `54c17e3`: "Migrate alerting from Prometheus Alertmanager to Grafana unified alerting"
- Multiple other commits were also cleaned

---

## Prevention Measures

### Pre-commit Hook
Located at: `.git/hooks/pre-commit`
- Automatically checks all staged files for secrets before commit
- Prevents accidental commits of sensitive data
- Must be explicitly bypassed to commit secrets

### .gitignore
The `.env` file is already in `.gitignore`, but the pre-commit hook provides an extra layer of protection.

### Best Practices Going Forward
1. **Never hardcode secrets** - Always use environment variables or secret management
2. **Use ${VARIABLE} references** in configuration files
3. **Test the pre-commit hook** - Try to commit a file with a webhook URL to verify it blocks
4. **Regular audits** - Periodically check for accidentally committed secrets

---

## Technical Details

### Tools Used
- `git-filter-repo` v2.47.0 - For history rewriting
- Custom pre-commit hook - For future prevention

### Commands Executed
```bash
# Install git-filter-repo
pip3 install git-filter-repo

# Create backup
cp -r home-server home-server-backup-20260119-163223

# Rewrite history
git-filter-repo --replace-text webhook-replacements.txt --force

# Force push to all branches
git remote add origin https://github.com/AntoineGlacet/home-server.git
git push --force --all origin
git push --force --tags origin
```

---

## Verification

To verify the webhook has been removed from history:
```bash
# Should return no results
git log --all --full-history -p -S "1461590139049607252"

# Should return no results
grep -r "1461590139049607252" . --exclude-dir=.git
```

---

## Recovery Information

If you need to recover the original repository:
- Backup location: `/home/antoine/home-server-backup-20260119-163223`
- Original remote: `https://github.com/AntoineGlacet/home-server.git`

⚠️ **Important**: The backup still contains the exposed webhook URL. Do not push it to any public repository.

---

**Completed**: 2026-01-19 16:33 JST
**Verified**: Git history cleaned, pre-commit hook active, changes pushed to GitHub
