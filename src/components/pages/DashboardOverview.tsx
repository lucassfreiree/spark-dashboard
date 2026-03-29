import { DashboardState } from '@/types/dashboard'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatusBadge } from '@/components/StatusBadge'
import { MetricCard } from '@/components/MetricCard'
import { Package, Robot, GitBranch, Pulse, Lock, Warning, CheckCircle } from '@phosphor-icons/react'
import { useMemo } from 'react'

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
      {/* Drift Alert */}
      {(corp?.controller?.drift || corp?.agent?.drift) && (
        <div className="p-4 rounded-lg bg-destructive/10 border border-destructive/30 flex items-start gap-3">
          <Warning className="w-5 h-5 text-destructive mt-0.5" />
          <div>
            <div className="font-semibold text-destructive">Version Drift Detected</div>
            <div className="text-sm text-muted-foreground">
              {corp?.controller?.drift && <div>Controller: autopilot says {data.controller?.version} but real repo has {corp.controller.sourceVersion}</div>}
              {corp?.agent?.drift && <div>Agent: autopilot says {data.agent?.version} but real repo has {corp.agent.sourceVersion}</div>}
            </div>
          </div>
        </div>
      )}

      {/* Top metrics */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard title="Controller" value={data.controller?.version || '?'} icon={<Package className="w-5 h-5" />} />
        <MetricCard title="Agent" value={data.agent?.version || '?'} icon={<Package className="w-5 h-5" />} />
        <MetricCard title="Pipeline Run" value={`#${data.pipeline?.lastRun || 0}`} icon={<GitBranch className="w-5 h-5" />} />
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-muted-foreground">Health</CardTitle></CardHeader>
          <CardContent><div className={`text-3xl font-bold font-mono ${healthColor}`}>{health.score}</div><div className="text-xs text-muted-foreground mt-1">{health.reasons[0] || 'All systems OK'}</div></CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        {/* Pipeline */}
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Pulse className="w-5 h-5" />Pipeline</CardTitle></CardHeader>
          <CardContent>
            <StatusBadge status={data.pipeline?.status || 'idle'} className="text-base px-4 py-2" />
            <div className="text-sm text-muted-foreground mt-2">
              {data.pipeline?.component || '?'} v{data.pipeline?.version || '?'}
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

      {/* Corporate Real vs Autopilot */}
      {corp?.controller?.sourceVersion && corp.controller.sourceVersion !== '?' && (
        <Card>
          <CardHeader><CardTitle>Corporate Reality (Real Versions)</CardTitle></CardHeader>
          <CardContent>
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <div className="text-sm font-medium">Controller</div>
                <div className="flex items-center gap-2">
                  <span className="text-muted-foreground text-xs">Source:</span>
                  <span className={`font-mono font-bold ${corp.controller.drift ? 'text-destructive' : 'text-success'}`}>{corp.controller.sourceVersion}</span>
                  {corp.controller.drift && <StatusBadge status="failed" />}
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-muted-foreground text-xs">CAP tag:</span>
                  <span className="font-mono">{corp.controller.capTag}</span>
                </div>
              </div>
              <div className="space-y-2">
                <div className="text-sm font-medium">Agent</div>
                <div className="flex items-center gap-2">
                  <span className="text-muted-foreground text-xs">Source:</span>
                  <span className={`font-mono font-bold ${corp.agent?.drift ? 'text-destructive' : 'text-success'}`}>{corp.agent?.sourceVersion || '?'}</span>
                  {corp.agent?.drift && <StatusBadge status="failed" />}
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-muted-foreground text-xs">CAP tag:</span>
                  <span className="font-mono">{corp.agent?.capTag || '?'}</span>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Recent Workflows */}
      <Card>
        <CardHeader><CardTitle>Recent Workflows</CardTitle></CardHeader>
        <CardContent>
          <div className="space-y-2">
            {(data.recentWorkflows || []).slice(0, 5).map((wf, i) => (
              <div key={i} className="flex items-center justify-between p-3 rounded-lg bg-muted/30">
                <div className="flex-1 min-w-0">
                  {wf.url ? (
                    <a href={wf.url} target="_blank" rel="noopener noreferrer" className="font-semibold text-sm hover:underline truncate block">{wf.name}</a>
                  ) : (
                    <div className="font-semibold text-sm truncate">{wf.name}</div>
                  )}
                  <div className="text-xs text-muted-foreground font-mono">{wf.head_branch || ''}</div>
                </div>
                <StatusBadge status={wf.conclusion || wf.status || 'unknown'} />
              </div>
            ))}
            {(!data.recentWorkflows || data.recentWorkflows.length === 0) && (
              <div className="text-sm text-muted-foreground text-center py-4">No workflows data</div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
