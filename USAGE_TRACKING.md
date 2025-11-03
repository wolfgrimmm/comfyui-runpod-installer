# RunPod Usage Tracking

Automatically track GPU usage costs per team member and sync to Google Sheets.

## Features

- ✅ Track usage per user (hours, costs, GPU types)
- ✅ Automatic daily sync to Google Sheets
- ✅ Monthly reports for billing
- ✅ Runs via GitHub Actions (no pod needed!)
- ✅ Beautiful formatted sheets with totals

## Setup (One Time)

### 1. Add GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions → New repository secret

Add these two secrets:

**Secret 1: `COMFYUI_RUNPOD_API_KEY`**
- Value: Your RunPod API key from https://www.runpod.io/console/user/settings

**Secret 2: `GOOGLE_SERVICE_ACCOUNT`**
- Value: Your Google Service Account JSON (entire file contents as one line)
- Should look like: `{"type":"service_account","project_id":"...","private_key":"..."}`

### 2. Update User Mapping

Edit `scripts/track_usage.py` and `scripts/generate_monthly_report.py`:

```python
EMAIL_TO_USER_MAP = {
    "serhii.y@webgroup-limited.com": "serhii",
    "john@example.com": "john",          # Add your team members
    "jane@example.com": "jane",
}
```

### 3. Commit and Push

```bash
git add .
git commit -m "Setup usage tracking"
git push
```

That's it! The workflow will run automatically every day at midnight UTC.

## Usage

### Automatic Daily Sync

The GitHub Action runs automatically every day and:
1. Fetches all audit logs from RunPod
2. Calculates usage per user
3. Updates Google Sheets with:
   - **"Usage Summary"** tab (totals per user)
   - **"Detailed Sessions"** tab (every pod session)
   - **Current month report** tab

### Manual Trigger

Go to GitHub → Actions → "Track RunPod Usage" → Run workflow

### Generate Historical Monthly Reports

**Option 1: Via GitHub Actions**
1. Go to Actions → "Track RunPod Usage" → Run workflow
2. Check "Generate monthly report for previous month"
3. Click "Run workflow"

**Option 2: Locally**
```bash
# Install dependencies
pip install requests gspread oauth2client

# Set environment variables
export COMFYUI_RUNPOD_API_KEY="your-api-key"
export GOOGLE_SERVICE_ACCOUNT='{"type":"service_account",...}'

# Generate report for specific month
python scripts/generate_monthly_report.py 2024 12

# Or run without arguments for previous month
python scripts/generate_monthly_report.py
```

## Google Sheets Structure

### 1. Usage Summary Tab
```
User     | Total Hours | Total Cost ($) | Sessions | Last Updated
---------|-------------|----------------|----------|------------------
serhii   | 45.25       | 33.49          | 12       | 2025-01-31 14:30
antonia  | 23.50       | 17.39          | 8        | 2025-01-31 14:30
vlad     | 38.75       | 28.68          | 15       | 2025-01-31 14:30
         |             |                |          |
TOTAL    | 107.50      | 79.56          |          |
```

### 2. Detailed Sessions Tab
```
User   | Pod ID    | GPU Type  | Started             | Ended               | Duration | Cost/hr | Total Cost | Status
-------|-----------|-----------|---------------------|---------------------|----------|---------|------------|----------
serhii | abc123    | RTX 4090  | 2025-01-30 10:00:00 | 2025-01-30 14:30:00 | 4.50     | 0.74    | 3.33       | completed
serhii | def456    | RTX 5090  | 2025-01-30 15:00:00 | Still Running       | 23.50    | 1.89    | 44.42      | running
```

### 3. Monthly Report Tabs
```
January 2025 Report
December 2024 Report
November 2024 Report
...
```

## Local Testing

```bash
# Test daily sync
python scripts/track_usage.py

# Test monthly report
python scripts/generate_monthly_report.py 2024 12

# Output shows usage summary and Google Sheets URL
```

## Troubleshooting

**GitHub Action fails with "API key not set"**
- Check that `COMFYUI_RUNPOD_API_KEY` secret is added in GitHub
- Secret name must be exact (case-sensitive)

**GitHub Action fails with "Google credentials error"**
- Check that `GOOGLE_SERVICE_ACCOUNT` secret contains entire JSON file
- Make sure JSON is valid (no extra spaces/newlines)

**No data in sheets**
- Check that email addresses in `EMAIL_TO_USER_MAP` match RunPod audit logs
- RunPod audit logs show user emails, not usernames

**Sheets not updating**
- Check GitHub Actions logs for errors
- Verify service account has edit access to the sheet

## Cost

- **GitHub Actions**: Free (2000 minutes/month on free tier)
- **RunPod API**: Free
- **Google Sheets API**: Free

Total cost: **$0** 🎉
