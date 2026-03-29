import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { MetricCard } from '@/components/MetricCard'
import { Package, Robot, GitBranch, Pulse, Lock, Warning, CheckCircle, NumberCircleOne } from '@phosphor-icons/react'
import { useMemo } from 'react'
import { formatDistanceToNowSaoPaulo } from '@/lib/timezone'

interface Props {
  data: DashboardState
}

function computeHealth(data: DashboardState) {
  let score = 100
  const reasons: string[] = []
  const c = data.controller
  const a = data.agent
  const p = data.pipeline

  if (c?.ciResult === 'failure') { score -= 20; reasons.push('Controller CI failed (-20)') }
  if (a?.ciResult === 'failure') { score -= 20; reasons.push('Agent CI failed (-20)') }
  if (p?.status === 'failure' || p?.status === 'failed') { score -= 15; reasons.push('Pipeline failed (-15)') }
  if (c?.promoted === false && c?.status === 'success') { score -= 10; reasons.push('Controller not promoted (-10)') }
  if (data.corporateReal?.controller?.drift) { score -= 25; reasons.push('CONTROLLER DRIFT (-25)') }
  if (data.corporateReal?.agent?.drift) { score -= 25; reasons.push('AGENT DRIFT (-25)') }

  if (data.lastSync) {
    const age = (Date.now() - new Date(data.lastSync).getTime()) / 60000
    if (age > 30) { score -= 10; reasons.push('Sync stale >30min (-10)') }
  }

  const lock = data.sessionLock
  if (lock?.agentId && lock.agentId !== 'none' && lock.expiresAt) {
    if (new Date(lock.expiresAt) <= new Date()) { score -= 5; reasons.push('Expired lock (-5)') }
  }

  return { score: Math.max(0, Math.min(100, score)), reasons }
}

export function DashboardOverview({ data }: Props) {
  const health = useMemo(() => computeHealth(data), [data])
  const healthColor = health.score >= 80 ? 'text-success' : health.score >= 50 ? 'text-warning' : 'text-destructive'
  const claude = data.agents?.claude
  const lock = data.sessionLock
  const corp = data.corporateReal

  return (
    <div className="space-y-6">
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        <MetricCard
          title="Controller Version"
          value={data.controllerVersion || '?'}
          icon={<Package className="w-5 h-5" />}
        />
        
        <MetricCard
          title="Agent Version"
          value={data.agentVersion || '?'}
          icon={<Package className="w-5 h-5" />}
        />
        
        <MetricCard
          title="Last Trigger Run"
          value={`#${data.lastTriggerRun || 0}`}
          icon={<NumberCircleOne className="w-5 h-5" />}
        />
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        {/* Pipeline */}
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Pulse className="w-5 h-5" />Pipeline</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-3">
              <StatusBadge status={data.pipelineStatus || 'idle'} className="text-base px-4 py-2" />
              {data.pipeline.currentStage && (
                <div className="text-sm text-muted-foreground">
                  Current stage: <span className="font-mono text-foreground">{data.pipeline.currentStage}</span>
                </div>
              )}
            </div>
            {data.pipeline?.commitMessage && <div className="text-xs text-muted-foreground mt-1 truncate">{data.pipeline.commitMessage}</div>}
          </CardContent>
        </Card>

        {/* Active Agent */}
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Robot className="w-5 h-5" />Active Agent</CardTitle></CardHeader>
          <CardContent>
            {claude?.status === 'active' ? (
              <>
                <div className="text-2xl font-bold font-mono mb-1">Claude</div>
                <div className="text-sm text-muted-foreground">{claude.task || 'Working...'}</div>
                {claude.phase && <div className="text-xs text-muted-foreground">Phase: {claude.phase}</div>}
              </>
            ) : (
              <>
                <div className="text-2xl font-bold font-mono text-muted-foreground">idle</div>
                <div className="text-sm text-muted-foreground">No agent active</div>
              </>
            )}
          </CardContent>
        </Card>

        {/* Session Lock */}
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Lock className="w-5 h-5" />Session Lock</CardTitle></CardHeader>
          <CardContent>
            {lock?.agentId && lock.agentId !== 'none' ? (
              <>
                <div className="text-lg font-bold font-mono text-warning">{lock.agentId}</div>
                <div className="text-sm text-muted-foreground">Op: {lock.operation || '?'}</div>
              </>
            ) : (
              <>
                <div className="flex items-center gap-2"><CheckCircle className="w-5 h-5 text-success" /><span className="text-success font-medium">Free</span></div>
                <div className="text-sm text-muted-foreground">No active lock</div>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <GitBranch className="w-5 h-5" />
            Last Deploy
          </CardTitle>
        </CardHeader>
        <CardContent>
          {data.lastDeploy ? (
            <div className="grid gap-4 md:grid-cols-3">
              <div>
                <div className="text-sm text-muted-foreground mb-1">Component</div>
                <div className="font-mono text-base">{data.lastDeploy.component}</div>
              </div>
              <div>
                <div className="text-sm text-muted-foreground mb-1">Status</div>
                <StatusBadge status={data.lastDeploy.status} />
              </div>
              <div>
                <div className="text-sm text-muted-foreground mb-1">Time</div>
                <div className="text-sm">
                  {formatDistanceToNowSaoPaulo(data.lastDeploy.date, { addSuffix: true })}
                </div>
              </div>
            </div>
          ) : (
            <div className="text-sm text-muted-foreground">No recent deploys</div>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Recent Deploys</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {data.deployHistory.slice(0, 5).map((deploy) => (
                <div key={deploy.id} className="flex items-center justify-between p-3 rounded-lg bg-muted/30">
                  <div className="flex-1">
                    <div className="font-mono text-sm font-semibold">{deploy.component}</div>
                    <div className="text-xs text-muted-foreground">{deploy.version}</div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-xs text-muted-foreground">{deploy.duration}</span>
                    <StatusBadge status={deploy.status} />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Active Workflows</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {(data.workflows || []).slice(0, 5).map((workflow) => (
                <div key={workflow.id} className="flex items-center justify-between p-3 rounded-lg bg-muted/30">
                  <div className="flex-1">
                    <div className="font-semibold text-sm">{workflow.name}</div>
                    <div className="text-xs text-muted-foreground font-mono">{workflow.branch}</div>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="font-mono text-xs text-muted-foreground">{workflow.duration}</span>
                    <StatusBadge status={workflow.status} />
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
