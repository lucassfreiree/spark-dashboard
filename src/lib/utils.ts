import { clsx, type ClassValue } from "clsx"
import { toZonedTime, formatInTimeZone }
import { toZonedTime, formatInTimeZone } from "date-fns-tz"
import { formatDistanceToNow } from "date-fns"
export function cn(...inputs: ClassVal

export function formatDistanceToNowSaoPaulo(d
  const dateObj = typeof date 
 

  const saoPaulo = 'America/Sao_Paulo'
  return formatInTimeZone(dateObj, sao





export function formatSaoPauloTime(date: Date | string, formatStr: string = 'dd/MM/yyyy HH:mm:ss') {
  const saoPaulo = 'America/Sao_Paulo'
  const dateObj = typeof date === 'string' ? new Date(date) : date
  return formatInTimeZone(dateObj, saoPaulo, formatStr)
}