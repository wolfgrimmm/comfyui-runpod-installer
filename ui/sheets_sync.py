"""
Google Sheets Integration for RunPod Usage Tracking
Automatically syncs usage data to Google Sheets for easy viewing
"""

import os
import json
from datetime import datetime
from typing import Dict, Optional
import gspread
from oauth2client.service_account import ServiceAccountCredentials

class SheetsSync:
    def __init__(self):
        self.sheet_name = "RunPod Usage Tracking"
        self.creds = None
        self.client = None
        self.spreadsheet = None

    def _get_credentials(self) -> Optional[ServiceAccountCredentials]:
        """Get Google service account credentials from environment or file"""

        # Try to get from environment variable (same as Drive sync)
        service_account_json = (
            os.environ.get('GOOGLE_SERVICE_ACCOUNT') or
            os.environ.get('RUNPOD_SECRET_GOOGLE_SERVICE_ACCOUNT')
        )

        if service_account_json:
            # Parse JSON from environment variable
            try:
                creds_dict = json.loads(service_account_json)
                scope = [
                    'https://spreadsheets.google.com/feeds',
                    'https://www.googleapis.com/auth/drive'
                ]
                return ServiceAccountCredentials.from_json_keyfile_dict(creds_dict, scope)
            except json.JSONDecodeError as e:
                print(f"Error parsing service account JSON: {e}")
                return None

        # Try to get from file (fallback)
        service_account_file = (
            os.environ.get('GOOGLE_SERVICE_ACCOUNT_FILE') or
            '/root/.config/rclone/service_account.json' or
            '/workspace/.config/rclone/service_account.json'
        )

        if os.path.exists(service_account_file):
            scope = [
                'https://spreadsheets.google.com/feeds',
                'https://www.googleapis.com/auth/drive'
            ]
            return ServiceAccountCredentials.from_json_keyfile_name(service_account_file, scope)

        return None

    def connect(self) -> bool:
        """Connect to Google Sheets API"""
        try:
            self.creds = self._get_credentials()
            if not self.creds:
                print("No Google service account credentials found")
                return False

            self.client = gspread.authorize(self.creds)
            return True

        except Exception as e:
            print(f"Error connecting to Google Sheets: {e}")
            return False

    def get_or_create_sheet(self) -> Optional[gspread.Spreadsheet]:
        """Get existing sheet or create new one"""
        try:
            if not self.client:
                if not self.connect():
                    return None

            # Try to open existing sheet
            try:
                self.spreadsheet = self.client.open(self.sheet_name)
                print(f"✅ Found existing sheet: {self.sheet_name}")
                return self.spreadsheet
            except gspread.SpreadsheetNotFound:
                pass

            # Create new sheet
            print(f"📄 Creating new sheet: {self.sheet_name}")
            self.spreadsheet = self.client.create(self.sheet_name)

            # Share with team (make it viewable by anyone with the link)
            try:
                self.spreadsheet.share(None, perm_type='anyone', role='reader')
                print(f"✅ Sheet is now viewable by anyone with the link")
            except Exception as e:
                print(f"⚠️ Could not share sheet publicly: {e}")

            return self.spreadsheet

        except Exception as e:
            print(f"Error getting/creating sheet: {e}")
            return None

    def update_usage_data(self, usage_stats: Dict[str, Dict]) -> bool:
        """
        Update Google Sheet with usage data

        Args:
            usage_stats: Dictionary from runpod_api.calculate_user_usage()
                {
                    "serhii": {
                        "total_hours": 10.5,
                        "total_cost": 7.77,
                        "sessions": [...]
                    }
                }

        Returns:
            True if successful, False otherwise
        """
        try:
            sheet = self.get_or_create_sheet()
            if not sheet:
                return False

            # Get the first worksheet (or create it)
            try:
                worksheet = sheet.get_worksheet(0)
            except:
                worksheet = sheet.add_worksheet(title="Usage Summary", rows=100, cols=10)

            # Prepare data
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            # Header row
            headers = ["User", "Total Hours", "Total Cost ($)", "Sessions", "Last Updated"]

            # Data rows
            rows = [headers]
            total_hours = 0
            total_cost = 0

            for username, stats in sorted(usage_stats.items()):
                hours = stats.get('total_hours', 0)
                cost = stats.get('total_cost', 0)
                sessions_count = len(stats.get('sessions', []))

                total_hours += hours
                total_cost += cost

                rows.append([
                    username,
                    round(hours, 2),
                    round(cost, 2),
                    sessions_count,
                    current_time
                ])

            # Add totals row
            rows.append([])  # Empty row
            rows.append([
                "TOTAL",
                round(total_hours, 2),
                round(total_cost, 2),
                "",
                ""
            ])

            # Clear existing content and update
            worksheet.clear()
            worksheet.update('A1', rows)

            # Format header row (bold)
            worksheet.format('A1:E1', {
                "textFormat": {"bold": True},
                "backgroundColor": {"red": 0.9, "green": 0.9, "blue": 0.9}
            })

            # Format totals row (bold)
            total_row = len(rows)
            worksheet.format(f'A{total_row}:E{total_row}', {
                "textFormat": {"bold": True},
                "backgroundColor": {"red": 1, "green": 0.95, "blue": 0.8}
            })

            # Auto-resize columns
            worksheet.columns_auto_resize(0, 4)

            print(f"✅ Updated sheet with {len(usage_stats)} users")
            print(f"📊 Total: {round(total_hours, 2)} hours, ${round(total_cost, 2)}")

            # Create detailed sessions worksheet
            self._update_sessions_sheet(sheet, usage_stats, current_time)

            return True

        except Exception as e:
            print(f"Error updating usage data: {e}")
            import traceback
            traceback.print_exc()
            return False

    def _update_sessions_sheet(self, spreadsheet: gspread.Spreadsheet,
                               usage_stats: Dict[str, Dict], current_time: str):
        """Create/update detailed sessions worksheet"""
        try:
            # Try to get existing worksheet
            try:
                worksheet = spreadsheet.worksheet("Detailed Sessions")
            except:
                worksheet = spreadsheet.add_worksheet(title="Detailed Sessions", rows=1000, cols=10)

            # Header row
            headers = [
                "User", "Pod ID", "GPU Type", "Started", "Ended",
                "Duration (hrs)", "Cost/hr ($)", "Total Cost ($)", "Status"
            ]

            # Data rows
            rows = [headers]

            for username, stats in sorted(usage_stats.items()):
                sessions = stats.get('sessions', [])

                for session in sessions:
                    status = session.get('status', 'completed')
                    rows.append([
                        username,
                        session.get('pod_id', 'N/A'),
                        session.get('gpu_type', 'Unknown'),
                        session.get('created_at', 'N/A'),
                        session.get('deleted_at', 'Still Running' if status == 'running' else 'N/A'),
                        round(session.get('duration_hours', 0), 2),
                        round(session.get('cost_per_hour', 0), 2),
                        round(session.get('total_cost', 0), 2),
                        status
                    ])

            # Add timestamp footer
            rows.append([])
            rows.append([f"Last Updated: {current_time}"])

            # Clear and update
            worksheet.clear()
            worksheet.update('A1', rows)

            # Format header
            worksheet.format('A1:I1', {
                "textFormat": {"bold": True},
                "backgroundColor": {"red": 0.9, "green": 0.9, "blue": 0.9}
            })

            # Auto-resize columns
            worksheet.columns_auto_resize(0, 8)

            print(f"✅ Updated detailed sessions sheet with {len(rows)-3} sessions")

        except Exception as e:
            print(f"Warning: Could not update sessions sheet: {e}")

    def get_sheet_url(self) -> Optional[str]:
        """Get the URL of the Google Sheet"""
        if self.spreadsheet:
            return self.spreadsheet.url
        return None
