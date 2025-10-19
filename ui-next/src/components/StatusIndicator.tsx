'use client';

import { motion } from 'framer-motion';

type StatusType = 'idle' | 'loading' | 'ready' | 'error';

interface Props {
  status: StatusType;
  label?: string;
}

const statusConfig = {
  idle: {
    color: 'bg-gray-500',
    glow: 'shadow-gray-500/50',
    animation: '',
  },
  loading: {
    color: 'bg-blue-500',
    glow: 'shadow-blue-500/50',
    animation: 'animate-pulse',
  },
  ready: {
    color: 'bg-green-500',
    glow: 'shadow-green-500/50',
    animation: 'animate-pulse',
  },
  error: {
    color: 'bg-red-500',
    glow: 'shadow-red-500/50',
    animation: 'animate-bounce',
  },
};

export default function StatusIndicator({ status, label }: Props) {
  const config = statusConfig[status];

  return (
    <motion.div
      className="flex items-center gap-3"
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ type: 'spring', stiffness: 100, damping: 15 }}
    >
      <div className="relative w-8 h-8 gpu-accelerated">
        {/* Main dot */}
        <motion.div
          className={`absolute inset-0 rounded-full ${config.color} ${config.animation}`}
          animate={{
            scale: status === 'loading' ? [1, 1.2, 1] : 1,
          }}
          transition={{
            duration: 1.5,
            repeat: status === 'loading' ? Infinity : 0,
            ease: 'easeInOut',
          }}
        />

        {/* Glow effect */}
        <motion.div
          className={`absolute inset-0 rounded-full ${config.color} blur-md opacity-60`}
          animate={{
            scale: [1, 1.5, 1],
            opacity: [0.6, 0.3, 0.6],
          }}
          transition={{
            duration: 2,
            repeat: Infinity,
            ease: 'easeInOut',
          }}
        />

        {/* Pulse rings */}
        {(status === 'ready' || status === 'loading') && (
          <>
            <motion.div
              className={`absolute inset-0 rounded-full border-2 ${config.color.replace('bg-', 'border-')}`}
              animate={{
                scale: [1, 2],
                opacity: [0.5, 0],
              }}
              transition={{
                duration: 2,
                repeat: Infinity,
                ease: 'easeOut',
              }}
            />
            <motion.div
              className={`absolute inset-0 rounded-full border-2 ${config.color.replace('bg-', 'border-')}`}
              animate={{
                scale: [1, 2],
                opacity: [0.5, 0],
              }}
              transition={{
                duration: 2,
                repeat: Infinity,
                ease: 'easeOut',
                delay: 1,
              }}
            />
          </>
        )}
      </div>

      {label && (
        <motion.span
          className="text-sm font-medium text-white/90"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.2 }}
        >
          {label}
        </motion.span>
      )}
    </motion.div>
  );
}

