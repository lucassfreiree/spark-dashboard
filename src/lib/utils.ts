import { clsx, type ClassValue } from "clsx"
import { toZonedTime, formatInTimeZone } from "date-fns-tz"
import { formatDistanceToNow } from "date-fns"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const zonedDate = toZonedTime(dateObj, saoPaulo)
}
export function formatSaoPauloTime(date: Date | st
  const dateObj = typeof date === 'string' ? new
}





