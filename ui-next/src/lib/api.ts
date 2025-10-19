const API_BASE_URL = process.env.NODE_ENV === 'production' 
  ? 'http://localhost:5001' 
  : 'http://localhost:5001';

export interface ComfyUIStatus {
  running: boolean;
  current_user: string;
  start_time: number | null;
  gpu_info: {
    name: string;
    memory_total: string;
    memory_used: string;
    utilization: string;
  };
}

export interface User {
  username: string;
  active: boolean;
}

export const api = {
  async getStatus(): Promise<ComfyUIStatus> {
    const response = await fetch(`${API_BASE_URL}/api/status`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  },

  async startComfyUI(username: string): Promise<{ success: boolean; message: string }> {
    const response = await fetch(`${API_BASE_URL}/api/start`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ username }),
    });
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  },

  async stopComfyUI(): Promise<{ success: boolean; message: string }> {
    const response = await fetch(`${API_BASE_URL}/api/stop`, {
      method: 'POST',
    });
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  },

  async getUsers(): Promise<User[]> {
    const response = await fetch(`${API_BASE_URL}/api/users`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  },

  async getGDriveStatus(): Promise<{ status: string; last_sync: string | null }> {
    const response = await fetch(`${API_BASE_URL}/api/gdrive/status`);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  },
};