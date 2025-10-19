'use client';
import { useEffect } from 'react';

type StatusType = 'idle' | 'loading' | 'ready' | 'error';

interface Props {
  status: StatusType;
  label?: string;
}

const STATUS_MAP: Record<StatusType, number> = {
  idle: 0,
  loading: 1,
  ready: 2,
  error: 3,
};

const STATUS_COLORS: Record<StatusType, string> = {
  idle: 'bg-gray-500',
  loading: 'bg-blue-500',
  ready: 'bg-green-500',
  error: 'bg-red-500',
};

const STATUS_ANIMATIONS: Record<StatusType, string> = {
  idle: '',
  loading: 'animate-status-pulse',
  ready: 'animate-glow-pulse',
  error: 'animate-status-shake',
};

export default function StatusDot({ status, label }: Props) {

  return (
    <div className="flex items-center gap-2">
      <div className="relative w-6 h-6">
        {/* Stunning CSS animation */}
        <div className={`w-full h-full rounded-full ${STATUS_COLORS[status]} ${STATUS_ANIMATIONS[status]}
          transform-gpu will-change-transform`}>
          {/* Glow effect for ready/error states */}
          {(status === 'ready' || status === 'error') && (
            <div className={`absolute inset-0 rounded-full ${STATUS_COLORS[status]} opacity-30 
              animate-glow-pulse blur-sm scale-150`} />
          )}
        </div>
      </div>
      {label && (
        <span className="text-sm text-gray-300">{label}</span>
      )}
    </div>
  );
}



