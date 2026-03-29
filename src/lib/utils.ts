import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { formatDistanceToNow, format } from "date-fns"
import { toZonedTime, formatInTimeZone } from "date-fns-tz"
import { ptBR } from "date-fns/locale"

const SAO_PAULO_TZ = "America/Sao_Paulo"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function convertToSaoPauloTime(date: Date | number | string): Date {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return toZonedTime(dateObj, SAO_PAULO_TZ)
}

export function formatDistanceToNowSaoPaulo(date: Date | number | string, options?: any) {
  const saoPauloDate = convertToSaoPauloTime(date)
  const now = convertToSaoPauloTime(new Date())
  return formatDistanceToNow(saoPauloDate, { ...options, locale: ptBR })
}

export function formatDateSaoPaulo(date: Date | number | string, formatStr: string = "dd/MM/yyyy HH:mm:ss") {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return formatInTimeZone(dateObj, SAO_PAULO_TZ, formatStr, { locale: ptBR })
}
