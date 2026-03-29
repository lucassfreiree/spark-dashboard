import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { CheckCircle, Circle, Spinner, XCircle } from '@phosphor-icons/react'

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
      {/* Pipeline Info */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>apply-source-change Pipeline</span>
            <StatusBadge status={ps} className="text-base" />
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-4 text-sm mb-6 p-3 rounded-lg bg-muted/30">
            <span><strong>Run:</strong> #{pipeline?.lastRun || 0}</span>
            <span><strong>Component:</strong> {pipeline?.component || '?'}</span>
            <span><strong>Version:</strong> v{pipeline?.version || '?'}</span>
            {pipeline?.changesCount != null && <span><strong>Files:</strong> {pipeline.changesCount}</span>}
            <span><strong>Workspace:</strong> {pipeline?.workspace || '?'}</span>
          </div>
          {pipeline?.commitMessage && (
            <div className="text-sm text-muted-foreground mb-6">Commit: {pipeline.commitMessage}</div>
          )}

          {/* 7 Stages */}
          <div className="relative">
            <div className="absolute left-[11px] top-8 bottom-4 w-0.5 bg-border" />
            <div className="space-y-1">
              {stages.map((stage, i) => {
                const ss = stageStatus(ps, i, stages.length)
                return (
                  <div key={i} className="flex items-start gap-4 py-2 relative">
                    <div className="z-10 bg-background"><StageIcon status={ss} /></div>
                    <div>
                      <div className="font-semibold text-sm">{i <= 1 ? ['1', '1.5'][i] : i}. {stage.name}</div>
                      <div className="text-xs text-muted-foreground">{stage.desc}</div>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* CI Monitor */}
      {data.ciMonitor?.ciOutcome && (
        <Card>
          <CardHeader><CardTitle>Corporate CI Result</CardTitle></CardHeader>
          <CardContent>
            <div className="flex items-center gap-2">
              <StatusBadge status={data.ciMonitor.ciOutcome} />
              <span className="text-sm text-muted-foreground">
                {data.ciMonitor.component} | SHA: <code className="text-xs">{data.ciMonitor.commitSha?.slice(0, 8)}</code>
              </span>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Version Rules */}
      {data.versionRules && (
        <Card>
          <CardHeader><CardTitle>Version Rules</CardTitle></CardHeader>
          <CardContent>
            <div className="grid gap-2 text-sm">
              <div className="flex justify-between"><span className="text-muted-foreground">Controller</span><span className="font-mono font-bold">{data.versionRules.currentController}</span></div>
              <div className="flex justify-between"><span className="text-muted-foreground">Agent</span><span className="font-mono font-bold">{data.versionRules.currentAgent}</span></div>
              <div className="flex justify-between"><span className="text-muted-foreground">Last trigger</span><span>#{data.versionRules.lastTriggerRun}</span></div>
              <div className="flex justify-between"><span className="text-muted-foreground">Last success</span><span>#{data.versionRules.lastSuccessfulRun}</span></div>
              <div className="flex justify-between"><span className="text-muted-foreground">Rule</span><span className="text-xs">{data.versionRules.pattern}</span></div>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
