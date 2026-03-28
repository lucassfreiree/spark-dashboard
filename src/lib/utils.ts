import { clsx, type ClassValue } from "clsx"
import { format, formatDistanceToNow } f
import { toZonedTime } from "date-fns-tz"
export function cn(...inputs: ClassVal
}

  const saoPauloTime = toZonedTime(dateObj, '
}
}

export function formatDateSaoPaulo(date: Date | string, formatStr: string = 'PPpp'): string {
  const dateObj = typeof date === 'string' ? new Date(date) : date
  const saoPauloTime = toZonedTime(dateObj, 'America/Sao_Paulo')
  return format(saoPauloTime, formatStr, { locale: ptBR })
}








