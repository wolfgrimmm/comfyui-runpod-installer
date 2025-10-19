'use client';

import { motion, useAnimation, useInView } from 'framer-motion';
import { useRef, useEffect } from 'react';

interface AnimatedButtonProps {
  children: React.ReactNode;
  onClick?: () => void;
  variant?: 'primary' | 'secondary' | 'success';
  disabled?: boolean;
  className?: string;
}

export const AnimatedButton = ({ 
  children, 
  onClick, 
  variant = 'primary', 
  disabled = false,
  className = ''
}: AnimatedButtonProps) => {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true });
  const controls = useAnimation();

  useEffect(() => {
    if (isInView) {
      controls.start('visible');
    }
  }, [isInView, controls]);

  const variants = {
    hidden: { 
      opacity: 0, 
      y: 50, 
      scale: 0.8,
      rotateX: -15
    },
    visible: { 
      opacity: 1, 
      y: 0, 
      scale: 1,
      rotateX: 0,
      transition: {
        type: 'spring',
        stiffness: 100,
        damping: 15,
        duration: 0.6
      }
    },
    hover: {
      scale: 1.05,
      y: -5,
      rotateX: 5,
      transition: {
        type: 'spring',
        stiffness: 400,
        damping: 10
      }
    },
    tap: {
      scale: 0.95,
      y: 0,
      transition: {
        type: 'spring',
        stiffness: 600,
        damping: 15
      }
    }
  };

  const getVariantStyles = () => {
    switch (variant) {
      case 'primary':
        return 'bg-gradient-to-r from-red-500 to-red-600 hover:from-red-400 hover:to-red-500 text-white shadow-lg shadow-red-500/25';
      case 'secondary':
        return 'bg-gradient-to-r from-gray-600 to-gray-700 hover:from-gray-500 hover:to-gray-600 text-white shadow-lg shadow-gray-500/25';
      case 'success':
        return 'bg-gradient-to-r from-green-500 to-green-600 hover:from-green-400 hover:to-green-500 text-white shadow-lg shadow-green-500/25';
      default:
        return 'bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-400 hover:to-blue-500 text-white shadow-lg shadow-blue-500/25';
    }
  };

  return (
    <motion.button
      ref={ref}
      initial="hidden"
      animate={controls}
      whileHover={!disabled ? "hover" : {}}
      whileTap={!disabled ? "tap" : {}}
      variants={variants}
      onClick={onClick}
      disabled={disabled}
      className={`
        relative px-8 py-4 rounded-2xl font-semibold text-lg
        transform-gpu will-change-transform
        ${getVariantStyles()}
        ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
        ${className}
      `}
      style={{
        perspective: '1000px',
        transformStyle: 'preserve-3d'
      }}
    >
      {/* Glass overlay effect */}
      <motion.div
        className="absolute inset-0 rounded-2xl bg-gradient-to-r from-white/20 to-transparent"
        initial={{ opacity: 0 }}
        whileHover={{ opacity: 1 }}
        transition={{ duration: 0.2 }}
      />
      
      {/* Content */}
      <motion.span
        className="relative z-10"
        style={{ transform: 'translateZ(20px)' }}
      >
        {children}
      </motion.span>
      
      {/* Ripple effect */}
      <motion.div
        className="absolute inset-0 rounded-2xl bg-white/30"
        initial={{ scale: 0, opacity: 0 }}
        whileTap={{ 
          scale: 1, 
          opacity: [0, 0.3, 0],
          transition: { duration: 0.4 }
        }}
      />
    </motion.button>
  );
};

interface AnimatedCardProps {
  children: React.ReactNode;
  delay?: number;
  className?: string;
}

