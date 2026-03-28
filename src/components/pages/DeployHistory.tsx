import { useState, useMemo } from 'react'
import { DashboardState, DeployStatus } from '@/types/dashboard'
import { StatusBadge } from '@/components/StatusBadge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { ClockCounterClockwise } from '@phosphor-icons/react'
import { formatSaoPauloTime } from '@/lib/utils'

interface DeployHistoryProps {
  data: DashboardState
}

export function DeployHistory({ data }: DeployHistoryProps) {
  const [statusFilter, setStatusFilter] = useState<string>('all')
  const [componentFilter, setComponentFilter] = useState<string>('all')

  const filteredDeploys = useMemo(() => {
    return data.deployHistory.filter(deploy => {
      const matchesStatus = statusFilter === 'all' || deploy.status === statusFilter
      const matchesComponent = componentFilter === 'all' || deploy.component === componentFilter
      return matchesStatus && matchesComponent
    })
  }, [data.deployHistory, statusFilter, componentFilter])

  const uniqueComponents = useMemo(() => {
    const components = new Set(data.deployHistory.map(d => d.component))
    return Array.from(components)
  }, [data.deployHistory])

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row gap-4">
        <div className="w-full sm:w-48">
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger>
              <SelectValue placeholder="Filter by status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Status</SelectItem>
              <SelectItem value="success">Success</SelectItem>
              <SelectItem value="failed">Failed</SelectItem>
              <SelectItem value="running">Running</SelectItem>
              <SelectItem value="idle">Idle</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="w-full sm:w-48">
          <Select value={componentFilter} onValueChange={setComponentFilter}>
            <SelectTrigger>
              <SelectValue placeholder="Filter by component" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All Components</SelectItem>
              {uniqueComponents.map(comp => (
                <SelectItem key={comp} value={comp}>{comp}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <ClockCounterClockwise className="w-5 h-5" />
            Deploy History ({filteredDeploys.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead>
                <TableHead>Component</TableHead>
                <TableHead>Version</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Run</TableHead>
                <TableHead>Duration</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredDeploys.map((deploy) => (
                <TableRow key={deploy.id}>
                  <TableCell className="font-mono text-sm">
                    {formatSaoPauloTime(deploy.date, 'dd/MM/yy HH:mm')}
                  </TableCell>
                  <TableCell className="font-mono">{deploy.component}</TableCell>
                  <TableCell className="font-mono text-sm">{deploy.version}</TableCell>
                  <TableCell>
                    <StatusBadge status={deploy.status} />
                  </TableCell>
                  <TableCell className="font-mono">#{deploy.run}</TableCell>
                  <TableCell className="font-mono text-sm">{deploy.duration}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
