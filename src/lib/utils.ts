import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { formatDistanceToNow, format } from "date-fns"
import { toZonedTime } from "date-fns-tz"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return formatDistanceToNow(dateObj, options)
}

export function formatSaoPauloTime(date: Date | string, formatStr: string = 'PPpp') {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTime = toZonedTime(dateObj, 'America/Sao_Paulo')
  return format(saoPauloTime, formatStr)
}











