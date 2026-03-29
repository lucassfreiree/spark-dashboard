import { DashboardState } from '@/types/dashboard'

export function convertDashboardDatesToISO(data: DashboardState): DashboardState {
  const converted = { ...data }

  if (converted.lastDeploy?.date) {
    converted.lastDeploy.date = new Date(converted.lastDeploy.date).toISOString()
  }

  if (converted.deployHistory) {
    converted.deployHistory = converted.deployHistory.map((deploy: any) => ({
      ...deploy,
      date: new Date(deploy.date).toISOString(),
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

  return converted
}

export function convertApiDataToSaoPauloTimezone(data: DashboardState): DashboardState {
  return convertDashboardDatesToISO(data)
}
