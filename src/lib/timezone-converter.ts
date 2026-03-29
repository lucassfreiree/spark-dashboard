import { DashboardState } from '@/types/dashboard'

export function convertApiDataToSaoPauloTimezone(data: DashboardState): DashboardState {
  const converted = JSON.parse(JSON.stringify(data))

  if (converted.lastDeploy) {
    converted.lastDeploy = {
      ...converted.lastDeploy,
      date: new Date(converted.lastDeploy.date).toISOString(),
    }
  }

  if (converted.lastUpdated) {
    converted.lastUpdated = new Date(converted.lastUpdated).toISOString()
  }

  if (converted.deployHistory) {
    converted.deployHistory = converted.deployHistory.map((record: any) => ({
      ...record,
      date: new Date(record.date).toISOString(),
    }))
  }

  if (converted.agentActivity) {
    converted.agentActivity.timeline = converted.agentActivity.timeline.map((event: any) => ({
      ...event,
      timestamp: new Date(event.timestamp).toISOString(),
    }))

    converted.agentActivity.recentSessions = converted.agentActivity.recentSessions.map((session: any) => ({
      ...session,
      startTime: new Date(session.startTime).toISOString(),
      endTime: session.endTime ? new Date(session.endTime).toISOString() : undefined,
    }))
  }

  if (converted.workflows) {
    converted.workflows = converted.workflows.map((workflow: any) => ({
      ...workflow,
      lastRun: new Date(workflow.lastRun).toISOString(),
    }))
  }

  if (converted.pipeline?.stages) {
    converted.pipeline.stages = converted.pipeline.stages.map((stage: any) => ({
      ...stage,
      startTime: stage.startTime ? new Date(stage.startTime).toISOString() : undefined,
      endTime: stage.endTime ? new Date(stage.endTime).toISOString() : undefined,
    }))
  }

  return converted as DashboardState
}
