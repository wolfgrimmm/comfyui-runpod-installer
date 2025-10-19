export interface ComfyUIStatus {
  running: boolean;
  current_user: string | null;
  start_time: number | null;
  gpu_info?: {
    name: string;
    memory_total: string;
    memory_used: string;
    utilization: string;
  };
  startup_progress?: {
    stage: string;
    message: string;
    percent: number;
  };
}

export const api = {
  async getStatus(): Promise<ComfyUIStatus> {
    const response = await fetch('/api/status');
    return response.json();
  },

  async startComfyUI(username: string): Promise<{ success: boolean; message: string }> {
    const response = await fetch('/api/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username }),
    });
    return response.json();
  },

  async stopComfyUI(): Promise<{ success: boolean; message: string }> {
    const response = await fetch('/api/stop', {
      method: 'POST',
    });
    return response.json();
  },

  async restartComfyUI(): Promise<{ success: boolean; message: string }> {
    const response = await fetch('/api/restart', {
      method: 'POST',
    });
    return response.json();
  },
};

