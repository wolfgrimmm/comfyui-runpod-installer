"""
RunPod GraphQL API Integration
Query audit logs and pod usage for team tracking
"""

import os
import requests
import json
from datetime import datetime
from typing import Dict, List, Optional, Tuple

class RunPodAPI:
    def __init__(self):
        # Try multiple environment variable names for flexibility
        self.api_key = (
            os.environ.get('COMFYUI_RUNPOD_API_KEY') or  # Primary
            os.environ.get('API_KEY_RUNPOD') or          # Alternative
            os.environ.get('RUNPOD_API_KEY')             # Fallback (if RunPod allows it later)
        )
        self.endpoint = 'https://api.runpod.io/graphql'

    def _query(self, query: str, variables: Optional[Dict] = None) -> Dict:
        """Execute GraphQL query"""
        if not self.api_key:
            raise Exception("RUNPOD_API_KEY environment variable not set")

        headers = {
            'Content-Type': 'application/json',
        }

        # API key can be in URL or header
        url = f"{self.endpoint}?api_key={self.api_key}"

        payload = {'query': query}
        if variables:
            payload['variables'] = variables

        response = requests.post(url, json=payload, headers=headers)

        # Print debug info for errors
        if response.status_code != 200:
            print(f"GraphQL Error Response:")
            print(f"Status: {response.status_code}")
            print(f"Body: {response.text}")

        response.raise_for_status()

        return response.json()

    def get_audit_logs(self, limit: int = 100, cursor: Optional[str] = None) -> Dict:
        """
        Get audit logs from RunPod
        Returns pod creation/deletion events with timestamps
        """
        query = """
        query GetAuditLogs($after: String) {
            myself {
                auditLogs(first: %d, after: $after) {
                    edges {
                        node {
                            id
                            actorId
                            action
                            timestamp
                            resourceType
                            resourceId
                            metadata
                        }
                    }
                    pageInfo {
                        hasNextPage
                        endCursor
                    }
                }
            }
        }
        """ % limit

        variables = {'after': cursor} if cursor else {'after': None}
        result = self._query(query, variables)

        return result.get('data', {}).get('myself', {}).get('auditLogs', {})

    def get_all_audit_logs(self, limit: int = 1000) -> List[Dict]:
        """
        Get all audit logs (paginated)
        Returns list of audit log entries
        """
        all_logs = []
        cursor = None

        while True:
            logs_data = self.get_audit_logs(limit=100, cursor=cursor)

            edges = logs_data.get('edges', [])
            if not edges:
                break

            # Extract nodes
            for edge in edges:
                node = edge.get('node', {})
                all_logs.append(node)

            # Check if there are more pages
            page_info = logs_data.get('pageInfo', {})
            if not page_info.get('hasNextPage'):
                break

            cursor = page_info.get('endCursor')

            if len(all_logs) >= limit:
                break

        return all_logs

    def get_pod_details(self, pod_id: str) -> Optional[Dict]:
        """
        Get detailed information about a specific pod
        """
        query = """
        query GetPodDetails($podId: String!) {
            pod(input: {podId: $podId}) {
                id
                name
                createdAt
                machineId
                machine {
                    gpuDisplayName
                }
                gpuCount
                costPerHr
                adjustedCostPerHr
                uptimeSeconds
                lastStatusChange
                lastStartedAt
                desiredStatus
                runtime {
                    uptimeInSeconds
                    gpus {
                        id
                        gpuUtilPercent
                        memoryUtilPercent
                    }
                }
            }
        }
        """

        variables = {'podId': pod_id}
        result = self._query(query, variables)

        return result.get('data', {}).get('pod')

    def get_all_pods(self) -> List[Dict]:
        """
        Get all current pods (active)
        """
        query = """
        query GetAllPods {
            myself {
                pods {
                    id
                    name
                    createdAt
                    machineId
                    machine {
                        gpuDisplayName
                    }
                    gpuCount
                    costPerHr
                    adjustedCostPerHr
                    uptimeSeconds
                    lastStatusChange
                    lastStartedAt
                    desiredStatus
                }
            }
        }
        """

        result = self._query(query)
        return result.get('data', {}).get('myself', {}).get('pods', [])

    def calculate_user_usage(self, email_to_user_map: Dict[str, str]) -> Dict[str, Dict]:
        """
        Calculate GPU usage per user based on audit logs

        Args:
            email_to_user_map: Map of email addresses to usernames
                               e.g., {"serhii.y@webgroup-limited.com": "serhii"}

        Returns:
            Dictionary with user statistics:
            {
                "serhii": {
                    "total_hours": 10.5,
                    "total_cost": 7.77,
                    "sessions": [
                        {
                            "pod_id": "abc123",
                            "gpu_type": "RTX 4090",
                            "created_at": "2025-01-03T14:30:00Z",
                            "deleted_at": "2025-01-03T18:45:00Z",
                            "duration_hours": 4.25,
                            "cost_per_hour": 0.74,
                            "total_cost": 3.15
                        }
                    ]
                }
            }
        """
        # Get audit logs
        logs = self.get_all_audit_logs(limit=1000)

        # Group by user
        user_stats = {}
        pod_sessions = {}  # Track pod lifecycle: {pod_id: {created_at, created_by, gpu, cost}}

        for log in logs:
            action = log.get('action', '')
            actor_id = log.get('actorId', '')
            timestamp = log.get('timestamp')
            resource_type = log.get('resourceType', '')
            resource_id = log.get('resourceId', '')

            # Only process pod-related actions
            if resource_type != 'Pod':
                continue

            # Map email to username
            username = email_to_user_map.get(actor_id, actor_id)

            # Initialize user stats
            if username not in user_stats:
                user_stats[username] = {
                    'total_hours': 0,
                    'total_cost': 0,
                    'sessions': []
                }

            # Track pod creation
            if action == 'created' or action == 'create':
                # Try to get pod details for GPU info
                try:
                    pod_details = self.get_pod_details(resource_id)
                    if pod_details:
                        gpu_type = pod_details.get('machine', {}).get('gpuDisplayName', 'Unknown')
                        cost_per_hr = pod_details.get('costPerHr', 0.74)
                    else:
                        gpu_type = 'Unknown'
                        cost_per_hr = 0.74
                except:
                    gpu_type = 'Unknown'
                    cost_per_hr = 0.74

                pod_sessions[resource_id] = {
                    'created_at': timestamp,
                    'created_by': username,
                    'gpu_type': gpu_type,
                    'cost_per_hour': cost_per_hr
                }

            # Track pod deletion
            elif action == 'deleted' or action == 'delete':
                if resource_id in pod_sessions:
                    session = pod_sessions[resource_id]
                    created_at = datetime.fromisoformat(session['created_at'].replace('Z', '+00:00'))
                    deleted_at = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))

                    duration_hours = (deleted_at - created_at).total_seconds() / 3600
                    total_cost = duration_hours * session['cost_per_hour']

                    # Add session to user stats
                    session_data = {
                        'pod_id': resource_id,
                        'gpu_type': session['gpu_type'],
                        'created_at': session['created_at'],
                        'deleted_at': timestamp,
                        'duration_hours': round(duration_hours, 2),
                        'cost_per_hour': session['cost_per_hour'],
                        'total_cost': round(total_cost, 2)
                    }

                    user_stats[session['created_by']]['sessions'].append(session_data)
                    user_stats[session['created_by']]['total_hours'] += duration_hours
                    user_stats[session['created_by']]['total_cost'] += total_cost

                    # Clean up
                    del pod_sessions[resource_id]

        # Handle pods that are still running (not deleted yet)
        for pod_id, session in pod_sessions.items():
            try:
                pod_details = self.get_pod_details(pod_id)
                if pod_details:
                    # Pod still exists, calculate current runtime
                    created_at = datetime.fromisoformat(session['created_at'].replace('Z', '+00:00'))
                    now = datetime.now(created_at.tzinfo)

                    duration_hours = (now - created_at).total_seconds() / 3600
                    total_cost = duration_hours * session['cost_per_hour']

                    session_data = {
                        'pod_id': pod_id,
                        'gpu_type': session['gpu_type'],
                        'created_at': session['created_at'],
                        'deleted_at': None,  # Still running
                        'duration_hours': round(duration_hours, 2),
                        'cost_per_hour': session['cost_per_hour'],
                        'total_cost': round(total_cost, 2),
                        'status': 'running'
                    }

                    user_stats[session['created_by']]['sessions'].append(session_data)
                    user_stats[session['created_by']]['total_hours'] += duration_hours
                    user_stats[session['created_by']]['total_cost'] += total_cost
            except:
                pass

        # Round totals
        for username in user_stats:
            user_stats[username]['total_hours'] = round(user_stats[username]['total_hours'], 2)
            user_stats[username]['total_cost'] = round(user_stats[username]['total_cost'], 2)

        return user_stats

    def get_spending_summary(self) -> Dict:
        """
        Get overall spending summary from RunPod account
        """
        query = """
        query GetSpendingSummary {
            myself {
                currentSpendPerHr
                spendLimit
                clientLifetimeSpend
                clientBalance
                spendDetails
            }
        }
        """

        result = self._query(query)
        return result.get('data', {}).get('myself', {})
