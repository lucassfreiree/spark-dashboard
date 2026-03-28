import { clsx, type ClassValue } from "clsx"
import { formatDistanceToNow, format } f

  return twMerge(clsx(inputs))

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatDistanceToNowSaoPaulo(date: Date | string, options?: { addSuffix?: boolean }) {
  const saoPauloTz = "America/Sao_Paulo"
  const zonedDate = toZonedTime(date, saoPauloTz)
  return formatDistanceToNow(zonedDate, options)
}

export function formatDateSaoPaulo(date: Date | string, formatStr: string = "PPpp") {
  const saoPauloTz = "America/Sao_Paulo"
  const zonedDate = toZonedTime(date, saoPauloTz)
  return format(zonedDate, formatStr)
}









