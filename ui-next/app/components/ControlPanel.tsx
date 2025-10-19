'use client';

import { useState } from 'react';
import { api, ComfyUIStatus } from '../lib/api';

interface Props {
  status: ComfyUIStatus | null;
}

export default function ControlPanel({ status }: Props) {
  const [loading, setLoading] = useState(false);
  const [selectedUser, setSelectedUser] = useState('demo');

  const handleStart = async () => {
    setLoading(true);
    try {
      const result = await api.startComfyUI(selectedUser);
      console.log('Start result:', result);
    } catch (error) {
      console.error('Error starting ComfyUI:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleStop = async () => {
    setLoading(true);
    try {
      const result = await api.stopComfyUI();
      console.log('Stop result:', result);
    } catch (error) {
      console.error('Error stopping ComfyUI:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRestart = async () => {
    setLoading(true);
    try {
      const result = await api.restartComfyUI();
      console.log('Restart result:', result);
    } catch (error) {
      console.error('Error restarting ComfyUI:', error);
    } finally {
      setLoading(false);
    }
  };

  const isRunning = status?.running || false;
  const statusType: 'idle' | 'loading' | 'ready' | 'error' = isRunning
    ? status?.startup_progress?.stage === 'ready'
      ? 'ready'
      : 'loading'
    : 'idle';

  const statusColors = {
    idle: '#666666',
    loading: '#f59e0b',
    ready: '#10b981',
    error: '#ef4444',
  };

  return (
    <div className="card-glass p-8 max-w-4xl mx-auto relative z-10 animate-fade-in">
      {/* Title */}
      <div className="text-center mb-12 animate-slide-down">
        <h1 className="text-7xl font-black mb-6 text-white drop-shadow-2xl">
          COMFY<span className="text-red-500">UI</span>
        </h1>
        <p className="text-xl text-gray-300 font-semibold">
          Powered by Next.js 15 + Turbopack
        </p>
      </div>

      {/* Status Display - Pure CSS */}
      <div className="flex items-center justify-center gap-4 mb-8 p-6 card-glass animate-slide-up" style={{ animationDelay: '0.1s' }}>
        <div className="flex items-center gap-3">
          {/* Pure CSS pulsing dot */}
          <div 
            className="relative w-3 h-3 rounded-full animate-pulse"
            style={{ 
              backgroundColor: statusColors[statusType],
              boxShadow: `0 0 10px ${statusColors[statusType]}`,
            }}
          />
          <span className="font-medium text-white">
            {isRunning ? (status?.startup_progress?.message || 'Running') : 'System Inactive'}
          </span>
        </div>
        {status?.gpu_info && (
          <div className="ml-8 text-sm text-gray-400">
            <div className="font-semibold text-blue-300">
              GPU: {status.gpu_info.name}
            </div>
            <div className="text-green-300">
              VRAM: {Math.round(parseInt(status.gpu_info.memory_used) / 1024)} /{' '}
              {Math.round(parseInt(status.gpu_info.memory_total) / 1024)} GB
            </div>
          </div>
        )}
      </div>

      {/* User Selection */}
      <div className="mb-8 animate-slide-up" style={{ animationDelay: '0.2s' }}>
        <label className="block text-sm font-medium mb-2 text-gray-300">
          Select User
        </label>
        <select
          value={selectedUser}
          onChange={(e) => setSelectedUser(e.target.value)}
          className="w-full px-4 py-3 bg-black/50 border border-white/10 rounded-lg
                     focus:outline-none focus:border-red-500 smooth-transition text-white hover:scale-[1.02] transition-transform"
          disabled={isRunning}
        >
          <option value="demo">Demo User</option>
          <option value="serhii">Serhii</option>
          <option value="antonia">Antonia</option>
        </select>
      </div>

      {/* Action Buttons - Pure CSS */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 animate-slide-up" style={{ animationDelay: '0.3s' }}>
        {!isRunning ? (
          <div className="md:col-span-3">
            <button
              onClick={handleStart}
              disabled={loading}
              className="w-full px-10 py-5 rounded-2xl font-bold text-xl text-white
                       bg-gradient-to-br from-red-500 via-red-600 via-purple-600 to-blue-600 
                       shadow-2xl shadow-red-500/50
                       hover:scale-105 hover:-translate-y-1 transition-all duration-300
                       disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? 'Starting...' : 'Launch ComfyUI'}
            </button>
          </div>
        ) : (
          <>
            <button
              onClick={() => window.open('http://localhost:8188', '_blank')}
              className="px-10 py-5 rounded-2xl font-bold text-xl text-white
                       bg-gradient-to-br from-green-500 via-green-600 to-emerald-600 
                       shadow-2xl shadow-green-500/50
                       hover:scale-105 hover:-translate-y-1 transition-all duration-300"
            >
              Open ComfyUI
            </button>
            <button
              onClick={handleRestart}
              disabled={loading}
              className="px-10 py-5 rounded-2xl font-bold text-xl text-white
                       bg-gradient-to-br from-gray-600 via-gray-700 to-gray-800 
                       border-2 border-white/20 shadow-xl
                       hover:scale-105 hover:-translate-y-1 transition-all duration-300
                       disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? 'Restarting...' : 'Restart'}
            </button>
            <button
              onClick={handleStop}
              disabled={loading}
              className="px-10 py-5 rounded-2xl font-bold text-xl text-white
                       bg-gradient-to-br from-gray-600 via-gray-700 to-gray-800 
                       border-2 border-white/20 shadow-xl
                       hover:scale-105 hover:-translate-y-1 transition-all duration-300
                       disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? 'Stopping...' : 'Stop'}
            </button>
          </>
        )}
      </div>

      {/* Additional Info */}
      {isRunning && status?.current_user && (
        <div className="mt-6 p-4 bg-green-500/10 border border-green-500/20 rounded-lg animate-slide-up" style={{ animationDelay: '0.4s' }}>
          <p className="text-sm text-green-300">
            ✓ Running as <strong>{status.current_user}</strong>
            {status.start_time && (
              <span className="ml-4">
                Started{' '}
                {new Date(status.start_time * 1000).toLocaleTimeString()}
              </span>
            )}
          </p>
        </div>
      )}
    </div>
  );
}
