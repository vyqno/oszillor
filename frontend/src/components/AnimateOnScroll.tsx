"use client";

import { useRef } from "react";
import { motion, useInView } from "framer-motion";

type Animation = "fadeUp" | "fadeLeft" | "fadeRight" | "scale";

function getVariants(animation: Animation) {
  switch (animation) {
    case "fadeUp":
      return { hidden: { opacity: 0, y: 40 }, visible: { opacity: 1, y: 0 } };
    case "fadeLeft":
      return { hidden: { opacity: 0, x: -40 }, visible: { opacity: 1, x: 0 } };
    case "fadeRight":
      return { hidden: { opacity: 0, x: 40 }, visible: { opacity: 1, x: 0 } };
    case "scale":
      return { hidden: { opacity: 0, scale: 0.9 }, visible: { opacity: 1, scale: 1 } };
  }
}

interface Props {
  children: React.ReactNode;
  animation?: Animation;
  delay?: number;
  duration?: number;
  threshold?: number;
  className?: string;
}

export function AnimateOnScroll({
  children,
  animation = "fadeUp",
  delay = 0,
  duration = 0.6,
  threshold = 0.15,
  className,
}: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, amount: threshold });
  const { hidden, visible } = getVariants(animation);

  return (
    <motion.div
      ref={ref}
      variants={{ hidden, visible }}
      initial="hidden"
      animate={inView ? "visible" : "hidden"}
      transition={{ duration, delay, ease: [0.25, 0.1, 0.25, 1] }}
      className={className}
    >
      {children}
    </motion.div>
  );
}
