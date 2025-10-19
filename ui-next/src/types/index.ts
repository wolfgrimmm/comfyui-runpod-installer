export interface ComfyUIStatus {
  running: boolean;
  current_user: string | null;
  start_time: number | null;
  gpu_info?: {
    name: string;
    memory_total: string;
    memory_used: string;
    utilization?: string;
  };
  startup_progress?: {
    stage: string;
    message: string;
    percent: number;
  };
}

export interface Feature {
  title: string;
  icon: string;
  desc: string;
  span: string;
}



