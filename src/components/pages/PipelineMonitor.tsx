import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { CheckCircle, Circle, Spinner, XCircle, ArrowRight } from '@phosphor-icons/react'
import { cn } from '@/lib/utils'

interface Props {
  data: DashboardState
}

const DEFAULT_STAGES = [
  { name: 'Setup', desc: 'Read workspace config' },
  { name: 'Session Guard', desc: 'Acquire multi-agent lock' },
  { name: 'Apply & Push', desc: 'Clone, apply patches, push' },
  { name: 'CI Gate', desc: 'Wait corporate CI (Esteira Build NPM)' },
  { name: 'Promote', desc: 'Update CAP values.yaml image tag' },
  { name: 'Save State', desc: 'Record on autopilot-state' },
  { name: 'Audit', desc: 'Audit trail + release lock' },
]

function stageStatus(pipelineStatus: string, idx: number, total: number) {
  if (pipelineStatus === 'idle' || pipelineStatus === 'unknown') return 'pending'
  if (pipelineStatus === 'success' || pipelineStatus === 'completed') return 'success'
  if (pipelineStatus === 'failure' || pipelineStatus === 'failed') return idx < total - 1 ? 'success' : 'failed'
  if (pipelineStatus === 'running' || pipelineStatus === 'in_progress') {
    if (idx < 3) return 'success'
    if (idx === 3) return 'running'
    return 'pending'
  }
  return 'pending'
}

function StageIcon({ status }: { status: string }) {
  if (status === 'success') return <CheckCircle className="w-5 h-5 text-success" weight="fill" />
  if (status === 'failed') return <XCircle className="w-5 h-5 text-destructive" weight="fill" />
  if (status === 'running') return <Spinner className="w-5 h-5 text-warning animate-spin" />
  return <Circle className="w-5 h-5 text-muted-foreground" />
}

export function PipelineMonitor({ data }: Props) {
  const pipeline = data.pipeline
  const stages = data.pipelineStages?.length ? data.pipelineStages : DEFAULT_STAGES
  const ps = pipeline?.status || 'idle'

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>apply-source-change Pipeline</span>
            <StatusBadge status={ps} className="text-base" />
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col lg:flex-row items-start lg:items-center gap-4 lg:gap-2 overflow-x-auto pb-4">
            {stages.map((stage, idx) => {
              const status = stageStatus(ps, idx, stages.length)
              return (
                <div key={stage.name} className="flex items-center gap-2 w-full lg:w-auto">
                  <div className={cn(
                    "flex-1 lg:flex-initial p-4 rounded-lg border-2 transition-all min-w-[180px]",
                    status === 'success' && "bg-success/10 border-success/40",
                    status === 'failed' && "bg-destructive/10 border-destructive/40",
                    status === 'running' && "bg-warning/10 border-warning/40 animate-pulse",
                    status === 'pending' && "bg-muted/30 border-border",
                  )}>
                    <div className="flex items-center gap-2 mb-1">
                      <StageIcon status={status} />
                      <span className="font-semibold text-sm">{stage.name}</span>
                    </div>
                    <div className="text-xs text-muted-foreground">{stage.desc}</div>
                  </div>
                  {idx < stages.length - 1 && (
                    <ArrowRight className="hidden lg:block w-5 h-5 text-muted-foreground flex-shrink-0" />
                  )}
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Pipeline Details</CardTitle></CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <div className="p-3 rounded bg-muted/30">
              <div className="text-xs text-muted-foreground">Component</div>
              <div className="font-mono font-bold">{pipeline?.component || '?'}</div>
            </div>
            <div className="p-3 rounded bg-muted/30">
              <div className="text-xs text-muted-foreground">Version</div>
              <div className="font-mono font-bold">{pipeline?.version || '?'}</div>
            </div>
            <div className="p-3 rounded bg-muted/30">
              <div className="text-xs text-muted-foreground">Run #</div>
              <div className="font-mono font-bold">{pipeline?.lastRun || 0}</div>
            </div>
            <div className="p-3 rounded bg-muted/30">
              <div className="text-xs text-muted-foreground">Workspace</div>
              <div className="font-mono font-bold text-xs">{pipeline?.workspace || '?'}</div>
            </div>
          </div>
          {pipeline?.commitMessage && (
            <div className="mt-4 p-3 rounded bg-muted/30 text-sm">
              <span className="text-muted-foreground">Commit: </span>
              <span className="font-mono">{pipeline.commitMessage}</span>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
