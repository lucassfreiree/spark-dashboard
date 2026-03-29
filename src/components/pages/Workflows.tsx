import { DashboardState } from '@/types/dashboard'
import { StatusBadge } from '@/components/StatusBadge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { GitBranch } from '@phosphor-icons/react'
import { formatDistanceToNowSaoPaulo } from '@/lib/utils'

interface WorkflowsProps {
  data: DashboardState
}

export function Workflows({ data }: WorkflowsProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <GitBranch className="w-5 h-5" />
          GitHub Actions Workflows
        </CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Workflow</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Branch</TableHead>
              <TableHead>Last Run</TableHead>
              <TableHead>Duration</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(data.workflows || []).map((workflow) => (
              <TableRow key={workflow.id}>
                <TableCell className="font-semibold">{workflow.name}</TableCell>
                <TableCell>
                  <StatusBadge status={workflow.status} />
                </TableCell>
                <TableCell className="font-mono text-sm">{workflow.branch}</TableCell>
                <TableCell className="text-sm">
                  {formatDistanceToNowSaoPaulo(workflow.lastRun, { addSuffix: true })}
                </TableCell>
                <TableCell className="font-mono text-sm">{workflow.duration}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}
