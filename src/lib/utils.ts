import { clsx, type ClassValue } from "clsx"
import { formatDistanceToNow, format } f
import { ptBR } from "date-fns/locale"
export function cn(...inputs: ClassValue[
import { ptBR } from "date-fns/locale"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
 


  const saoPauloTz = "America/Sao_Paulo"
  const zonedDate = toZonedTime(dateObj, saoPaulo
}


export function formatDateSaoPaulo(date: Date | number, formatStr: string = "dd/MM/yyyy HH:mm:ss") {
  const saoPauloTz = "America/Sao_Paulo"
  const zonedDate = toZonedTime(date, saoPauloTz)
  return format(zonedDate, formatStr, { locale: ptBR })
}





