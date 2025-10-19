'use client';
import { useState } from 'react';
import { api } from '@/lib/api';
import RiveButton from '@/components/animations/RiveButton';
import StatusDot from '@/components/animations/StatusDot';
import type { ComfyUIStatus } from '@/types';

interface Props {
  status: ComfyUIStatus | null;
}

export default function ControlPanel({ status }: Props) {
  const [loading, setLoading] = useState(false);
  const [selectedUser, setSelectedUser] = useState('demo');

  const handleStart = async () => {
    if (loading) return;
    setLoading(true);
    // Mock API call - just show loading state
    setTimeout(() => {
      setLoading(false);
      console.log('Mock: Starting ComfyUI for', selectedUser);
    }, 2000);
  };

  const handleStop = async () => {
    if (loading) return;
    setLoading(true);
    // Mock API call
    setTimeout(() => {
      setLoading(false);
      console.log('Mock: Stopping ComfyUI');
    }, 1000);
  };

  const handleRestart = async () => {
    if (loading) return;
    setLoading(true);
    // Mock API call
    setTimeout(() => {
      setLoading(false);
      console.log('Mock: Restarting ComfyUI');
    }, 1500);
  };

  const isRunning = status?.running || false;
  const comfyUIStatus: 'idle' | 'loading' | 'ready' | 'error' = isRunning ? 
    (status?.startup_progress?.stage === 'ready' ? 'ready' : 'loading') : 
    'idle';

  return (
    <div className="card-glass p-8 max-w-4xl mx-auto">
      <div className="text-center mb-8">
        <h1 className="text-5xl font-bold mb-4 bg-gradient-to-r from-blue-400 to-purple-600 bg-clip-text text-transparent">
          ComfyUI Control Panel
        </h1>
        <p className="text-gray-400 text-lg">
          Manage your ComfyUI instance with advanced animations
        </p>
      </div>

      {/* Status Display */}
      <div className="flex items-center justify-center gap-4 mb-8 p-6 card-glass">
        <StatusDot 
          status={comfyUIStatus} 
          label={isRunning ? (status?.startup_progress?.message || 'Running') : 'Stopped'}
        />
        {status?.gpu && (
          <div className="ml-8 text-sm text-gray-400">
            <div>GPU: {status.gpu.name}</div>
            <div>VRAM: {Math.round(status.gpu.memory.used / 1024)} / {Math.round(status.gpu.memory.total / 1024)} GB</div>
          </div>
        )}
      </div>

      {/* User Selection */}
      <div className="mb-8">
        <label className="block text-sm font-medium mb-2 text-gray-300">
          Select User
        </label>
        <select
          value={selectedUser}
          onChange={(e) => setSelectedUser(e.target.value)}
          className="w-full px-4 py-3 bg-black/50 border border-white/10 rounded-lg
                   focus:outline-none focus:border-blue-500 transition-colors"
          disabled={isRunning}
        >
          <option value="demo">Demo User</option>
          <option value="serhii">Serhii</option>
          <option value="antonia">Antonia</option>
        </select>
      </div>

      {/* Action Buttons */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {!isRunning ? (
          <div className="md:col-span-3">
            <RiveButton 
              onClick={handleStart} 
              disabled={loading}
              variant="primary"
            >
              {loading ? 'Starting...' : 'Launch ComfyUI'}
            </RiveButton>
          </div>
        ) : (
          <>
            <RiveButton 
              onClick={() => window.open('http://localhost:8188', '_blank')}
              variant="primary"
            >
              Open ComfyUI
            </RiveButton>
            <RiveButton 
              onClick={handleRestart} 
              disabled={loading}
              variant="secondary"
            >
              {loading ? 'Restarting...' : 'Restart'}
            </RiveButton>
            <RiveButton 
              onClick={handleStop} 
              disabled={loading}
              variant="secondary"
            >
              {loading ? 'Stopping...' : 'Stop'}
            </RiveButton>
          </>
        )}
      </div>

      {/* Additional Info */}
      {isRunning && status?.current_user && (
        <div className="mt-6 p-4 bg-blue-500/10 border border-blue-500/20 rounded-lg">
          <p className="text-sm text-blue-300">
            ✓ Running as <strong>{status.current_user}</strong>
            {status.start_time && (
              <span className="ml-4">
                Started {new Date(status.start_time * 1000).toLocaleTimeString()}
              </span>
            )}
          </p>
        </div>
      )}
    </div>
  );
}