export const AnimatedCard = ({ children, delay = 0, className = '' }: AnimatedCardProps) => {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true });
  const controls = useAnimation();

  useEffect(() => {
    if (isInView) {
      controls.start('visible');
    }
  }, [isInView, controls]);

  return (
    <motion.div
      ref={ref}
      initial="hidden"
      animate={controls}
      whileHover="hover"
      variants={{
        hidden: { 
          opacity: 0, 
          y: 60, 
          scale: 0.9,
          rotateY: -10
        },
        visible: { 
          opacity: 1, 
          y: 0, 
          scale: 1,
          rotateY: 0,
          transition: {
            type: 'spring',
            stiffness: 80,
            damping: 20,
            delay: delay
          }
        },
        hover: {
          y: -10,
          scale: 1.02,
          rotateY: 5,
          transition: {
            type: 'spring',
            stiffness: 300,
            damping: 20
          }
        }
      }}
      className={`
        relative bg-white/10 backdrop-blur-xl border border-white/20
        rounded-2xl p-6 shadow-2xl
        transform-gpu will-change-transform
        ${className}
      `}
      style={{
        perspective: '1000px',
        transformStyle: 'preserve-3d'
      }}
    >
      {/* Glass shine effect */}
      <motion.div
        className="absolute inset-0 rounded-2xl bg-gradient-to-r from-transparent via-white/20 to-transparent"
        initial={{ x: '-100%' }}
        animate={{ x: '100%' }}
        transition={{
          duration: 2,
          repeat: Infinity,
          repeatDelay: 3,
          ease: 'easeInOut'
        }}
      />
      
      {/* Content */}
      <div className="relative z-10">
        {children}
      </div>
    </motion.div>
  );
};

interface AnimatedIconProps {
  children: React.ReactNode;
  onClick?: () => void;
  delay?: number;
  className?: string;
}

export const AnimatedIcon = ({ children, onClick, delay = 0, className = '' }: AnimatedIconProps) => {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true });
  const controls = useAnimation();

  useEffect(() => {
    if (isInView) {
      controls.start('visible');
    }
  }, [isInView, controls]);

  return (
    <motion.button
      ref={ref}
      initial="hidden"
      animate={controls}
      whileHover="hover"
      whileTap="tap"
      onClick={onClick}
      variants={{
        hidden: { 
          opacity: 0, 
          scale: 0,
          rotate: -180
        },
        visible: { 
          opacity: 1, 
          scale: 1,
          rotate: 0,
          transition: {
            type: 'spring',
            stiffness: 200,
            damping: 15,
            delay: delay
          }
        },
        hover: {
          scale: 1.2,
          rotate: 10,
          y: -5,
          transition: {
            type: 'spring',
            stiffness: 400,
            damping: 10
          }
        },
        tap: {
          scale: 0.9,
          transition: {
            type: 'spring',
            stiffness: 600,
            damping: 15
          }
        }
      }}
      className={`
        w-12 h-12 rounded-xl bg-white/20 backdrop-blur-lg
        border border-white/30 flex items-center justify-center
        text-white hover:bg-white/30
        transform-gpu will-change-transform
        ${className}
      `}
    >
      <motion.div
        whileHover={{ rotate: 360 }}
        transition={{ duration: 0.5 }}
      >
        {children}
      </motion.div>
    </motion.button>
  );
};

interface StatusIndicatorProps {
  status: 'inactive' | 'initializing' | 'ready' | 'error';
  className?: string;
}

export const StatusIndicator = ({ status, className = '' }: StatusIndicatorProps) => {
  const getStatusColor = () => {
    switch (status) {
      case 'inactive': return 'bg-gray-500';
      case 'initializing': return 'bg-yellow-500';
      case 'ready': return 'bg-green-500';
      case 'error': return 'bg-red-500';
      default: return 'bg-gray-500';
    }
  };

  const getStatusAnimation = () => {
    switch (status) {
      case 'initializing':
        return {
          scale: [1, 1.2, 1],
          opacity: [0.5, 1, 0.5],
          transition: {
            duration: 1.5,
            repeat: Infinity,
            ease: 'easeInOut'
          }
        };
      case 'ready':
        return {
          scale: [0.8, 1.1, 1],
          opacity: [0, 1, 1],
          transition: {
            duration: 0.6,
            ease: 'easeOut'
          }
        };
      case 'error':
        return {
          scale: [1, 1.3, 1],
          opacity: [1, 0.7, 1],
          transition: {
            duration: 0.3,
            repeat: 3,
            ease: 'easeInOut'
          }
        };
      default:
        return {
          scale: 1,
          opacity: 0.6
        };
    }
  };

  return (
    <motion.div
      className={`w-3 h-3 rounded-full ${getStatusColor()} ${className}`}
      animate={getStatusAnimation()}
    />
  );
};
