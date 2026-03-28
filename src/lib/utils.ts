import { clsx, type ClassValue } from "clsx"
import { ptBR } from "date-fns/locale"
import { ptBR } from "date-fns/locale"
import { toZonedTime } from "date-fns-tz"


  const dateObj = typ
 

  const dateObj = typeof date === 'string' ? new Date(date) : date
  return format(saoPauloTime, formatStr, { locale: ptBR })




export function formatDateSaoPaulo(date: Date | string, formatStr: string = 'PPpp') {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTime = toZonedTime(dateObj, 'America/Sao_Paulo')
  return format(saoPauloTime, formatStr, { locale: ptBR })
}

export { formatDateSaoPaulo as formatSaoPauloTime }

