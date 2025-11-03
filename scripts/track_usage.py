#!/usr/bin/env python3
"""
Standalone RunPod Usage Tracker
Runs independently of pods - can be executed locally or via GitHub Actions
Syncs usage data to Google Sheets automatically
"""

import os
import sys
from datetime import datetime, timedelta

# Add ui directory to path so we can import the modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'ui'))

from runpod_api import RunPodAPI
from sheets_sync import SheetsSync

# Email to username mapping
EMAIL_TO_USER_MAP = {
    "serhii.y@webgroup-limited.com": "serhii",
    "marcin.k@webgroup-limited.com": "marcin",
    "vladislav.k@webgroup-limited.com": "vlad",
    "ksenija.s@webgroup-limited.com": "ksenija",
    "max.k@webgroup-limited.com": "max",
    "ivan.s@webgroup-limited.com": "ivan",
    "antonia.v@webgroup-limited.com": "antonia"
}

def main():
    """Main function to track usage and sync to Google Sheets"""
    print("=" * 60)
    print("🔍 RunPod Usage Tracker")
    print("=" * 60)
    print()

    # Check for required environment variables
    if not os.environ.get('COMFYUI_RUNPOD_API_KEY') and not os.environ.get('API_KEY_RUNPOD'):
        print("❌ Error: COMFYUI_RUNPOD_API_KEY environment variable not set")
        print("   Set it in GitHub Secrets or export it locally")
        return 1

    if not os.environ.get('GOOGLE_SERVICE_ACCOUNT'):
        print("❌ Error: GOOGLE_SERVICE_ACCOUNT environment variable not set")
        print("   Set it in GitHub Secrets or export it locally")
        return 1

    try:
        # Initialize RunPod API
        print("📡 Connecting to RunPod API...")
        api = RunPodAPI()

        # DEBUG: Introspect the schema first
        print("🔍 Introspecting auditLogs schema...")
        api.introspect_audit_logs()

        # Calculate usage for all users
        print("📊 Calculating usage statistics...")
        usage_stats = api.calculate_user_usage(EMAIL_TO_USER_MAP)

        if not usage_stats:
            print("⚠️  No usage data found")
            return 0

        # Print summary
        print()
        print("📈 Usage Summary:")
        print("-" * 60)
        total_hours = 0
        total_cost = 0

        for username, stats in sorted(usage_stats.items()):
            hours = stats.get('total_hours', 0)
            cost = stats.get('total_cost', 0)
            sessions = len(stats.get('sessions', []))

            total_hours += hours
            total_cost += cost

            print(f"  {username:15} {hours:8.2f} hrs  ${cost:8.2f}  ({sessions} sessions)")

        print("-" * 60)
        print(f"  {'TOTAL':15} {total_hours:8.2f} hrs  ${total_cost:8.2f}")
        print()

        # Sync to Google Sheets
        print("📤 Syncing to Google Sheets...")
        sheets = SheetsSync()

        if sheets.update_usage_data(usage_stats):
            sheet_url = sheets.get_sheet_url()
            print(f"✅ Successfully synced to Google Sheets!")
            print(f"📊 View at: {sheet_url}")
            print()

            # Also generate monthly report for current month
            now = datetime.now()
            print(f"📅 Generating monthly report for {now.strftime('%B %Y')}...")

            if sheets.create_monthly_report(usage_stats, now.year, now.month):
                print(f"✅ Monthly report created!")

            return 0
        else:
            print("❌ Failed to sync to Google Sheets")
            return 1

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
