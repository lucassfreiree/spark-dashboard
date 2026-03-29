import { Badge } from '@/components/ui/badge'
import { CheckCircle, XCircle, Clock, MinusCircle } from '@phosphor-icons/react'
import { cn } from '@/lib/utils'

interface StatusBadgeProps {
  status: string
  className?: string
}

export function StatusBadge({ status, className }: StatusBadgeProps) {
  const successConfig = {
    icon: CheckCircle,
    label: 'Success',
    className: 'bg-success/20 text-success-foreground border-success/40'
  }
  const failedConfig = {
    icon: XCircle,
    label: 'Failed',
    className: 'bg-destructive/20 text-destructive-foreground border-destructive/40'
  }
  const runningConfig = {
    icon: Clock,
    label: 'Running',
    className: 'bg-warning/20 text-warning-foreground border-warning/40 animate-pulse-glow'
  }
  const idleConfig = {
    icon: MinusCircle,
    label: 'Idle',
    className: 'bg-idle/20 text-idle-foreground border-idle/40'
  }

  const configs: Record<string, typeof successConfig> = {
    success: successConfig,
    completed: successConfig,
    failed: failedConfig,
    failure: failedConfig,
    running: runningConfig,
    in_progress: runningConfig,
    idle: idleConfig
  }

  const config = configs[status] ?? {
    icon: MinusCircle,
    label: status,
    className: 'bg-muted/20 text-muted-foreground border-muted/40'
  }
  const Icon = config.icon

  return (
    <Badge variant="outline" className={cn(config.className, className)}>
      <Icon className="w-3 h-3 mr-1" weight="fill" />
      {config.label}
    </Badge>
  )
}
