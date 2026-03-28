import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { toZonedTime } from "date-fns-tz"
import { formatDistanceToNow, format } from "date-fns"
import { ptBR } from "date-fns/locale"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTimeZone = 'America/Sao_Paulo'
  const spTime = toZonedTime(dateObj, saoPauloTimeZone)
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
}

export function formatSaoPauloTime(date: Date | string, formatString: string = 'PPpp') {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTimeZone = 'America/Sao_Paulo'
  const spTime = toZonedTime(dateObj, saoPauloTimeZone)
  return format(spTime, formatString, { locale: ptBR })
}


