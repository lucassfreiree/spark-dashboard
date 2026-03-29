import { Badge } from '@/components/ui/badge'
import { CheckCircle, XCircle, Clock, MinusCircle } from '@phosphor-icons/react'
import { cn } from '@/lib/utils'

interface StatusBadgeProps {
  status: string
  className?: string
}

const configs: Record<string, { icon: typeof CheckCircle; label: string; className: string }> = {
  success: { icon: CheckCircle, label: 'Success', className: 'bg-success/20 text-success-foreground border-success/40' },
  completed: { icon: CheckCircle, label: 'Success', className: 'bg-success/20 text-success-foreground border-success/40' },
  failed: { icon: XCircle, label: 'Failed', className: 'bg-destructive/20 text-destructive-foreground border-destructive/40' },
  failure: { icon: XCircle, label: 'Failed', className: 'bg-destructive/20 text-destructive-foreground border-destructive/40' },
  error: { icon: XCircle, label: 'Error', className: 'bg-destructive/20 text-destructive-foreground border-destructive/40' },
  running: { icon: Clock, label: 'Running', className: 'bg-warning/20 text-warning-foreground border-warning/40 animate-pulse-glow' },
  in_progress: { icon: Clock, label: 'Running', className: 'bg-warning/20 text-warning-foreground border-warning/40 animate-pulse-glow' },
  queued: { icon: Clock, label: 'Queued', className: 'bg-warning/20 text-warning-foreground border-warning/40' },
  active: { icon: CheckCircle, label: 'Active', className: 'bg-success/20 text-success-foreground border-success/40' },
  idle: { icon: MinusCircle, label: 'Idle', className: 'bg-idle/20 text-idle-foreground border-idle/40' },
  unknown: { icon: MinusCircle, label: 'Unknown', className: 'bg-idle/20 text-idle-foreground border-idle/40' },
  setup: { icon: Clock, label: 'Setup', className: 'bg-warning/20 text-warning-foreground border-warning/40' },
  locked: { icon: XCircle, label: 'Locked', className: 'bg-destructive/20 text-destructive-foreground border-destructive/40' },
}

const fallback = { icon: MinusCircle, label: '', className: 'bg-idle/20 text-idle-foreground border-idle/40' }

export function StatusBadge({ status, className }: StatusBadgeProps) {
  const config = configs[status] ?? { ...fallback, label: status }
  const Icon = config.icon

  return (
    <Badge variant="outline" className={cn(config.className, className)}>
      <Icon className="w-3 h-3 mr-1" weight="fill" />
      {config.label}
    </Badge>
  )
}
