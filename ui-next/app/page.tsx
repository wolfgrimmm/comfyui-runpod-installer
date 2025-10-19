'use client';

import { useState, useEffect } from 'react';
import ControlPanel from './components/ControlPanel';
import { api, ComfyUIStatus } from './lib/api';

export default function Home() {
  const [status, setStatus] = useState<ComfyUIStatus | null>(null);

  useEffect(() => {
    // Fetch initial status
    const fetchStatus = async () => {
      try {
        const data = await api.getStatus();
        setStatus(data);
      } catch (error) {
        // Use mock data if API is unavailable
        setStatus({
          running: false,
          current_user: 'demo',
          start_time: null,
          gpu_info: {
            name: 'NVIDIA GeForce RTX 4090',
            memory_total: '24576',
            memory_used: '0',
            utilization: '0',
          },
        });
      }
    };

    fetchStatus();

    // Poll status every 3 seconds
    const interval = setInterval(fetchStatus, 3000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="min-h-screen bg-black text-white overflow-hidden relative">

      {/* DRAMATIC Background gradients */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div className="absolute -top-1/4 -left-1/4 w-[800px] h-[800px] bg-red-500/40 rounded-full blur-[120px] animate-pulse" />
        <div className="absolute top-1/3 -right-1/4 w-[700px] h-[700px] bg-purple-500/40 rounded-full blur-[120px] animate-pulse" style={{ animationDelay: '1s' }} />
        <div className="absolute -bottom-1/4 left-1/4 w-[600px] h-[600px] bg-blue-500/40 rounded-full blur-[120px] animate-pulse" style={{ animationDelay: '2s' }} />
        <div className="absolute top-1/2 left-1/2 w-[500px] h-[500px] bg-green-500/30 rounded-full blur-[120px] animate-pulse" style={{ animationDelay: '0.5s' }} />
      </div>

      {/* Main content */}
      <main className="relative z-10 container mx-auto px-6 py-12">
        <ControlPanel status={status} />
      </main>
    </div>
  );
}
