import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { format as dateFnsFormat, formatDistanceToNow as dateFnsFormatDistanceToNow } from 'date-fns'
import { toZonedTime } from 'date-fns-tz'
import { ptBR } from 'date-fns/locale'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

const SAO_PAULO_TZ = 'America/Sao_Paulo'

export function toSaoPauloTime(date: Date | string): Date {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return toZonedTime(dateObj, SAO_PAULO_TZ)
}

export function formatSaoPauloDate(date: Date | string, formatStr: string = 'dd/MM/yyyy HH:mm'): string {
  const spTime = toSaoPauloTime(date)
  return dateFnsFormat(spTime, formatStr, { locale: ptBR })
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }): string {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return dateFnsFormatDistanceToNow(dateObj, { ...options, locale: ptBR })
}
