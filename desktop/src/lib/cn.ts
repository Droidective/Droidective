import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

/** Conditional classes, with later Tailwind utilities winning over earlier. */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs))
}
