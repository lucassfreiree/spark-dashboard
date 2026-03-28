import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { format, formatDistanceToNow } from "date-fns"
import { ptBR } from "date-fns/locale"



  const dateObj = typeof date 
 

  const dateObj = typeof date === 'string' ? new Date(date) : date
  return format(saoPauloTime, formatStr, { locale: ptBR })




export function formatDateSaoPaulo(date: Date | string, formatStr: string = 'PPpp'): string {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTime = toZonedTime(dateObj, 'America/Sao_Paulo')
  return format(saoPauloTime, formatStr, { locale: ptBR })
}


