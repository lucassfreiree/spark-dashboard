import { format, formatDistanceToNow, parseISO } from 'date-fns'
import { toZonedTime } from 'date-fns-tz'

const SAO_PAULO_TZ = 'America/Sao_Paulo'

export function formatDateSaoPaulo(date: string | Date, formatString: string = 'PPpp'): string {
  const dateObj = typeof date === 'string' ? parseISO(date) : date
  const zonedDate = toZonedTime(dateObj, SAO_PAULO_TZ)
  return format(zonedDate, formatString)
}

export function formatDistanceToNowSaoPaulo(date: string | Date, options?: { addSuffix?: boolean }): string {
  const dateObj = typeof date === 'string' ? parseISO(date) : date
  const zonedDate = toZonedTime(dateObj, SAO_PAULO_TZ)
  return formatDistanceToNow(zonedDate, options)
}
