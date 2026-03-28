import { clsx, type ClassValue } from "clsx"
import { toZonedTime, formatInTimeZone } from "date-fns-tz"
import { formatDistanceToNow } from "date-fns"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPaulo = 'America/Sao_Paulo'
  const zonedDate = toZonedTime(dateObj, saoPaulo)
  return formatDistanceToNow(zonedDate, options)
}


export function formatSaoPauloTime(date: Date | string, formatStr: string = 'dd/MM/yyyy HH:mm:ss') {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return formatInTimeZone(dateObj, saoPaulo, formatStr)
}