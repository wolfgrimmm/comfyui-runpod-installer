'use client';

import { useEffect, useRef } from 'react';
import Lottie, { LottieRefCurrentProps } from 'lottie-react';
import statusAnimation from '@/public/animations/status-dot.json';

interface Props {
  status: 'idle' | 'loading' | 'ready' | 'error';
  label: string;
}

export default function LottieStatus({ status, label }: Props) {
  const lottieRef = useRef<LottieRefCurrentProps>(null);

  useEffect(() => {
    if (lottieRef.current) {
      // Play animation for active states
      if (status === 'loading' || status === 'ready') {
        lottieRef.current.play();
      } else {
        lottieRef.current.stop();
      }
    }
  }, [status]);

  const statusColors = {
    idle: '#666666',
    loading: '#f59e0b',
    ready: '#10b981',
    error: '#ef4444',
  };

  const statusStyles = {
    idle: 'opacity-50',
    loading: 'animate-pulse',
    ready: '',
    error: '',
  };

  return (
    <div className={`flex items-center gap-3 ${statusStyles[status]}`}>
      {/* Lottie Status Dot */}
      <div 
        className="relative w-10 h-10"
        style={{ 
          filter: `drop-shadow(0 0 10px ${statusColors[status]})`,
        }}
      >
        <Lottie
          lottieRef={lottieRef}
          animationData={statusAnimation}
          loop={status === 'loading' || status === 'ready'}
          autoplay={status === 'loading' || status === 'ready'}
          style={{
            width: '100%',
            height: '100%',
          }}
        />
        {/* Color overlay */}
        <div 
          className="absolute inset-0 rounded-full mix-blend-color"
          style={{ 
            backgroundColor: statusColors[status],
            opacity: 0.8,
          }}
        />
      </div>

      {/* Status Text */}
      <span className="font-medium text-white">{label}</span>
    </div>
  );
}

