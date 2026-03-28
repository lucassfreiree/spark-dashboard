import { DashboardState } from '@/types/dashboard'
import { MetricCard } from '@/components/MetricCard'
import { StatusBadge } from '@/components/StatusBadge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Package, Robot, GitBranch, Pulse, NumberCircleOne } from '@phosphor-icons/react'
import { formatDistanceToNow } from 'date-fns'

interface DashboardOverviewProps {
  data: DashboardState
}

export function DashboardOverview({ data }: DashboardOverviewProps) {
  return (
    <div className="space-y-6">
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        <MetricCard
          title="Controller Version"
          value={data.controllerVersion}
          icon={<Package className="w-5 h-5" />}
        />
        
        <MetricCard
          title="Agent Version"
          value={data.agentVersion}
          icon={<Package className="w-5 h-5" />}
        />
        
        <MetricCard
          title="Last Trigger Run"
          value={`#${data.lastTriggerRun}`}
          icon={<NumberCircleOne className="w-5 h-5" />}
        />
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Pulse className="w-5 h-5" />
              Pipeline Status
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <StatusBadge status={data.pipelineStatus} className="text-base px-4 py-2" />
              {data.pipeline.currentStage && (
                <div className="text-sm text-muted-foreground">
                  Current stage: <span className="font-mono text-foreground">{data.pipeline.currentStage}</span>
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Robot className="w-5 h-5" />
              Active Agent
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-mono mb-2">
              {data.activeAgent}
            </div>
            <div className="text-sm text-muted-foreground">
              {data.activeAgent === 'idle' ? 'No active sessions' : 'Currently processing deployments'}
            </div>
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
                {formatDistanceToNow(new Date(data.lastDeploy.date), { addSuffix: true })}
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
