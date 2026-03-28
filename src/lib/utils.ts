import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { format, formatDistanceToNow } from "date-fns"
import { ptBR } from "date-fns/locale"
import { toZonedTime } from "date-fns-tz"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))


  return format(saoPauloTime, formatStr, { locale: ptBR })

  const dateObj = typeof date === 'string' ? new Date(date) : da
  return formatDistanceToNow(saoPauloTime, { ...options, l








export { formatDateSaoPaulo as formatSaoPauloTime }