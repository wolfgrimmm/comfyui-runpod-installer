#!/usr/bin/env python3
"""
Generate Monthly RunPod Usage Report
Creates a monthly report for a specific month (defaults to previous month)
"""

import os
import sys
from datetime import datetime, timedelta
from calendar import monthrange

# Add ui directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'ui'))

from runpod_api import RunPodAPI
from sheets_sync import SheetsSync

# Email to username mapping (same as track_usage.py)
EMAIL_TO_USER_MAP = {
    "serhii.y@webgroup-limited.com": "serhii",
    "marcin.k@webgroup-limited.com": "marcin",
    "vladislav.k@webgroup-limited.com": "vlad",
    "ksenija.s@webgroup-limited.com": "ksenija",
    "max.k@webgroup-limited.com": "max",
    "ivan.s@webgroup-limited.com": "ivan",
    "antonia.v@webgroup-limited.com": "antonia"
}

def filter_usage_by_month(usage_stats, year, month):
    """Filter usage stats to only include sessions from specified month"""
    filtered_stats = {}

    # Get month start and end timestamps
    start_date = datetime(year, month, 1)
    _, last_day = monthrange(year, month)
    end_date = datetime(year, month, last_day, 23, 59, 59)

    for username, stats in usage_stats.items():
        filtered_sessions = []

        for session in stats.get('sessions', []):
            # Parse session start time
            created_at = session.get('created_at', '')
            if not created_at:
                continue

            try:
                session_date = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                session_date = session_date.replace(tzinfo=None)  # Remove timezone for comparison

                # Check if session is within the month
                if start_date <= session_date <= end_date:
                    filtered_sessions.append(session)

            except Exception as e:
                print(f"Warning: Could not parse date {created_at}: {e}")
                continue

        # Calculate totals for filtered sessions
        if filtered_sessions:
            total_hours = sum(s.get('duration_hours', 0) for s in filtered_sessions)
            total_cost = sum(s.get('total_cost', 0) for s in filtered_sessions)

            filtered_stats[username] = {
                'total_hours': total_hours,
                'total_cost': total_cost,
                'sessions': filtered_sessions
            }

    return filtered_stats

def main():
    """Generate monthly report"""
    print("=" * 60)
    print("📅 Monthly RunPod Usage Report Generator")
    print("=" * 60)
    print()

    # Default to previous month
    now = datetime.now()
    if now.month == 1:
        year = now.year - 1
        month = 12
    else:
        year = now.year
        month = now.month - 1

    month_name = datetime(year, month, 1).strftime("%B %Y")

    # Check for command line arguments
    if len(sys.argv) >= 3:
        try:
            year = int(sys.argv[1])
            month = int(sys.argv[2])
            month_name = datetime(year, month, 1).strftime("%B %Y")
        except:
            print("Usage: python generate_monthly_report.py [year] [month]")
            print("Example: python generate_monthly_report.py 2024 12")
            return 1

    print(f"📊 Generating report for: {month_name}")
    print()

    try:
        # Initialize RunPod API
        print("📡 Fetching audit logs from RunPod...")
        api = RunPodAPI()

        # Get ALL usage data
        all_usage_stats = api.calculate_user_usage(EMAIL_TO_USER_MAP)

        # Filter to specific month
        print(f"🔍 Filtering sessions for {month_name}...")
        month_usage_stats = filter_usage_by_month(all_usage_stats, year, month)

        if not month_usage_stats:
            print(f"⚠️  No usage data found for {month_name}")
            return 0

        # Print summary
        print()
        print(f"📈 {month_name} Summary:")
        print("-" * 60)
        total_hours = 0
        total_cost = 0

        for username, stats in sorted(month_usage_stats.items()):
            hours = stats.get('total_hours', 0)
            cost = stats.get('total_cost', 0)
            sessions = len(stats.get('sessions', []))

            total_hours += hours
            total_cost += cost

            print(f"  {username:15} {hours:8.2f} hrs  ${cost:8.2f}  ({sessions} sessions)")

        print("-" * 60)
        print(f"  {'TOTAL':15} {total_hours:8.2f} hrs  ${total_cost:8.2f}")
        print()

        # Create monthly report in Google Sheets
        print(f"📤 Creating {month_name} worksheet in Google Sheets...")
        sheets = SheetsSync()

        if sheets.create_monthly_report(month_usage_stats, year, month):
            sheet_url = sheets.get_sheet_url()
            print(f"✅ Monthly report created!")
            print(f"📊 View at: {sheet_url}")
            return 0
        else:
            print("❌ Failed to create monthly report")
            return 1

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
