'use client';
import { useRive, useStateMachineInput } from '@rive-app/react-canvas';
import { useEffect } from 'react';
import { RIVE_SPECS } from '@/lib/rive-specs';

interface Props {
  isVisible: boolean;
  intensity?: number;
}

export default function CardGlow({ isVisible, intensity = 1.0 }: Props) {
  const spec = RIVE_SPECS.cardGlow;
  
  const { RiveComponent, rive } = useRive({
    src: `/animations/${spec.file}`,
    stateMachines: spec.stateMachine,
    autoplay: false, // Start paused
  });

  const isVisibleInput = useStateMachineInput(rive, spec.stateMachine, 'isVisible');
  const intensityInput = useStateMachineInput(rive, spec.stateMachine, 'intensity');

  useEffect(() => {
    if (isVisibleInput) isVisibleInput.value = isVisible;
  }, [isVisible, isVisibleInput]);

  useEffect(() => {
    if (intensityInput) intensityInput.value = intensity;
  }, [intensity, intensityInput]);

  return (
    <div className="absolute inset-0 pointer-events-none overflow-hidden">
      <RiveComponent className="w-full h-full" />
    </div>
  );
}



