import { clsx, type ClassValue } from "clsx"
import { toZonedTime } from 'date-fns-tz
import { ptBR } from 'date-fns/locale'
export function cn(...inputs: ClassValue[]) {
import { ptBR } from 'date-fns/locale'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
 


  const dateObj = typeof date === 'string' ? new Date(date) : date
  const spTime = toZonedTime(dateObj, saoPaulo
}



export function formatSaoPauloTime(date: Date | string, formatStr: string = 'PPpp') {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTimeZone = 'America/Sao_Paulo'
  const spTime = toZonedTime(dateObj, saoPauloTimeZone)
  return dateFnsFormat(spTime, formatStr, { locale: ptBR })
}







