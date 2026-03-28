import { DashboardState } from '@/types/dashboard'
import { StatusBadge } from '@/components/StatusBadge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowRight } from '@phosphor-icons/react'
import { cn, formatDateSaoPaulo } from '@/lib/utils'

interface PipelineMonitorProps {
  data: DashboardState
}

export function PipelineMonitor({ data }: PipelineMonitorProps) {
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Deploy Pipeline Stages</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col lg:flex-row items-start lg:items-center gap-4 lg:gap-2 overflow-x-auto pb-4">
            {data.pipeline.stages.map((stage, idx) => (
              <div key={stage.name} className="flex items-center gap-2 w-full lg:w-auto">
                <div className={cn(
                  "flex-1 lg:flex-initial p-4 rounded-lg border-2 transition-all min-w-[180px]",
                  stage.status === 'success' && "bg-success/10 border-success/40",
                  stage.status === 'failed' && "bg-destructive/10 border-destructive/40",
                  stage.status === 'running' && "bg-warning/10 border-warning/40 animate-pulse-glow",
                  stage.status === 'idle' && "bg-muted/30 border-border",
                  data.pipeline.currentStage === stage.name && "ring-2 ring-primary ring-offset-2 ring-offset-background"
                )}>
                  <div className="font-semibold text-sm mb-2">{stage.name}</div>
                  <StatusBadge status={stage.status} className="mb-2" />
                  {stage.duration && (
                    <div className="text-xs font-mono text-muted-foreground">{stage.duration}</div>
                  )}
                </div>
                {idx < data.pipeline.stages.length - 1 && (
                  <ArrowRight className="hidden lg:block w-5 h-5 text-muted-foreground flex-shrink-0" />
                )}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-6 md:grid-cols-2">
        {data.pipeline.stages.map((stage) => (
          <Card key={stage.name}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle className="text-base">{stage.name}</CardTitle>
                <StatusBadge status={stage.status} />
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-2 text-sm">
                {stage.startTime && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Iniciado:</span>
                    <span className="font-mono">{formatDateSaoPaulo(stage.startTime, 'HH:mm:ss')}</span>
                  </div>
                )}
                {stage.endTime && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Finalizado:</span>
                    <span className="font-mono">{formatDateSaoPaulo(stage.endTime, 'HH:mm:ss')}</span>
                  </div>
                )}
                {stage.duration && (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Duração:</span>
                    <span className="font-mono font-semibold">{stage.duration}</span>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
