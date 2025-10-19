'use client';

import { motion, useAnimation } from 'framer-motion';
import { useState, useEffect } from 'react';
import { Canvas } from '@react-three/fiber';
import GlassShader from './GlassShader';
import { AnimatedButton, AnimatedCard, AnimatedIcon, StatusIndicator } from './AnimatedComponents';

interface ControlPanelProps {
  // Mock data for now - will connect to Flask API later
  users?: string[];
  currentUser?: string;
  running?: boolean;
  gpuInfo?: {
    name: string;
    memory_used: string;
    memory_total: string;
    utilization: string;
  };
}

export default function ControlPanel({ 
  users = ['serhii', 'antonia', 'vlad'],
  currentUser = 'serhii',
  running = false,
  gpuInfo = {
    name: 'NVIDIA GeForce RTX 4090',
    memory_used: '8.2',
    memory_total: '24.0',
    utilization: '45'
  }
}: ControlPanelProps) {
  const [selectedUser, setSelectedUser] = useState(currentUser);
  const [isRunning, setIsRunning] = useState(running);
  const [isInitializing, setIsInitializing] = useState(false);
  const controls = useAnimation();

  const handleLaunchComfyUI = async () => {
    setIsInitializing(true);
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 2000));
    setIsRunning(true);
    setIsInitializing(false);
  };

  const handleStopComfyUI = () => {
    setIsRunning(false);
  };

  const handleOpenComfyUI = () => {
    window.open('http://localhost:8188', '_blank');
  };

  const getStatus = () => {
    if (isInitializing) return 'initializing';
    if (isRunning) return 'ready';
    return 'inactive';
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 relative overflow-hidden">
      {/* Three.js Glass Background */}
      <div className="absolute inset-0">
        <Canvas camera={{ position: [0, 0, 5], fov: 75 }}>
          <GlassShader />
        </Canvas>
      </div>

      {/* Main Content */}
      <div className="relative z-10 container mx-auto px-4 py-8">
        {/* Header */}
        <motion.div
          initial={{ opacity: 0, y: -50 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, ease: 'easeOut' }}
          className="text-center mb-12"
        >
          <motion.h1
            initial={{ opacity: 0, scale: 0.5 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1, delay: 0.2 }}
            className="text-6xl font-bold text-white mb-4"
            style={{
              background: 'linear-gradient(45deg, #ffffff, #e7331d, #ffffff)',
              backgroundSize: '200% 200%',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              animation: 'gradientShift 3s ease-in-out infinite'
            }}
          >
            COMFY<span className="text-red-500">UI</span>
          </motion.h1>
          
          {/* Typing cursor effect */}
          <motion.span
            className="text-white text-6xl"
            animate={{ opacity: [1, 0, 1] }}
            transition={{ duration: 1, repeat: Infinity }}
          >
            |
          </motion.span>
        </motion.div>

        {/* Quick Actions */}
        <motion.div
          initial={{ opacity: 0, x: -50 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.8, delay: 0.4 }}
          className="flex justify-end gap-4 mb-8"
        >
          <AnimatedIcon delay={0.1}>
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
            </svg>
          </AnimatedIcon>
          
          <AnimatedIcon delay={0.2}>
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
            </svg>
          </AnimatedIcon>
        </motion.div>

        {/* Status Card */}
        <AnimatedCard delay={0.3} className="mb-8">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-4">
              <StatusIndicator status={getStatus()} />
              <div>
                <h2 className="text-xl font-semibold text-white">
                  {isRunning ? `Active • ${selectedUser}` : 'Inactive • Select User'}
                </h2>
              </div>
            </div>
            
            <AnimatedIcon delay={0.4}>
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004 12m0 8v-5h.581m0 0a8.003 8.003 0 0015.357-2m-1.857-20v5h.581m0 0a8.003 8.003 0 00-15.357 2m1.857 20v-5h.581m0 0a8.003 8.003 0 0015.357-2" />
              </svg>
            </AnimatedIcon>
          </div>

          {/* User Selection */}
          <div className="mb-6">
            <label className="block text-sm font-medium text-gray-300 mb-2">User:</label>
            <motion.select
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.5 }}
              value={selectedUser}
              onChange={(e) => setSelectedUser(e.target.value)}
              disabled={isRunning}
              className="w-full px-4 py-3 rounded-xl bg-white/10 border border-white/20 text-white focus:outline-none focus:ring-2 focus:ring-red-500/50 disabled:opacity-50"
            >
              {users.map((user) => (
                <option key={user} value={user} className="bg-gray-800 text-white">
                  {user}
                </option>
              ))}
            </motion.select>
          </div>

          {/* GPU Info */}
          <div className="grid grid-cols-3 gap-4">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.6 }}
              className="text-center"
            >
              <div className="text-sm text-gray-400">GPU</div>
              <div className="text-lg font-semibold text-white">{gpuInfo.name}</div>
            </motion.div>
            
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.7 }}
              className="text-center"
            >
              <div className="text-sm text-gray-400">VRAM</div>
              <div className="text-lg font-semibold text-white">
                {gpuInfo.memory_used} / {gpuInfo.memory_total} GB
              </div>
            </motion.div>
            
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.8 }}
              className="text-center"
            >
              <div className="text-sm text-gray-400">Utilization</div>
              <div className="text-lg font-semibold text-white">{gpuInfo.utilization}%</div>
            </motion.div>
          </div>
        </AnimatedCard>

        {/* Auto-open Checkbox */}
        <AnimatedCard delay={0.9} className="mb-8">
          <motion.label
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 1.0 }}
            className="flex items-center gap-3 cursor-pointer"
          >
            <motion.input
              type="checkbox"
              className="w-5 h-5 rounded accent-red-500"
              whileTap={{ scale: 0.9 }}
            />
            <span className="text-white font-medium">Auto-open ComfyUI when ready</span>
          </motion.label>
        </AnimatedCard>

        {/* Action Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 50 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.1, duration: 0.8 }}
          className="grid grid-cols-1 gap-4"
        >
          {!isRunning ? (
            <AnimatedButton
              variant="primary"
              onClick={handleLaunchComfyUI}
              disabled={!selectedUser || isInitializing}
              className="w-full"
            >
              {isInitializing ? 'Initializing...' : 'Launch ComfyUI'}
            </AnimatedButton>
          ) : (
            <>
              <AnimatedButton
                variant="success"
                onClick={handleOpenComfyUI}
                className="w-full"
              >
                Open ComfyUI
              </AnimatedButton>
              
              <div className="grid grid-cols-2 gap-4">
                <AnimatedButton
                  variant="secondary"
                  onClick={() => {/* Restart logic */}}
                  className="w-full"
                >
                  Restart
                </AnimatedButton>
                
                <AnimatedButton
                  variant="secondary"
                  onClick={handleStopComfyUI}
                  className="w-full"
                >
                  Stop
                </AnimatedButton>
              </div>
            </>
          )}
        </motion.div>

        {/* Google Drive Sync Panel */}
        <AnimatedCard delay={1.2} className="mt-8">
          <div className="flex items-center gap-3">
            <svg className="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 2L2 7l10 5 10-5-10-5z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2 17l10 5 10-5M2 12l10 5 10-5" />
            </svg>
            <span className="text-white font-medium">Google Drive Sync</span>
            <StatusIndicator status="ready" className="ml-auto" />
          </div>
        </AnimatedCard>

        {/* Footer */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.5 }}
          className="text-center mt-12 text-gray-400"
        >
          <div className="flex justify-center gap-6 mb-2">
            <a href="https://github.com/comfyanonymous/ComfyUI" className="hover:text-white transition-colors">
              ComfyUI
            </a>
            <a href="https://www.runpod.io/" className="hover:text-white transition-colors">
              RunPod
            </a>
          </div>
          <div className="text-sm">© 2025 Web Group Limited</div>
        </motion.div>
      </div>

      {/* Global Styles */}
      <style jsx global>{`
        @keyframes gradientShift {
          0%, 100% { background-position: 0% 50%; }
          50% { background-position: 100% 50%; }
        }
      `}</style>
    </div>
  );
}