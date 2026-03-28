import { clsx, type ClassValue } from "clsx"
import { toZonedTime, formatInTimeZone }
import { ptBR } from "date-fns/locale"
export function cn(...inputs: ClassValue[]) {
}

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const spTime = toZonedTime(dateObj, saoPaulo)
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
}

export function formatSaoPauloTime(date: Date | string, formatStr: string = 'dd/MM/yyyy HH:mm:ss') {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return formatTz(dateObj, formatStr, { timeZone: saoPaulo })
}


export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const spTime = toZonedTime(dateObj, saoPaulo)
  return formatDistanceToNow(spTime, { ...options, locale: ptBR })
}

export function formatSaoPauloTime(date: Date | string, formatStr: string = 'dd/MM/yyyy HH:mm:ss') {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return formatInTimeZone(dateObj, saoPaulo, formatStr)
}
