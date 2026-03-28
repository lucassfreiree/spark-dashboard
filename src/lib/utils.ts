import { clsx, type ClassValue } from "clsx"
import { formatDistanceToNow, format } f
import { formatDistanceToNow, format } from "date-fns"
import { toZonedTime } from "date-fns-tz"

export function formatDistanceToNowSaoPaulo(d
  return formatDistanceToNow(d


  return format(saoPauloTime, formatStr)




export function formatSaoPauloTime(date: Date | string, formatStr: string = 'PPpp') {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTime = toZonedTime(dateObj, 'America/Sao_Paulo')
  return format(saoPauloTime, formatStr)
}
