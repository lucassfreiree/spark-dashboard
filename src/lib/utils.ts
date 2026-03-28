import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { formatDistanceToNow, format } from "date-fns"
import { toZonedTime } from "date-fns-tz"
import { ptBR } from "date-fns/locale"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | number | string, options?: { addSuffix?: boolean }) {
  const saoPauloTz = "America/Sao_Paulo"
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const zonedDate = toZonedTime(dateObj, saoPauloTz)
  return formatDistanceToNow(zonedDate, { ...options, locale: ptBR })
}

export function formatDateSaoPaulo(date: Date | number | string, formatStr: string = "dd/MM/yyyy HH:mm:ss") {
  const saoPauloTz = "America/Sao_Paulo"
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const zonedDate = toZonedTime(dateObj, saoPauloTz)
  return format(zonedDate, formatStr, { locale: ptBR })
}









