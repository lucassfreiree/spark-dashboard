import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { toZonedTime } from "date-fns-tz"

  return twMerge(clsx(inputs))

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTimeZone = 'America/Sao_Paulo'
  const spTime = toZonedTime(dateObj, saoPauloTimeZone)
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
} const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTimeZone = 'America/Sao_Paulo'
oTimeZone)
String, { locale: ptBR })




}







