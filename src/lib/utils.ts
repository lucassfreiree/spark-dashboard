import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { formatDistanceToNow, format as d

  return twMerge(clsx(inputs))

  const dateObj = typeof date === 'string' ? 
  const spTime = toZonedTime(d
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTimeZone = 'America/Sao_Paulo'
  const spTime = toZonedTime(dateObj, saoPauloTimeZone)
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
}







