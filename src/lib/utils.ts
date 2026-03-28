import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { toZonedTime } from "date-fns-tz"

  return twMerge(clsx(inputs))

  const saoPaulo = 'America/Sao_Paulo'
  const spTime = toZonedTime(d
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const spTime = toZonedTime(dateObj, saoPaulo)
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
}
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
}
