import { Badge } from '@/components/ui/badge'
import { DeployStatus } from '@/types/dashboard'
import { CheckCircle, XCircle, Clock, MinusCircle } from '@phosphor-icons/react'
import { cn } from '@/lib/utils'

interface StatusBadgeProps {
  status: DeployStatus
  className?: string
}

export function StatusBadge({ status, className }: StatusBadgeProps) {
  const configs = {
    success: {
      icon: CheckCircle,
      label: 'Success',
      className: 'bg-success/20 text-success-foreground border-success/40'
    },
    failed: {
      icon: XCircle,
      label: 'Failed',
      className: 'bg-destructive/20 text-destructive-foreground border-destructive/40'
    },
    running: {
      icon: Clock,
      label: 'Running',
      className: 'bg-warning/20 text-warning-foreground border-warning/40 animate-pulse-glow'
    },
    idle: {
      icon: MinusCircle,
      label: 'Idle',
      className: 'bg-idle/20 text-idle-foreground border-idle/40'
    }
  }

  const config = configs[status]
  const Icon = config.icon

  return (
    <Badge variant="outline" className={cn(config.className, className)}>
      <Icon className="w-3 h-3 mr-1" weight="fill" />
      {config.label}
    </Badge>
  )
}
