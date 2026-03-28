import { DashboardState } from '@/types/dashboard'
import { StatusBadge } from '@/components/StatusBadge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Separator } from '@/components/ui/separator'
import { Robot, Lightbulb } from '@phosphor-icons/react'
import { formatDistanceToNow, format } from 'date-fns'

interface AgentActivityProps {
  data: DashboardState
}

export function AgentActivity({ data }: AgentActivityProps) {
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Robot className="w-5 h-5" />
            Agent Timeline
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="relative space-y-4">
            <div className="absolute left-2 top-0 bottom-0 w-0.5 bg-border" />
            {data.agentActivity.timeline.map((event, idx) => (
              <div key={event.id} className="relative flex gap-4 pl-8">
                <div className={`absolute left-0 w-4 h-4 rounded-full border-2 ${
                  event.agent === 'Claude' ? 'bg-primary border-primary' :
                  event.agent === 'Copilot' ? 'bg-accent border-accent' :
                  'bg-muted border-muted'
                }`} />
                <div className="flex-1 pb-4">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-mono text-sm font-semibold">{event.agent}</span>
                    <span className="text-xs text-muted-foreground">
                      {formatDistanceToNow(new Date(event.timestamp), { addSuffix: true })}
                    </span>
                    {event.duration && (
                      <span className="text-xs font-mono text-muted-foreground">({event.duration})</span>
                    )}
                  </div>
                  <p className="text-sm text-foreground">{event.action}</p>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Recent Sessions</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Agent</TableHead>
                <TableHead>Start Time</TableHead>
                <TableHead>End Time</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Deploys</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.agentActivity.recentSessions.map((session) => (
                <TableRow key={session.id}>
                  <TableCell className="font-mono font-semibold">{session.agent}</TableCell>
                  <TableCell className="font-mono text-sm">
                    {format(new Date(session.startTime), 'MMM dd, HH:mm')}
                  </TableCell>
                  <TableCell className="font-mono text-sm">
                    {session.endTime ? format(new Date(session.endTime), 'MMM dd, HH:mm') : 'In progress'}
                  </TableCell>
                  <TableCell>
                    <StatusBadge status={session.status} />
                  </TableCell>
                  <TableCell className="font-mono">{session.deploysCount}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Lightbulb className="w-5 h-5" />
            Lessons Learned
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {data.agentActivity.lessonsLearned.map((lesson, idx) => (
            <div key={lesson.id}>
              {idx > 0 && <Separator className="mb-4" />}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <h4 className="font-semibold">{lesson.title}</h4>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono text-muted-foreground">{lesson.agent}</span>
                    <span className="text-xs text-muted-foreground">{lesson.date}</span>
                  </div>
                </div>
                <p className="text-sm text-muted-foreground">{lesson.description}</p>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}
